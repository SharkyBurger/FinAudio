import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'youtube_service.dart';

/// A single playable track resolved from YouTube.
class Track {
  final String id;
  final String title;
  final String author;
  final String youtubeUrl;
  final Uri streamUrl;
  final Duration duration;

  const Track({
    required this.id,
    required this.title,
    required this.author,
    required this.youtubeUrl,
    required this.streamUrl,
    required this.duration,
  });
}

/// Playback modes for the loop control.
enum LoopMode { off, one, all }

/// Centralized player + queue used by both the Player tab and the Playlists
/// tab. This keeps "now playing" consistent across the app and gives us
/// replay / loop / shuffle controls without each tab owning its own Player.
class PlayerService {
  /// Browser-like headers required by YouTube's CDN, otherwise it returns 403.
  static const Map<String, String> _streamHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/125.0.0.0 Safari/537.36',
    'Referer': 'https://www.youtube.com/',
  };

  final YoutubeService _yt = YoutubeService();
  final Player _player = Player();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  final StreamController<Track?> _nowPlayingController =
      StreamController<Track?>.broadcast();
  final StreamController<LoopMode> _loopModeController =
      StreamController<LoopMode>.broadcast();
  final StreamController<bool> _shuffleController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  Track? _currentTrack;
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleEnabled = false;
  final List<Track> _queue = [];
  final List<Track> _originalQueue = []; // before shuffle
  int _currentIndex = -1;

  bool _disposed = false;

  PlayerService() {
    _player.stream.playing.listen((playing) {
      if (!_disposed) _playingController.add(playing);
    });
    _player.stream.position.listen((pos) {
      _position = pos;
      if (!_disposed) _positionController.add(pos);
    });
    _player.stream.duration.listen((dur) {
      _duration = dur;
      if (!_disposed) _durationController.add(dur);
    });
    _player.stream.completed.listen((completed) {
      if (completed) {
        onTrackEnd();
      }
    });
  }

  // ---------------------------------------------------------------
  // Public streams for UI
  // ---------------------------------------------------------------

  Stream<Track?> get nowPlayingStream => _nowPlayingController.stream;
  Stream<LoopMode> get loopModeStream => _loopModeController.stream;
  Stream<bool> get shuffleStream => _shuffleController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  /// Current track (synced with the player).
  Track? get currentTrack => _currentTrack;

  /// Current playback position.
  Duration get position => _position;

  /// Media duration (only valid once resolved).
  Duration get duration => _duration;

  /// Whether the player is currently playing.
  bool get isPlaying => _player.state.playing;

  /// Current loop mode.
  LoopMode get loopMode => _loopMode;

  /// Whether shuffle is enabled.
  bool get shuffleEnabled => _shuffleEnabled;

  // ---------------------------------------------------------------
  // Playback actions
  // ---------------------------------------------------------------

  /// Resolve a YouTube URL / video ID to a [Track] and start playback.
  /// Replaces the current queue with a single-track queue by default.
  Future<Track> play(String input, {bool replaceQueue = true}) async {
    final resolved = await _yt.resolveAudioStream(input);
    final track = Track(
      id: resolved.videoUrl.split('v=').last.split('&').first,
      title: resolved.title,
      author: resolved.author,
      youtubeUrl: resolved.videoUrl,
      streamUrl: resolved.audioStreamUrl,
      duration: resolved.duration,
    );

    await _enqueueAndPlay([track], startIndex: 0, replaceQueue: replaceQueue);
    return track;
  }

  /// Enqueue tracks and start playback from [startIndex]. If [replaceQueue]
  /// is true, the existing queue is cleared first.
  Future<void> playList(
    List<Track> tracks, {
    int startIndex = 0,
    bool replaceQueue = true,
  }) async {
    await _enqueueAndPlay(
      tracks,
      startIndex: startIndex,
      replaceQueue: replaceQueue,
    );
  }

  /// Toggle play/pause for the current track.
  void togglePlayPause() {
    if (_player.state.playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  /// Stop playback and clear "now playing" state.
  void stop() {
    _player.stop();
    _currentTrack = null;
    _currentIndex = -1;
    _queue.clear();
    _originalQueue.clear();
    _emitNowPlaying(null);
  }

  /// Replay the current track from the start.
  void replay() {
    if (_currentTrack != null) {
      _player.seek(Duration.zero);
      _player.play();
    }
  }

  /// Skip to the next track in the queue.
  Future<void> nextTrack() async {
    if (_queue.isEmpty) return;

    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      _currentTrack = _queue[_currentIndex];
      _emitNowPlaying(_currentTrack);
      try {
        await _playTrack(_currentTrack!);
      } catch (e) {
        debugPrint('PlayerService: failed to play next track: $e');
      }
    } else if (_loopMode == LoopMode.all) {
      // Loop all: wrap to start
      _currentIndex = 0;
      _currentTrack = _queue[0];
      _emitNowPlaying(_currentTrack);
      try {
        await _playTrack(_currentTrack!);
      } catch (e) {
        debugPrint('PlayerService: failed to loop to start: $e');
      }
    }
  }

  /// Skip to the previous track in the queue.
  Future<void> previousTrack() async {
    if (_queue.isEmpty) return;

    // If more than 3 seconds into the song, restart it instead.
    if (_position.inSeconds > 3) {
      _player.seek(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
    } else if (_loopMode == LoopMode.all) {
      _currentIndex = _queue.length - 1;
    } else {
      _player.seek(Duration.zero);
      return;
    }

    _currentTrack = _queue[_currentIndex];
    _emitNowPlaying(_currentTrack);
    try {
      await _playTrack(_currentTrack!);
    } catch (e) {
      debugPrint('PlayerService: failed to play previous track: $e');
    }
  }

  /// Toggle shuffle on/off. When enabling, randomize the queue order (keeping
  /// the current track at index 0). When disabling, restore original order.
  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;

    if (_shuffleEnabled) {
      // Save original order
      _originalQueue.clear();
      _originalQueue.addAll(_queue);

      // Shuffle, but keep current track at front
      final current = _currentTrack;
      final others = _queue.where((t) => t.id != current?.id).toList();
      others.shuffle(Random());

      _queue.clear();
      if (current != null) _queue.add(current);
      _queue.addAll(others);
      _currentIndex = 0;
    } else {
      // Restore original order, keeping current track position
      final current = _currentTrack;
      _queue.clear();
      _queue.addAll(_originalQueue);
      _originalQueue.clear();

      if (current != null) {
        _currentIndex = _queue.indexWhere((t) => t.id == current.id);
        if (_currentIndex == -1) _currentIndex = 0;
      }
    }

    if (!_disposed) _shuffleController.add(_shuffleEnabled);
  }

  /// Cycle loop mode: off -> one -> all -> off.
  void cycleLoopMode() {
    _loopMode = switch (_loopMode) {
      LoopMode.off => LoopMode.one,
      LoopMode.one => LoopMode.all,
      LoopMode.all => LoopMode.off,
    };
    _emitLoopMode();
  }

  /// Seek to [position].
  void seek(Duration position) {
    _player.seek(position);
  }

  // ---------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------

  /// Play a single track using media_kit's AudioPlayer with proper headers.
  Future<void> _playTrack(Track track) async {
    await _player.open(
      Media(
        track.streamUrl.toString(),
        httpHeaders: _streamHeaders,
      ),
    );
  }

  Future<void> _enqueueAndPlay(
    List<Track> tracks, {
    required int startIndex,
    required bool replaceQueue,
  }) async {
    if (replaceQueue) {
      _queue.clear();
      _originalQueue.clear();
    }
    _queue.addAll(tracks);
    if (replaceQueue) _originalQueue.addAll(tracks);

    if (_queue.isEmpty) return;

    final index =
        (startIndex >= 0 && startIndex < _queue.length) ? startIndex : 0;
    _currentIndex = index;
    _currentTrack = _queue[index];

    _emitNowPlaying(_currentTrack);

    try {
      await _playTrack(_currentTrack!);
    } catch (e) {
      debugPrint('PlayerService: failed to play track: $e');
      _emitError('Playback failed: $e');
    }
  }

  void _emitNowPlaying(Track? track) {
    if (_disposed) return;
    _nowPlayingController.add(track);
  }

  void _emitLoopMode() {
    if (_disposed) return;
    _loopModeController.add(_loopMode);
  }

  void _emitError(String message) {
    if (_disposed) return;
    _errorController.add(message);
  }

  /// Called automatically when AudioPlayer finishes a track.
  Future<void> onTrackEnd() async {
    if (_disposed || _currentTrack == null) return;

    if (_loopMode == LoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }

    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      _currentTrack = _queue[_currentIndex];
      _emitNowPlaying(_currentTrack);
      try {
        await _playTrack(_currentTrack!);
      } catch (e) {
        debugPrint('PlayerService: failed to play next track: $e');
      }
      return;
    }

    if (_loopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      _currentTrack = _queue[0];
      _emitNowPlaying(_currentTrack);
      try {
        await _playTrack(_currentTrack!);
      } catch (e) {
        debugPrint('PlayerService: failed to loop all: $e');
      }
      return;
    }

    // No more tracks and no loop: stop.
    _player.stop();
    _currentTrack = null;
    _currentIndex = -1;
    _queue.clear();
    _emitNowPlaying(null);
  }

  /// Current queue (for display in a minimal "up next" UI).
  List<Track> get queue => List.unmodifiable(_queue);

  /// Removes a track from the queue by id, if present.
  void removeFromQueue(String trackId) {
    final index = _queue.indexWhere((t) => t.id == trackId);
    if (index == -1) return;
    _queue.removeAt(index);

    if (_queue.isEmpty) {
      _currentTrack = null;
      _currentIndex = -1;
      _emitNowPlaying(null);
      _player.stop();
      return;
    }

    // If we removed the currently playing track, move to the next available
    // one at the same index (or the previous one if we were at the end).
    if (_currentTrack != null && _currentTrack!.id == trackId) {
      final nextIndex = index < _queue.length ? index : _queue.length - 1;
      _currentIndex = nextIndex;
      _currentTrack = _queue[nextIndex];
      _emitNowPlaying(_currentTrack);
      _playTrack(_currentTrack!).catchError((e) {
        debugPrint('PlayerService: failed to play removed-track replacement: $e');
      });
    }
  }

  /// Releases resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _player.dispose();
    _yt.dispose();
    _nowPlayingController.close();
    _loopModeController.close();
    _shuffleController.close();
    _playingController.close();
    _errorController.close();
    _positionController.close();
    _durationController.close();
  }
}
