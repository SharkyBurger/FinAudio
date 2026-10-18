import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../models/local_playlist.dart';
import 'download_service.dart';
import 'history_service.dart';
import 'playlist_service.dart';
import 'settings_service.dart';
import 'spotify_service.dart';
import 'stream_proxy_service.dart';
import 'youtube_service.dart';

/// A single playable track.
class Track {
  final String id;
  final String title;
  final String author;
  final String youtubeUrl;
  final Duration duration;
  final Uri? streamUrl;
  final String? thumbnailUrl;
  final String? localThumbnailPath;
  final String? audioCodec;
  final int? bitrate;

  Track({
    required this.id,
    required this.title,
    required this.author,
    required this.youtubeUrl,
    required this.duration,
    this.streamUrl,
    this.thumbnailUrl,
    this.localThumbnailPath,
    this.audioCodec,
    this.bitrate,
  });

  Track copyWith({
    String? id,
    String? title,
    String? author,
    String? youtubeUrl,
    Duration? duration,
    Uri? streamUrl,
    String? thumbnailUrl,
    String? localThumbnailPath,
    String? audioCodec,
    int? bitrate,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      duration: duration ?? this.duration,
      streamUrl: streamUrl ?? this.streamUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      localThumbnailPath: localThumbnailPath ?? this.localThumbnailPath,
      audioCodec: audioCodec ?? this.audioCodec,
      bitrate: bitrate ?? this.bitrate,
    );
  }

  /// Returns true if this track has a valid locally stored thumbnail file on disk.
  bool get hasLocalThumbnail => resolvedLocalThumbnailFile != null;

  /// Resolves the local thumbnail file if it exists on the device filesystem.
  File? get resolvedLocalThumbnailFile {
    if (localThumbnailPath != null && localThumbnailPath!.isNotEmpty) {
      final f = File(localThumbnailPath!);
      if (f.existsSync()) return f;
    }
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      if (thumbnailUrl!.startsWith('file://')) {
        try {
          final f = File(Uri.parse(thumbnailUrl!).toFilePath());
          if (f.existsSync()) return f;
        } catch (_) {}
      } else if (!thumbnailUrl!.startsWith('http://') && !thumbnailUrl!.startsWith('https://')) {
        final f = File(thumbnailUrl!);
        if (f.existsSync()) return f;
      }
    }
    return null;
  }

  /// Public HTTP/HTTPS thumbnail URL safe for external services like Discord RPC.
  String? get publicThumbnailUrl {
    if (thumbnailUrl != null &&
        (thumbnailUrl!.startsWith('http://') || thumbnailUrl!.startsWith('https://'))) {
      return thumbnailUrl;
    }
    if (id.length == 11 && !id.contains(' ') && !id.startsWith('spotify:')) {
      return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
    }
    if (youtubeUrl.isNotEmpty) {
      final reg = RegExp(r'(?:v=|\/|youtu\.be\/)([0-9A-Za-z_-]{11})');
      final m = reg.firstMatch(youtubeUrl);
      if (m != null) {
        return 'https://img.youtube.com/vi/${m.group(1)}/hqdefault.jpg';
      }
    }
    return null;
  }

  /// Creates a lightweight track from playlist metadata.
  factory Track.fromPlaylistVideo({
    required String videoId,
    required String title,
    required String author,
    required Duration duration,
    String? thumbnailUrl,
  }) {
    return Track(
      id: videoId,
      title: title,
      author: author,
      youtubeUrl: 'https://www.youtube.com/watch?v=$videoId',
      duration: duration,
      thumbnailUrl: thumbnailUrl,
    );
  }

  /// Returns individual artist names parsed from [author].
  List<String> get individualArtists => LocalPlaylistTrack.splitArtists(author);

  /// Returns a clean human-readable artist string formatted with commas.
  String get formattedArtist {
    final list = individualArtists;
    return list.isNotEmpty ? list.join(', ') : author;
  }

  /// Creates a track from a local or imported Spotify playlist track.
  /// Lightweight and non-blocking: offline cache checking is handled just-in-time
  /// when playback starts or preloads to keep playlist enqueuing instantaneous.
  factory Track.fromLocalPlaylistTrack(LocalPlaylistTrack track) {
    final hasYtId = track.youtubeVideoId != null && track.youtubeVideoId!.isNotEmpty;
    final id = hasYtId ? track.youtubeVideoId! : (track.spotifyUri ?? 'track_${track.title.hashCode}');
    return Track(
      id: id,
      title: track.title,
      author: track.artist,
      youtubeUrl: hasYtId ? 'https://www.youtube.com/watch?v=${track.youtubeVideoId}' : '',
      duration: track.duration,
      thumbnailUrl: track.thumbnailUrl,
    );
  }

  /// Converts this playable track to a LocalPlaylistTrack.
  LocalPlaylistTrack toLocalPlaylistTrack() {
    return LocalPlaylistTrack(
      title: title,
      artist: author,
      duration: duration,
      youtubeVideoId: id.isNotEmpty ? id : null,
      thumbnailUrl: thumbnailUrl,
    );
  }
}

enum LoopMode { off, one, all }

class _CachedStream {
  final Uri streamUrl;
  final DateTime cachedAt;
  final Duration duration;
  final String? thumbnailUrl;
  final String? audioCodec;
  final int? bitrate;

  _CachedStream({
    required this.streamUrl,
    required this.cachedAt,
    required this.duration,
    this.thumbnailUrl,
    this.audioCodec,
    this.bitrate,
  });

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > const Duration(hours: 4);
}

/// Centralized playback service powered by native media_kit (libmpv).
/// Runs independently of the UI to guarantee uninterrupted background audio
/// playback when switching apps or locking the screen.
class PlayerService {
  /// Standard browser headers required by YouTube's CDN to prevent 403 Forbidden.
  static const Map<String, String> _streamHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/125.0.0.0 Safari/537.36',
    'Referer': 'https://www.youtube.com/',
  };

  final YoutubeService _yt = YoutubeService();
  YoutubeService get youtubeService => _yt;
  late final Player _player;

  int _playSessionId = 0;
  final Map<String, _CachedStream> _streamCache = {};
  final Map<String, Future<ResolvedVideo>> _resolvingFutures = {};

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

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
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final StreamController<String> _audioCodecController =
      StreamController<String>.broadcast();
  final StreamController<int?> _bitrateController =
      StreamController<int?>.broadcast();

  final SettingsService? settingsService;
  String _currentAudioCodec = 'AAC';
  int? _currentBitrate;

  Track? _currentTrack;
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleEnabled = false;
  final List<Track> _queue = [];
  final List<Track> _originalQueue = [];
  int _currentIndex = -1;

  double _volume = 1.0;
  double _lastNonZeroVolume = 1.0;
  final void Function(double)? onVolumeChanged;

  bool _disposed = false;
  int _recoveryAttempts = 0;
  String? _recoveringTrackId;
  StreamSubscription? _playingSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _errorSub;

  /// Ensures native MediaKit dependencies are resolved before Player instantiation.
  static void ensureMediaKitInitialized() {
    try {
      String? mpvPath;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final candidates = [
          '$exeDir\\libmpv-2.dll',
          r'build\windows\x64\runner\Debug\libmpv-2.dll',
          r'build\windows\x64\runner\Release\libmpv-2.dll',
          r'build\windows\x64\libmpv\libmpv-2.dll',
          r'build\windows\runner\Debug\libmpv-2.dll',
          r'build\windows\runner\Release\libmpv-2.dll',
          r'build\windows\libmpv\libmpv-2.dll',
        ];
        for (final c in candidates) {
          if (File(c).existsSync()) {
            mpvPath = File(c).absolute.path;
            break;
          }
        }
      }
      MediaKit.ensureInitialized(libmpv: mpvPath);
    } catch (e) {
      debugPrint('MediaKit init safety note: $e');
    }
  }

  PlayerService({
    double initialVolume = 1.0,
    this.onVolumeChanged,
    this.settingsService,
  }) {
    ensureMediaKitInitialized();
    _volume = initialVolume.clamp(0.0, 1.0);
    _lastNonZeroVolume = _volume > 0.01 ? _volume : 1.0;

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 16 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    _player.setVolume((_volume * 100).toDouble());

    // Pre-warm the local HTTP streaming proxy and wire stream auto-refresh
    StreamProxyService.instance.ensureStarted().catchError((e) {
      debugPrint('PlayerService: proxy warm-up warning: $e');
    });
    StreamProxyService.instance.onStreamExpired = (trackId) async {
      debugPrint(
          'PlayerService: Re-resolving stream for $trackId due to 403/expired...');
      _streamCache.remove(trackId);
      try {
        final quality = await _getEffectiveQuality();
        final resolved = await _yt.resolveAudioStream(trackId, quality: quality);
        _currentAudioCodec = resolved.audioCodec;
        _currentBitrate = resolved.bitrate;
        if (!_disposed) {
          _audioCodecController.add(_currentAudioCodec);
          _bitrateController.add(_currentBitrate);
        }
        _streamCache[trackId] = _CachedStream(
          streamUrl: resolved.audioStreamUrl,
          cachedAt: DateTime.now(),
          duration: resolved.duration,
          thumbnailUrl: _currentTrack?.thumbnailUrl,
          audioCodec: resolved.audioCodec,
          bitrate: resolved.bitrate,
        );
        return resolved.audioStreamUrl;
      } catch (e) {
        debugPrint('PlayerService: Auto-refresh failed for $trackId: $e');
        return null;
      }
    };

    _playingSub = _player.stream.playing.listen((playing) {
      if (_disposed) return;
      _isPlaying = playing;
      if (playing) {
        _recoveryAttempts = 0;
        _recoveringTrackId = null;
      }
      _playingController.add(playing);
    });

    _posSub = _player.stream.position.listen((pos) {
      if (_disposed) return;
      _position = pos;
      if (pos > Duration.zero) {
        _recoveryAttempts = 0;
        _recoveringTrackId = null;
      }
      _positionController.add(pos);
    });

    _durSub = _player.stream.duration.listen((dur) {
      if (_disposed) return;
      if (dur != Duration.zero) {
        _duration = dur;
        _durationController.add(dur);
      }
    });

    _completedSub = _player.stream.completed.listen((completed) {
      if (_disposed) return;
      if (completed) {
        onTrackEnd();
      }
    });

    _errorSub = _player.stream.error.listen((error) {
      if (_disposed) return;
      debugPrint('MediaKit Player error: $error');

      // Auto-recover from "Failed to open" stream errors by evicting stale cache & refreshing
      final cur = _currentTrack;
      if (cur != null && error.toString().contains('Failed to open')) {
        if (_recoveringTrackId != cur.id) {
          _recoveringTrackId = cur.id;
          _recoveryAttempts = 0;
        }
        _recoveryAttempts++;
        if (_recoveryAttempts > 2) {
          debugPrint(
              'PlayerService: Max recovery attempts reached for [${cur.title}] (${cur.id}), stopping recovery to avoid loop.');
          _emitError('Playback error: Unable to open audio stream ($error)');
          return;
        }
        debugPrint(
            'PlayerService: Attempting stream recovery for [${cur.title}] (${cur.id}) (attempt $_recoveryAttempts)...');
        _streamCache.remove(cur.id);
        _resolveOrFetch(cur.id).then((fresh) {
          if (_disposed || _currentTrack?.id != cur.id) return;
          final refreshed = cur.copyWith(streamUrl: fresh.audioStreamUrl);
          _playTrack(refreshed).catchError((e) {
            debugPrint('PlayerService: Recovery attempt failed: $e');
            _emitError('Playback error: $error');
          });
        }).catchError((e) {
          _emitError('Playback error: $error');
        });
        return;
      }

      _emitError('Playback error: $error');
    });
  }

  Stream<Track?> get nowPlayingStream => _nowPlayingController.stream;
  Stream<LoopMode> get loopModeStream => _loopModeController.stream;
  Stream<bool> get shuffleStream => _shuffleController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<double> get volumeStream => _volumeController.stream;
  Stream<String> get audioCodecStream => _audioCodecController.stream;
  Stream<int?> get bitrateStream => _bitrateController.stream;

  String get currentAudioCodec => _currentAudioCodec;
  int? get currentBitrate => _currentBitrate;
  Track? get currentTrack => _currentTrack;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  LoopMode get loopMode => _loopMode;
  bool get shuffleEnabled => _shuffleEnabled;
  List<Track> get queue => List.unmodifiable(_queue);
  double get volume => _volume;
  double get appVolume => _volume;

  /// Sets independent in-app playback volume (0.0 to 1.0) without changing device system volume.
  Future<void> setVolume(double value, {bool persist = true}) async {
    final clamped = value.clamp(0.0, 1.0);
    _volume = clamped;
    if (_volume > 0.01) {
      _lastNonZeroVolume = _volume;
    }
    _volumeController.add(_volume);
    try {
      _player.setVolume((_volume * 100).toDouble()).catchError((_) {});
    } catch (_) {}
    if (persist) {
      onVolumeChanged?.call(_volume);
    }
  }

  /// Alias for setVolume
  Future<void> setAppVolume(double value, {bool persist = true}) =>
      setVolume(value, persist: persist);

  /// Toggles mute state (returns to previous volume or 0).
  Future<void> toggleMute() async {
    if (_volume <= 0.01) {
      await setVolume(_lastNonZeroVolume > 0.01 ? _lastNonZeroVolume : 1.0);
    } else {
      _lastNonZeroVolume = _volume;
      await setVolume(0.0);
    }
  }

  /// Resolves input (URL, Spotify link, video ID, or search query) and begins playback.
  Future<Track> play(String input, {bool replaceQueue = true}) async {
    final trimmed = input.trim();

    // Check for Spotify links / URIs
    if (SpotifyService.isSpotifyUrl(trimmed)) {
      final spotify = SpotifyService();
      final result = await spotify.fetch(trimmed);
      if (result.tracks.isEmpty) {
        throw Exception('No tracks found in Spotify link');
      }
      final tracks = result.tracks.map(Track.fromLocalPlaylistTrack).toList();
      await _enqueueAndPlay(tracks, startIndex: 0, replaceQueue: replaceQueue);
      return tracks.first;
    }

    final idRegex = RegExp(r'(?:v=|\/|youtu\.be\/)([0-9A-Za-z_-]{11})');
    final match = idRegex.firstMatch(trimmed);
    final videoId = match != null
        ? match.group(1)!
        : (trimmed.length == 11 && !trimmed.contains(' ') ? trimmed : null);

    Track track;
    if (videoId != null) {
      String title = 'YouTube Track';
      String author = 'YouTube';
      Duration dur = Duration.zero;
      try {
        final video = await _yt.getVideoMetadata(videoId);
        title = video.title;
        author = video.author;
        dur = video.duration ?? Duration.zero;
      } catch (_) {}

      track = Track(
        id: videoId,
        title: title,
        author: author,
        youtubeUrl: 'https://www.youtube.com/watch?v=$videoId',
        duration: dur,
      );
    } else {
      final searchResults = await _yt.search(trimmed);
      if (searchResults.isEmpty) {
        throw Exception('No videos found for "$trimmed"');
      }
      final first = searchResults.first;
      track = Track(
        id: first.id.value,
        title: first.title,
        author: first.author,
        youtubeUrl: first.url,
        duration: first.duration ?? Duration.zero,
      );
    }

    await _enqueueAndPlay([track], startIndex: 0, replaceQueue: replaceQueue);
    return track;
  }

  Future<void> playList(List<Track> tracks,
      {int startIndex = 0, bool replaceQueue = true}) async {
    await _enqueueAndPlay(tracks,
        startIndex: startIndex, replaceQueue: replaceQueue);
  }

  /// Plays a single Track instance immediately.
  Future<void> playTrack(Track track, {bool replaceQueue = true}) async {
    await _enqueueAndPlay([track], startIndex: 0, replaceQueue: replaceQueue);
  }

  /// Appends a Track to the end of the current queue.
  void addToQueue(Track track) {
    _queue.add(track);
    _originalQueue.add(track);
    if (_currentIndex == -1) {
      _currentIndex = 0;
      _playTrack(track);
    } else {
      _preloadQueue(_currentIndex);
    }
  }

  /// Inserts a Track immediately after the current playing track.
  void playNext(Track track) {
    if (_queue.isEmpty || _currentIndex == -1) {
      playTrack(track);
      return;
    }
    final nextIdx = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(nextIdx, track);
    _originalQueue.insert(nextIdx, track);
    _preloadQueue(_currentIndex);
  }

  /// Inserts a list of tracks immediately after the current playing track.
  void playNextTracks(List<Track> tracks) {
    if (tracks.isEmpty) return;
    if (_queue.isEmpty || _currentIndex == -1) {
      _enqueueAndPlay(tracks, startIndex: 0, replaceQueue: true);
      return;
    }
    final nextIdx = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insertAll(nextIdx, tracks);
    _originalQueue.insertAll(nextIdx, tracks);
    _preloadQueue(_currentIndex);
  }

  /// Appends multiple tracks to the end of the current queue.
  void addTracksToQueue(List<Track> tracks) {
    if (tracks.isEmpty) return;
    if (_queue.isEmpty || _currentIndex == -1) {
      _enqueueAndPlay(tracks, startIndex: 0, replaceQueue: true);
      return;
    }
    _queue.addAll(tracks);
    _originalQueue.addAll(tracks);
    _preloadQueue(_currentIndex);
  }

  /// Queues tracks from a local or imported Spotify playlist and starts playback.
  Future<void> playLocalTracks(
    List<LocalPlaylistTrack> playlistTracks, {
    int startIndex = 0,
  }) async {
    if (playlistTracks.isEmpty) return;
    final tracks = playlistTracks.map(Track.fromLocalPlaylistTrack).toList();
    await _enqueueAndPlay(tracks, startIndex: startIndex, replaceQueue: true);
  }

  /// Alias for playLocalTracks
  Future<void> playLocalPlaylistTracks(
    List<LocalPlaylistTrack> playlistTracks, {
    int startIndex = 0,
  }) =>
      playLocalTracks(playlistTracks, startIndex: startIndex);

  /// Queues videos from playlist metadata and starts playback.
  Future<void> playVideos(
    List<({String videoId, String title, String author, Duration duration})>
        videos, {
    int startIndex = 0,
  }) async {
    if (videos.isEmpty) return;
    final tracks = videos
        .map((v) => Track.fromPlaylistVideo(
              videoId: v.videoId,
              title: v.title,
              author: v.author,
              duration: v.duration,
            ))
        .toList();
    await _enqueueAndPlay(tracks, startIndex: startIndex, replaceQueue: true);
  }

  /// Fetches recommended next tracks based on the currently playing track or provided videoId.
  Future<List<Track>> getRecommendations({String? videoId, int limit = 10}) async {
    final id = videoId ?? _currentTrack?.id;
    if (id == null || id.isEmpty) return [];
    final rawList = await _yt.getRecommendations(id, limit: limit);
    return rawList.map((item) {
      final vId = item['videoId'] as String;
      return Track(
        id: vId,
        title: item['title'] as String,
        author: item['author'] as String,
        youtubeUrl: 'https://www.youtube.com/watch?v=$vId',
        duration: item['duration'] as Duration,
        thumbnailUrl: item['thumbnailUrl'] as String?,
      );
    }).toList();
  }

  void togglePlayPause() {
    _player.playOrPause();
  }

  void pause() {
    _player.pause();
  }

  void resume() {
    _player.play();
  }

  void stop() {
    _playSessionId++;
    try {
      _player.stop();
    } catch (_) {}
    _currentTrack = null;
    _currentIndex = -1;
    _queue.clear();
    _originalQueue.clear();
    _emitNowPlaying(null);
  }

  void replay() {
    if (_currentTrack != null) {
      _player.seek(Duration.zero);
      _player.play();
    }
  }

  Future<void> nextTrack() async {
    if (_queue.isEmpty) return;

    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      await _playTrack(_queue[_currentIndex]);
    } else if (_loopMode == LoopMode.all) {
      _currentIndex = 0;
      await _playTrack(_queue[0]);
    }
  }

  Future<void> previousTrack() async {
    if (_queue.isEmpty) return;

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

    await _playTrack(_queue[_currentIndex]);
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;

    if (_queue.isNotEmpty) {
      final current = _currentTrack;
      if (_shuffleEnabled) {
        if (_originalQueue.isEmpty) {
          _originalQueue.addAll(_queue);
        }
        final others =
            _originalQueue.where((t) => t.id != current?.id).toList();
        others.shuffle(Random());
        _queue.clear();
        if (current != null) _queue.add(current);
        _queue.addAll(others);
        _currentIndex = 0;
      } else {
        if (_originalQueue.isNotEmpty) {
          _queue.clear();
          _queue.addAll(_originalQueue);
          if (current != null) {
            _currentIndex = _queue.indexWhere((t) => t.id == current.id);
            if (_currentIndex == -1) _currentIndex = 0;
          }
        }
      }
      _emitNowPlaying(_currentTrack);
      _preloadQueue(_currentIndex);
    }

    if (!_disposed) _shuffleController.add(_shuffleEnabled);
  }

  void setShuffle(bool enable) {
    if (_shuffleEnabled == enable) return;
    toggleShuffle();
  }

  Future<void> playTrackAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await _playTrack(_queue[_currentIndex]);
  }

  void cycleLoopMode() {
    _loopMode = switch (_loopMode) {
      LoopMode.off => LoopMode.one,
      LoopMode.one => LoopMode.all,
      LoopMode.all => LoopMode.off,
    };
    _emitLoopMode();
  }

  void setLoopMode(LoopMode mode) {
    if (_loopMode == mode) return;
    _loopMode = mode;
    _emitLoopMode();
  }

  void seek(Duration position) {
    _position = position;
    _positionController.add(position);
    _player.seek(position);
  }

  /// Returns the effective streaming audio quality level from SettingsService.
  Future<String> _getEffectiveQuality() async {
    try {
      if (settingsService != null) {
        return await settingsService!.getEffectiveAudioQuality();
      }
      if (SettingsService.instance != null) {
        return await SettingsService.instance!.getEffectiveAudioQuality();
      }
    } catch (e) {
      debugPrint('PlayerService: Error getting effective audio quality ($e)');
    }
    return 'high';
  }

  /// Deduplicated stream resolution future pool so concurrent requests join in-flight work.
  Future<ResolvedVideo> _resolveOrFetch(String videoId) async {
    if (_resolvingFutures.containsKey(videoId)) {
      return await _resolvingFutures[videoId]!;
    }
    final quality = await _getEffectiveQuality();
    final future = _yt.resolveAudioStream(videoId, quality: quality).whenComplete(() {
      _resolvingFutures.remove(videoId);
    });
    _resolvingFutures[videoId] = future;
    return await future;
  }

  /// Background lookahead: pre-resolves upcoming tracks in the queue so skipping is instantaneous.
  void _preloadQueue(int fromIndex) {
    if (_queue.isEmpty || _disposed) return;

    final indices = <int>[];
    if (fromIndex + 1 < _queue.length) {
      indices.add(fromIndex + 1);
    } else if (_loopMode == LoopMode.all && _queue.isNotEmpty) {
      indices.add(0);
    }
    if (fromIndex + 2 < _queue.length) {
      indices.add(fromIndex + 2);
    }

    for (final idx in indices) {
      final nextTrack = _queue[idx];
      if (nextTrack.streamUrl != null) continue;
      final cached = _streamCache[nextTrack.id];
      if (cached != null && !cached.isExpired) {
        _queue[idx] = nextTrack.copyWith(
          streamUrl: cached.streamUrl,
          duration: cached.duration != Duration.zero
              ? cached.duration
              : nextTrack.duration,
          thumbnailUrl: nextTrack.thumbnailUrl ?? cached.thumbnailUrl,
        );
        continue;
      }
      _preloadSingleTrack(idx, nextTrack);
    }
  }

  /// Resolves a verified YouTube video ID for a track if it doesn't already have one,
  /// using high-precision query variations with artist sanitation and persists the result.
  Future<String?> _resolveVideoIdForTrack(Track track) async {
    if (DownloadService.isValidYouTubeVideoId(track.id, title: track.title)) {
      return track.id;
    }

    final queries = DownloadService.buildSearchQueries(track);

    for (final q in queries) {
      try {
        final results = await _yt.search(q);
        if (results.isNotEmpty) {
          final foundId = results.first.id.value;
          if (DownloadService.isValidYouTubeVideoId(foundId, title: track.title)) {
            unawaited(PlaylistService.instance.updateTrackResolvedVideoId(
              title: track.title,
              artist: track.author,
              youtubeVideoId: foundId,
            ));
            return foundId;
          }
        }
      } catch (e) {
        debugPrint('PlayerService: Query "$q" failed during resolution: $e');
      }
    }

    return null;
  }

  Future<void> _preloadSingleTrack(int index, Track track) async {
    try {
      // 1. Check if track is already downloaded locally
      final downloaded = DownloadService.instance.findDownloadedTrack(
        id: track.id,
        title: track.title,
        artist: track.author,
      );
      if (downloaded != null && File(downloaded.audioFilePath).existsSync()) {
        final streamUri = Uri.file(downloaded.audioFilePath);
        final localThumb = downloaded.thumbnailFilePath != null &&
                File(downloaded.thumbnailFilePath!).existsSync()
            ? Uri.file(downloaded.thumbnailFilePath!).toString()
            : (track.thumbnailUrl ?? downloaded.thumbnailUrl);
        if (index < _queue.length && _queue[index].id == track.id) {
          _queue[index] = _queue[index].copyWith(
            id: (downloaded.youtubeVideoId != null && downloaded.youtubeVideoId!.isNotEmpty)
                ? downloaded.youtubeVideoId!
                : track.id,
            streamUrl: streamUri,
            thumbnailUrl: localThumb,
            duration: downloaded.duration != Duration.zero
                ? downloaded.duration
                : track.duration,
            audioCodec: downloaded.audioCodec,
            bitrate: downloaded.bitrate,
          );
        }
        return;
      }

      String? effectiveVideoId = track.id;
      final isYtId =
          DownloadService.isValidYouTubeVideoId(effectiveVideoId, title: track.title);
      if (!isYtId) {
        effectiveVideoId = await _resolveVideoIdForTrack(track);
        if (effectiveVideoId == null) return;
      }

      final cached = _streamCache[effectiveVideoId];
      if (cached != null && !cached.isExpired) {
        if (index < _queue.length && _queue[index].id == track.id) {
          _queue[index] = _queue[index].copyWith(
            id: effectiveVideoId,
            streamUrl: cached.streamUrl,
            duration: cached.duration != Duration.zero
                ? cached.duration
                : track.duration,
            thumbnailUrl: track.thumbnailUrl ?? cached.thumbnailUrl,
          );
        }
        return;
      }

      final resolved = await _resolveOrFetch(effectiveVideoId);
      final ytThumb =
          'https://img.youtube.com/vi/$effectiveVideoId/hqdefault.jpg';
      final thumb =
          (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
              ? track.thumbnailUrl
              : ytThumb;

      _streamCache[effectiveVideoId] = _CachedStream(
        streamUrl: resolved.audioStreamUrl,
        cachedAt: DateTime.now(),
        duration: resolved.duration,
        thumbnailUrl: thumb,
        audioCodec: resolved.audioCodec,
        bitrate: resolved.bitrate,
      );

      if (index < _queue.length && _queue[index].id == track.id) {
        _queue[index] = _queue[index].copyWith(
          id: effectiveVideoId,
          streamUrl: resolved.audioStreamUrl,
          youtubeUrl: 'https://www.youtube.com/watch?v=$effectiveVideoId',
          duration: resolved.duration != Duration.zero
              ? resolved.duration
              : track.duration,
          thumbnailUrl: thumb,
          audioCodec: resolved.audioCodec,
          bitrate: resolved.bitrate,
        );
      }
      debugPrint(
          'PlayerService: Preloaded stream for [${track.title}] ($effectiveVideoId)');
    } catch (e) {
      debugPrint(
          'PlayerService: Background preloading failed for ${track.title}: $e');
    }
  }

  Future<void> _playTrack(Track track) async {
    final session = ++_playSessionId;
    debugPrint(
        'PlayerService: Switching to [${track.title}] (${track.id}) [session #$session]');

    // 1. Instantly stop previous playback & reset position to feel immediate like Media3 / ExoPlayer
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
    if (!_disposed) _playingController.add(false);

    _position = Duration.zero;
    if (!_disposed) _positionController.add(Duration.zero);
    if (track.duration != Duration.zero) {
      _duration = track.duration;
      if (!_disposed) _durationController.add(_duration);
    }

    // 2. Immediately update now-playing info for instantaneous UI reaction
    _currentTrack = track;
    if (_recoveringTrackId != track.id) {
      _recoveringTrackId = null;
      _recoveryAttempts = 0;
    }
    _emitNowPlaying(track);

    try {
      // ---------------------------------------------------------------
      // STEP 1: INSTANT OFFLINE CHECK
      // If the track is already a local file or downloaded in DownloadService,
      // play it directly from disk immediately. NEVER touch the network!
      // ---------------------------------------------------------------
      bool isLocalFile = false;
      String? localFilePath;
      Uri? streamUri;

      if (track.streamUrl != null && track.streamUrl!.isScheme('file')) {
        final filePath = track.streamUrl!.toFilePath();
        if (File(filePath).existsSync()) {
          streamUri = track.streamUrl!;
          localFilePath = filePath;
          isLocalFile = true;
        }
      }

      if (!isLocalFile) {
        final downloaded = DownloadService.instance.findDownloadedTrack(
          id: track.id,
          title: track.title,
          artist: track.author,
        );
        if (downloaded != null && File(downloaded.audioFilePath).existsSync()) {
          streamUri = Uri.file(downloaded.audioFilePath);
          localFilePath = downloaded.audioFilePath;
          isLocalFile = true;

          _currentAudioCodec = downloaded.audioCodec;
          _currentBitrate = downloaded.bitrate;
          if (!_disposed) {
            _audioCodecController.add(_currentAudioCodec);
            _bitrateController.add(_currentBitrate);
          }

          // Preserve public remote thumbnail URL for external services (Discord RPC)
          // while keeping downloaded.thumbnailFilePath for local offline UI rendering
          final remoteThumb = (track.thumbnailUrl != null &&
                  (track.thumbnailUrl!.startsWith('http://') || track.thumbnailUrl!.startsWith('https://')))
              ? track.thumbnailUrl!
              : (downloaded.thumbnailUrl != null &&
                      (downloaded.thumbnailUrl!.startsWith('http://') || downloaded.thumbnailUrl!.startsWith('https://'))
                  ? downloaded.thumbnailUrl!
                  : (downloaded.youtubeVideoId != null && downloaded.youtubeVideoId!.isNotEmpty
                      ? 'https://img.youtube.com/vi/${downloaded.youtubeVideoId}/hqdefault.jpg'
                      : track.thumbnailUrl));

          track = track.copyWith(
            id: (downloaded.youtubeVideoId != null && downloaded.youtubeVideoId!.isNotEmpty)
                ? downloaded.youtubeVideoId!
                : track.id,
            streamUrl: streamUri,
            thumbnailUrl: remoteThumb,
            localThumbnailPath: downloaded.thumbnailFilePath,
            duration: downloaded.duration != Duration.zero
                ? downloaded.duration
                : track.duration,
            audioCodec: downloaded.audioCodec,
            bitrate: downloaded.bitrate,
          );
          _currentTrack = track;
          if (_currentIndex >= 0 && _currentIndex < _queue.length) {
            _queue[_currentIndex] = track;
          }
          _emitNowPlaying(_currentTrack);
        }
      }

      if (isLocalFile && localFilePath != null) {
        debugPrint('PlayerService: Playing local offline file: $localFilePath');
        try {
          await _player.open(
            Media(localFilePath),
            play: true,
          );
        } catch (openErr) {
          debugPrint('PlayerService: Media(localFilePath) fallback to URI ($openErr)');
          await _player.open(
            Media(streamUri!.toString()),
            play: true,
          );
        }
        await _player.setVolume((_volume * 100).toDouble());
        if (_currentTrack != null) {
          HistoryService.instance.recordTrack(_currentTrack!);
        }
        _preloadQueue(_currentIndex);
        return; // Complete offline playback - no network used
      }

      // ---------------------------------------------------------------
      // STEP 2: ONLINE STREAM RESOLUTION (Only when track not downloaded)
      // ---------------------------------------------------------------
      String effectiveVideoId = track.id;
      final isYtId =
          DownloadService.isValidYouTubeVideoId(effectiveVideoId, title: track.title);

      if (!isYtId) {
        // Resolve Spotify / text track to verified YouTube ID
        debugPrint('PlayerService: Resolving YouTube ID for "${track.title}" by "${track.author}"...');
        final resolvedId = await _resolveVideoIdForTrack(track);
        if (resolvedId == null) {
          throw Exception(
              'No YouTube match found for "${track.title}" by ${track.author}');
        }
        effectiveVideoId = resolvedId;
      }

      // Check if this playback request was superseded while resolving ID
      if (_disposed || _playSessionId != session) {
        debugPrint(
            'PlayerService: Session #$session superseded by #$_playSessionId');
        return;
      }

      final ytThumb =
          'https://img.youtube.com/vi/$effectiveVideoId/hqdefault.jpg';
      final thumbToUse =
          (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
              ? track.thumbnailUrl!
              : ytThumb;

      // Check preloaded/cached stream
      final cached = _streamCache[effectiveVideoId];
      if (track.streamUrl != null && isYtId) {
        streamUri = track.streamUrl!;
        if (track.audioCodec != null) {
          _currentAudioCodec = track.audioCodec!;
          _currentBitrate = track.bitrate;
          if (!_disposed) {
            _audioCodecController.add(_currentAudioCodec);
            _bitrateController.add(_currentBitrate);
          }
        }
      } else if (cached != null && !cached.isExpired) {
        streamUri = cached.streamUrl;
        if (cached.audioCodec != null) {
          _currentAudioCodec = cached.audioCodec!;
          _currentBitrate = cached.bitrate;
          if (!_disposed) {
            _audioCodecController.add(_currentAudioCodec);
            _bitrateController.add(_currentBitrate);
          }
        }
        final updated = track.copyWith(
          id: effectiveVideoId,
          youtubeUrl: 'https://www.youtube.com/watch?v=$effectiveVideoId',
          streamUrl: streamUri,
          thumbnailUrl: thumbToUse,
          duration: cached.duration != Duration.zero
              ? cached.duration
              : track.duration,
          audioCodec: cached.audioCodec,
          bitrate: cached.bitrate,
        );
        _currentTrack = updated;
        if (_currentIndex >= 0 && _currentIndex < _queue.length) {
          _queue[_currentIndex] = updated;
        }
        _emitNowPlaying(_currentTrack);
      } else {
        // Resolve stream (or join existing in-flight resolution future)
        ResolvedVideo resolved;
        try {
          resolved = await _resolveOrFetch(effectiveVideoId);
        } catch (e) {
          debugPrint(
              'PlayerService: Stream resolution error for $effectiveVideoId ($e), attempting fallback search...');
          final fallbackQueries = DownloadService.buildSearchQueries(track);
          String? fallbackId;
          for (final q in fallbackQueries) {
            try {
              final searchRes = await _yt.search(q);
              if (searchRes.isNotEmpty && searchRes.first.id.value != effectiveVideoId) {
                fallbackId = searchRes.first.id.value;
                break;
              }
            } catch (_) {}
          }
          if (fallbackId != null) {
            effectiveVideoId = fallbackId;
            unawaited(PlaylistService.instance.updateTrackResolvedVideoId(
              title: track.title,
              artist: track.author,
              youtubeVideoId: fallbackId,
            ));
            resolved = await _resolveOrFetch(effectiveVideoId);
          } else {
            rethrow;
          }
        }

        // Check again if superseded while resolving stream
        if (_disposed || _playSessionId != session) {
          debugPrint(
              'PlayerService: Session #$session superseded after resolving stream');
          return;
        }

        streamUri = resolved.audioStreamUrl;
        _currentAudioCodec = resolved.audioCodec;
        _currentBitrate = resolved.bitrate;
        if (!_disposed) {
          _audioCodecController.add(_currentAudioCodec);
          _bitrateController.add(_currentBitrate);
        }

        _streamCache[effectiveVideoId] = _CachedStream(
          streamUrl: streamUri,
          cachedAt: DateTime.now(),
          duration: resolved.duration,
          thumbnailUrl: thumbToUse,
          audioCodec: resolved.audioCodec,
          bitrate: resolved.bitrate,
        );

        final updated = track.copyWith(
          id: effectiveVideoId,
          youtubeUrl: 'https://www.youtube.com/watch?v=$effectiveVideoId',
          streamUrl: streamUri,
          thumbnailUrl: thumbToUse,
          duration: resolved.duration != Duration.zero
              ? resolved.duration
              : track.duration,
          audioCodec: resolved.audioCodec,
          bitrate: resolved.bitrate,
        );
        _currentTrack = updated;
        if (_currentIndex >= 0 && _currentIndex < _queue.length) {
          _queue[_currentIndex] = updated;
        }
        _emitNowPlaying(_currentTrack);
      }

      final isDesktop = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.macOS);

      Uri primaryUri;
      Map<String, String>? primaryHeaders;

      if (streamUri.scheme == 'file') {
        // Offline downloaded track: play directly from local file
        primaryUri = streamUri;
        primaryHeaders = null;
      } else if (isDesktop) {
        // Desktop platforms have native TLS 1.3 in libmpv; direct HTTPS with headers is lowest latency
        primaryUri = streamUri;
        primaryHeaders = _streamHeaders;
      } else {
        // Mobile platforms (Android Mbed TLS) route through local proxy to bypass TLS 1.3 restrictions
        try {
          await StreamProxyService.instance.ensureStarted();
          primaryUri = StreamProxyService.instance.getProxyUri(
            effectiveVideoId,
            streamUri,
          );
          primaryHeaders = null;
        } catch (proxyErr) {
          debugPrint('PlayerService: Proxy resolution error ($proxyErr), using direct stream');
          primaryUri = streamUri;
          primaryHeaders = _streamHeaders;
        }
      }

      // Check again before opening player
      if (_disposed || _playSessionId != session) return;

      // Attempt playback with fallback between proxy and direct HTTPS
      bool opened = false;
      try {
        await _player.open(
          Media(
            primaryUri.toString(),
            httpHeaders: primaryHeaders,
          ),
          play: true,
        );
        opened = true;
      } catch (openErr) {
        debugPrint(
            'PlayerService: Primary open failed ($openErr), attempting alternative fallback...');
        if (_disposed || _playSessionId != session) return;

        try {
          if (primaryUri == streamUri) {
            await StreamProxyService.instance.ensureStarted();
            final fallbackProxyUri = StreamProxyService.instance.getProxyUri(
              effectiveVideoId,
              streamUri,
            );
            await _player.open(
              Media(fallbackProxyUri.toString()),
              play: true,
            );
            opened = true;
          } else {
            await _player.open(
              Media(
                streamUri.toString(),
                httpHeaders: _streamHeaders,
              ),
              play: true,
            );
            opened = true;
          }
        } catch (fallbackErr) {
          debugPrint(
              'PlayerService: Alternative playback fallback also failed: $fallbackErr');
        }
        if (!opened) rethrow;
      }
      await _player.setVolume((_volume * 100).toDouble());

      if (_currentTrack != null) {
        HistoryService.instance.recordTrack(_currentTrack!);
      }

      // 4. Preload next tracks in queue in background for instant upcoming transitions
      _preloadQueue(_currentIndex);
    } catch (e) {
      if (_playSessionId == session) {
        debugPrint(
            'PlayerService: failed to play audio stream for ${track.id}: $e');
        _emitError('Playback failed: $e');
      }
    }
  }

  Future<void> _enqueueAndPlay(
    List<Track> tracks, {
    required int startIndex,
    required bool replaceQueue,
  }) async {
    if (tracks.isEmpty) return;

    final validIndex =
        (startIndex >= 0 && startIndex < tracks.length) ? startIndex : 0;
    final selectedTrack = tracks[validIndex];

    if (replaceQueue) {
      _originalQueue.clear();
      _originalQueue.addAll(tracks);
      _queue.clear();

      if (_shuffleEnabled) {
        final others = tracks.where((t) => t.id != selectedTrack.id).toList();
        others.shuffle(Random());
        _queue.add(selectedTrack);
        _queue.addAll(others);
        _currentIndex = 0;
      } else {
        _queue.addAll(tracks);
        _currentIndex = validIndex;
      }
    } else {
      _originalQueue.addAll(tracks);
      if (_shuffleEnabled) {
        final newTracks = List<Track>.from(tracks)..shuffle(Random());
        _queue.addAll(newTracks);
      } else {
        _queue.addAll(tracks);
      }
    }

    _currentTrack = _queue[_currentIndex];
    _emitNowPlaying(_currentTrack);

    try {
      await _playTrack(_currentTrack!);
    } catch (e) {
      debugPrint('PlayerService: failed to play track: $e');
      _emitError('Playback failed: $e');
    }
  }

  /// Sets current track for testing purposes.
  void setCurrentTrackForTesting(Track? track) {
    _currentTrack = track;
    _emitNowPlaying(track);
  }

  /// Sets current audio codec for testing purposes.
  void setAudioCodecForTesting(String codec, [int? bitrate]) {
    _currentAudioCodec = codec;
    _currentBitrate = bitrate;
    if (!_disposed) {
      _audioCodecController.add(codec);
      _bitrateController.add(bitrate);
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

  Future<void> onTrackEnd() async {
    if (_disposed || _currentTrack == null) return;

    if (_loopMode == LoopMode.one) {
      replay();
      return;
    }

    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      await _playTrack(_queue[_currentIndex]);
      return;
    }

    if (_loopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      await _playTrack(_queue[0]);
      return;
    }

    stop();
  }

  /// Appends a track to the end of the current playback queue.
  void addTrackToQueue(Track track) {
    _queue.add(track);
    _originalQueue.add(track);
    _preloadQueue(_currentIndex);
  }

  void removeFromQueue(String trackId) {
    final index = _queue.indexWhere((t) => t.id == trackId);
    if (index == -1) return;
    _queue.removeAt(index);

    if (_queue.isEmpty) {
      stop();
      return;
    }

    if (_currentTrack != null && _currentTrack!.id == trackId) {
      final nextIndex = index < _queue.length ? index : _queue.length - 1;
      _currentIndex = nextIndex;
      _playTrack(_queue[nextIndex]).catchError((e) {
        debugPrint(
            'PlayerService: failed to play removed-track replacement: $e');
      });
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _playSessionId++;
    _streamCache.clear();
    _resolvingFutures.clear();
    _playingSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    _player.dispose();
    _yt.dispose();
    _nowPlayingController.close();
    _loopModeController.close();
    _shuffleController.close();
    _playingController.close();
    _errorController.close();
    _positionController.close();
    _durationController.close();
    _volumeController.close();
    _audioCodecController.close();
    _bitrateController.close();
  }
}
