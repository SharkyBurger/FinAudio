#include "flutter_window.h"

#include <chrono>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

HHOOK FlutterWindow::keyboard_hook_ = nullptr;
FlutterWindow* FlutterWindow::instance_ = nullptr;

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::SetupMediaKeysChannel() {
  if (!flutter_controller_ || !flutter_controller_->engine()) return;

  media_keys_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "finaudio/windows_media_keys",
          &flutter::StandardMethodCodec::GetInstance());
}

void FlutterWindow::TearDownMediaKeysChannel() {
  media_keys_channel_ = nullptr;
}

void FlutterWindow::DispatchMediaKey(const std::string& action) {
  static auto last_time = std::chrono::steady_clock::now();
  static std::string last_action = "";
  auto now = std::chrono::steady_clock::now();
  auto elapsed_ms =
      std::chrono::duration_cast<std::chrono::milliseconds>(now - last_time)
          .count();

  // Debounce rapid duplicate events within 180ms
  if (last_action == action && elapsed_ms < 180) {
    return;
  }
  last_time = now;
  last_action = action;

  if (instance_ && instance_->media_keys_channel_) {
    instance_->media_keys_channel_->InvokeMethod(
        "onMediaKey", std::make_unique<flutter::EncodableValue>(action));
  }
}

LRESULT CALLBACK FlutterWindow::LowLevelKeyboardProc(int nCode, WPARAM wParam,
                                                    LPARAM lParam) {
  if (nCode == HC_ACTION &&
      (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
    KBDLLHOOKSTRUCT* pKey = reinterpret_cast<KBDLLHOOKSTRUCT*>(lParam);
    if (pKey != nullptr) {
      if (pKey->vkCode == VK_MEDIA_PLAY_PAUSE) {
        DispatchMediaKey("playPause");
      } else if (pKey->vkCode == VK_MEDIA_NEXT_TRACK) {
        DispatchMediaKey("nextTrack");
      } else if (pKey->vkCode == VK_MEDIA_PREV_TRACK) {
        DispatchMediaKey("previousTrack");
      } else if (pKey->vkCode == VK_MEDIA_STOP) {
        DispatchMediaKey("stop");
      }
    }
  }
  return CallNextHookEx(keyboard_hook_, nCode, wParam, lParam);
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  instance_ = this;
  SetupMediaKeysChannel();

  // Install system-wide low-level keyboard hook so media keys work when backgrounded
  keyboard_hook_ = SetWindowsHookEx(
      WH_KEYBOARD_LL, LowLevelKeyboardProc, GetModuleHandle(nullptr), 0);

  // Register Win32 hotkeys as well
  HWND hwnd = GetHandle();
  if (hwnd) {
    RegisterHotKey(hwnd, 9001, MOD_NOREPEAT, VK_MEDIA_PLAY_PAUSE);
    RegisterHotKey(hwnd, 9002, MOD_NOREPEAT, VK_MEDIA_NEXT_TRACK);
    RegisterHotKey(hwnd, 9003, MOD_NOREPEAT, VK_MEDIA_PREV_TRACK);
    RegisterHotKey(hwnd, 9004, MOD_NOREPEAT, VK_MEDIA_STOP);
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (keyboard_hook_) {
    UnhookWindowsHookEx(keyboard_hook_);
    keyboard_hook_ = nullptr;
  }

  HWND hwnd = GetHandle();
  if (hwnd) {
    UnregisterHotKey(hwnd, 9001);
    UnregisterHotKey(hwnd, 9002);
    UnregisterHotKey(hwnd, 9003);
    UnregisterHotKey(hwnd, 9004);
  }

  TearDownMediaKeysChannel();
  instance_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    case WM_APPCOMMAND: {
      DWORD cmd = GET_APPCOMMAND_LPARAM(lparam);
      switch (cmd) {
        case APPCOMMAND_MEDIA_PLAY_PAUSE:
          DispatchMediaKey("playPause");
          return TRUE;
        case APPCOMMAND_MEDIA_PLAY:
          DispatchMediaKey("play");
          return TRUE;
        case APPCOMMAND_MEDIA_PAUSE:
          DispatchMediaKey("pause");
          return TRUE;
        case APPCOMMAND_MEDIA_NEXTTRACK:
          DispatchMediaKey("nextTrack");
          return TRUE;
        case APPCOMMAND_MEDIA_PREVIOUSTRACK:
          DispatchMediaKey("previousTrack");
          return TRUE;
        case APPCOMMAND_MEDIA_STOP:
          DispatchMediaKey("stop");
          return TRUE;
      }
      break;
    }

    case WM_HOTKEY: {
      int id = static_cast<int>(wparam);
      if (id == 9001) {
        DispatchMediaKey("playPause");
        return 0;
      } else if (id == 9002) {
        DispatchMediaKey("nextTrack");
        return 0;
      } else if (id == 9003) {
        DispatchMediaKey("previousTrack");
        return 0;
      } else if (id == 9004) {
        DispatchMediaKey("stop");
        return 0;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
