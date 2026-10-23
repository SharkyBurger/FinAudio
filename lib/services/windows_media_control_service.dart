import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path/path.dart' as p;
import 'package:windows_taskbar/windows_taskbar.dart';

import 'player_service.dart';

/// Centralized Windows Media Key & Taskbar Thumbnail Controls Service.
///
/// Provides:
/// 1. Global & In-App Keyboard Media Key handling (Play/Pause, Next Track, Previous Track, Stop).
/// 2. Windows Taskbar Thumbnail preview toolbar buttons (Prev, Play/Pause, Next) and peek tooltip.
class WindowsMediaControlService {
  WindowsMediaControlService._internal();
  static final WindowsMediaControlService instance =
      WindowsMediaControlService._internal();

  PlayerService? _playerService;
  StreamSubscription<Track?>? _nowPlayingSub;
  StreamSubscription<bool>? _playingSub;

  bool _initialized = false;
  final List<HotKey> _registeredHotKeys = [];

  /// Attaches the PlayerService and initializes Windows hooks if on Windows.
  Future<void> attach({required PlayerService playerService}) async {
    _playerService = playerService;

    if (!Platform.isWindows || kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    if (!_initialized) {
      _initialized = true;
      _initKeyboardHandlers();
      await _initGlobalHotKeys();
    }

    _nowPlayingSub?.cancel();
    _nowPlayingSub = playerService.nowPlayingStream.listen((_) {
      _updateTaskbarToolbar();
    });

    _playingSub?.cancel();
    _playingSub = playerService.playingStream.listen((_) {
      _updateTaskbarToolbar();
    });

    // Initial toolbar population
    _updateTaskbarToolbar();
  }

  /// Sets up in-app focused hardware keyboard listeners for media keys.
  void _initKeyboardHandlers() {
    HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
  }

  bool _onHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.mediaPlayPause) {
      _handlePlayPause();
      return true;
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      _handlePlay();
      return true;
    } else if (key == LogicalKeyboardKey.mediaPause) {
      _handlePause();
      return true;
    } else if (key == LogicalKeyboardKey.mediaTrackNext) {
      _handleNext();
      return true;
    } else if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      _handlePrevious();
      return true;
    } else if (key == LogicalKeyboardKey.mediaStop) {
      _handleStop();
      return true;
    }

    return false;
  }

  /// Sets up OS-level global hotkeys using `hotkey_manager` so media keys
  /// work even when FinAudio is minimized or in the background.
  Future<void> _initGlobalHotKeys() async {
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}

    final keysToRegister = [
      PhysicalKeyboardKey.mediaPlayPause,
      PhysicalKeyboardKey.mediaTrackNext,
      PhysicalKeyboardKey.mediaTrackPrevious,
      PhysicalKeyboardKey.mediaStop,
      PhysicalKeyboardKey.mediaSelect,
    ];

    for (final physicalKey in keysToRegister) {
      try {
        final hotKey = HotKey(
          key: physicalKey,
          scope: HotKeyScope.system,
        );
        await hotKeyManager.register(
          hotKey,
          keyDownHandler: (_) {
            if (physicalKey == PhysicalKeyboardKey.mediaPlayPause ||
                physicalKey == PhysicalKeyboardKey.mediaSelect) {
              _handlePlayPause();
            } else if (physicalKey == PhysicalKeyboardKey.mediaTrackNext) {
              _handleNext();
            } else if (physicalKey == PhysicalKeyboardKey.mediaTrackPrevious) {
              _handlePrevious();
            } else if (physicalKey == PhysicalKeyboardKey.mediaStop) {
              _handleStop();
            }
          },
        );
        _registeredHotKeys.add(hotKey);
      } catch (e) {
        if (kDebugMode) {
          print('WindowsMediaControlService: Notice - could not register $physicalKey: $e');
        }
      }
    }
  }

  void _handlePlayPause() {
    _playerService?.togglePlayPause();
  }

  void _handlePlay() {
    _playerService?.resume();
  }

  void _handlePause() {
    _playerService?.pause();
  }

  void _handleNext() {
    _playerService?.nextTrack();
  }

  void _handlePrevious() {
    _playerService?.previousTrack();
  }

  void _handleStop() {
    _playerService?.pause();
  }

  /// Dynamically updates Windows taskbar thumbnail buttons & tooltip.
  void _updateTaskbarToolbar() {
    if (!Platform.isWindows || kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    final player = _playerService;
    if (player == null) return;

    final isPlaying = player.isPlaying;
    final track = player.currentTrack;

    try {
      final baseDir = p.dirname(Platform.resolvedExecutable);
      final assetDir = p.join(baseDir, 'data', 'flutter_assets');

      final prevFile = File(p.join(assetDir, 'assets', 'icons', 'prev.ico'));
      final playFile = File(p.join(assetDir, 'assets', 'icons', 'play.ico'));
      final pauseFile = File(p.join(assetDir, 'assets', 'icons', 'pause.ico'));
      final nextFile = File(p.join(assetDir, 'assets', 'icons', 'next.ico'));

      // If icon files don't exist yet (e.g. running outside standard build folder), skip gracefully
      if (!prevFile.existsSync() ||
          !playFile.existsSync() ||
          !pauseFile.existsSync() ||
          !nextFile.existsSync()) {
        return;
      }

      final playPauseIcon = isPlaying ? 'assets/icons/pause.ico' : 'assets/icons/play.ico';
      final playPauseTooltip = isPlaying ? 'Pause' : 'Play';

      WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/prev.ico'),
          'Previous Track',
          () => _handlePrevious(),
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(playPauseIcon),
          playPauseTooltip,
          () => _handlePlayPause(),
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/icons/next.ico'),
          'Next Track',
          () => _handleNext(),
        ),
      ]);

      if (track != null) {
        WindowsTaskbar.setThumbnailTooltip('${track.title} • ${track.formattedArtist}');
      } else {
        WindowsTaskbar.setThumbnailTooltip('FinAudio');
      }
    } catch (e) {
      if (kDebugMode) {
        print('WindowsMediaControlService: Taskbar toolbar update failed: $e');
      }
    }
  }

  /// Cleans up subscriptions, hotkeys, and taskbar toolbars.
  Future<void> dispose() async {
    _nowPlayingSub?.cancel();
    _playingSub?.cancel();
    _nowPlayingSub = null;
    _playingSub = null;

    if (!Platform.isWindows || kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);

    try {
      for (final hotKey in _registeredHotKeys) {
        await hotKeyManager.unregister(hotKey);
      }
      _registeredHotKeys.clear();
      await hotKeyManager.unregisterAll();
    } catch (_) {}

    try {
      await WindowsTaskbar.resetThumbnailToolbar();
      await WindowsTaskbar.setThumbnailTooltip('');
    } catch (_) {}

    _initialized = false;
  }
}
