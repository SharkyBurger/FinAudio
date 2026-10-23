import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:windows_taskbar/windows_taskbar.dart';

import 'player_service.dart';

/// Centralized Windows Media Key & Taskbar Thumbnail Controls Service.
///
/// Provides:
/// 1. System-wide & Background Media Key handling (Play/Pause, Next Track, Previous Track, Stop).
/// 2. In-App Hardware Keyboard Media Key handling.
/// 3. Windows Taskbar Thumbnail preview toolbar buttons (Prev, Play/Pause, Next) and peek tooltip.
class WindowsMediaControlService {
  WindowsMediaControlService._internal();
  static final WindowsMediaControlService instance =
      WindowsMediaControlService._internal();

  static const MethodChannel _mediaKeysChannel =
      MethodChannel('finaudio/windows_media_keys');

  PlayerService? _playerService;
  StreamSubscription<Track?>? _nowPlayingSub;
  StreamSubscription<bool>? _playingSub;
  Timer? _retryTimer;

  bool _initialized = false;
  DateTime _lastActionTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastActionName = '';

  /// Attaches the PlayerService and initializes Windows hooks if on Windows.
  Future<void> attach({required PlayerService playerService}) async {
    _playerService = playerService;

    if (!Platform.isWindows || kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    if (!_initialized) {
      _initialized = true;
      _initKeyboardHandlers();
      _initNativeMethodChannel();
    }

    _nowPlayingSub?.cancel();
    _nowPlayingSub = playerService.nowPlayingStream.listen((_) {
      _updateTaskbarToolbar();
    });

    _playingSub?.cancel();
    _playingSub = playerService.playingStream.listen((_) {
      _updateTaskbarToolbar();
    });

    // Defer initial toolbar setup until window is rendered and shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(milliseconds: 800), () {
        _updateTaskbarToolbar();
      });
    });
  }

  /// Sets up native background method channel from the Windows runner.
  void _initNativeMethodChannel() {
    _mediaKeysChannel.setMethodCallHandler((call) async {
      if (call.method == 'onMediaKey') {
        final action = call.arguments as String?;
        switch (action) {
          case 'playPause':
            _handlePlayPause();
            break;
          case 'play':
            _handlePlay();
            break;
          case 'pause':
            _handlePause();
            break;
          case 'nextTrack':
            _handleNext();
            break;
          case 'previousTrack':
            _handlePrevious();
            break;
          case 'stop':
            _handleStop();
            break;
        }
      }
    });
  }

  /// Sets up hardware keyboard listeners for focused media keys.
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

  bool _debounce(String action) {
    final now = DateTime.now();
    if (_lastActionName == action &&
        now.difference(_lastActionTime).inMilliseconds < 200) {
      return false;
    }
    _lastActionName = action;
    _lastActionTime = now;
    return true;
  }

  void _handlePlayPause() {
    if (!_debounce('playPause')) return;
    _playerService?.togglePlayPause();
  }

  void _handlePlay() {
    if (!_debounce('play')) return;
    _playerService?.resume();
  }

  void _handlePause() {
    if (!_debounce('pause')) return;
    _playerService?.pause();
  }

  void _handleNext() {
    if (!_debounce('next')) return;
    _playerService?.nextTrack();
  }

  void _handlePrevious() {
    if (!_debounce('prev')) return;
    _playerService?.previousTrack();
  }

  void _handleStop() {
    if (!_debounce('stop')) return;
    _playerService?.pause();
  }

  /// Dynamically updates Windows taskbar thumbnail buttons & tooltip safely.
  Future<void> _updateTaskbarToolbar() async {
    if (!Platform.isWindows || kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    final player = _playerService;
    if (player == null) return;

    try {
      final isVisible =
          await WindowsTaskbar.isTaskbarVisible().catchError((_) => false);
      if (!isVisible) {
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(milliseconds: 1000), () {
          _updateTaskbarToolbar();
        });
        return;
      }

      final isPlaying = player.isPlaying;
      final track = player.currentTrack;

      final baseDir = p.dirname(Platform.resolvedExecutable);
      final assetDir = p.join(baseDir, 'data', 'flutter_assets');

      final prevFile = File(p.join(assetDir, 'assets', 'icons', 'prev.ico'));
      final playFile = File(p.join(assetDir, 'assets', 'icons', 'play.ico'));
      final pauseFile = File(p.join(assetDir, 'assets', 'icons', 'pause.ico'));
      final nextFile = File(p.join(assetDir, 'assets', 'icons', 'next.ico'));

      // If icon files don't exist yet (e.g. running in test/dev), skip gracefully
      if (!prevFile.existsSync() ||
          !playFile.existsSync() ||
          !pauseFile.existsSync() ||
          !nextFile.existsSync()) {
        return;
      }

      final playPauseIcon =
          isPlaying ? 'assets/icons/pause.ico' : 'assets/icons/play.ico';
      final playPauseTooltip = isPlaying ? 'Pause' : 'Play';

      await WindowsTaskbar.setThumbnailToolbar([
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
      ]).catchError((e) {
        if (kDebugMode) {
          print('WindowsMediaControlService: setThumbnailToolbar error: $e');
        }
      });

      final tooltip = track != null
          ? '${track.title} • ${track.formattedArtist}'
          : 'FinAudio';
      await WindowsTaskbar.setThumbnailTooltip(tooltip).catchError((_) {});
    } catch (e) {
      if (kDebugMode) {
        print('WindowsMediaControlService: Taskbar toolbar update failed: $e');
      }
    }
  }

  /// Cleans up subscriptions, timers, method channels, and taskbar toolbars.
  Future<void> dispose() async {
    _retryTimer?.cancel();
    _retryTimer = null;

    _nowPlayingSub?.cancel();
    _playingSub?.cancel();
    _nowPlayingSub = null;
    _playingSub = null;

    if (!Platform.isWindows || kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    _mediaKeysChannel.setMethodCallHandler(null);
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);

    try {
      await WindowsTaskbar.resetThumbnailToolbar().catchError((_) {});
      await WindowsTaskbar.setThumbnailTooltip('').catchError((_) {});
    } catch (_) {}

    _initialized = false;
  }
}
