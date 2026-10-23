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
/// 1. Keyboard Media Key handling (Play/Pause, Next Track, Previous Track, Stop).
/// 2. Windows Taskbar Thumbnail preview toolbar buttons (Prev, Play/Pause, Next) and peek tooltip.
class WindowsMediaControlService {
  WindowsMediaControlService._internal();
  static final WindowsMediaControlService instance =
      WindowsMediaControlService._internal();

  PlayerService? _playerService;
  StreamSubscription<Track?>? _nowPlayingSub;
  StreamSubscription<bool>? _playingSub;
  Timer? _retryTimer;

  bool _initialized = false;

  /// Attaches the PlayerService and initializes Windows hooks if on Windows.
  Future<void> attach({required PlayerService playerService}) async {
    _playerService = playerService;

    if (!Platform.isWindows || kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    if (!_initialized) {
      _initialized = true;
      _initKeyboardHandlers();
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

  /// Sets up hardware keyboard listeners for media keys.
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

  /// Cleans up subscriptions, timers, and taskbar toolbars.
  Future<void> dispose() async {
    _retryTimer?.cancel();
    _retryTimer = null;

    _nowPlayingSub?.cancel();
    _playingSub?.cancel();
    _nowPlayingSub = null;
    _playingSub = null;

    if (!Platform.isWindows || kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);

    try {
      await WindowsTaskbar.resetThumbnailToolbar().catchError((_) {});
      await WindowsTaskbar.setThumbnailTooltip('').catchError((_) {});
    } catch (_) {}

    _initialized = false;
  }
}
