import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'player_service.dart';

/// Bridges FinAudio playback state with Android's system MediaSession and
/// Foreground Service notification via audio_service.
class FinAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  PlayerService? _playerService;
  final List<StreamSubscription> _subscriptions = [];

  void attachPlayerService(PlayerService service) {
    _playerService = service;

    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    // Listen to current track changes
    _subscriptions.add(
      service.nowPlayingStream.listen((track) {
        if (track != null) {
          mediaItem.add(
            MediaItem(
              id: track.id,
              album: 'FinAudio',
              title: track.title,
              artist: track.author,
              duration: track.duration != Duration.zero ? track.duration : null,
              artUri: (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
                  ? Uri.tryParse(track.thumbnailUrl!)
                  : Uri.tryParse('https://img.youtube.com/vi/${track.id}/hqdefault.jpg'),
            ),
          );
        } else {
          mediaItem.add(null);
        }
        _broadcastState();
      }),
    );

    // Listen to play/pause state
    _subscriptions.add(
      service.playingStream.listen((_) => _broadcastState()),
    );

    // Listen to seek/position changes
    _subscriptions.add(
      service.positionStream.listen((_) => _broadcastState()),
    );

    // Listen to duration updates
    _subscriptions.add(
      service.durationStream.listen((dur) {
        final current = mediaItem.value;
        if (current != null && dur != Duration.zero && current.duration != dur) {
          mediaItem.add(current.copyWith(duration: dur));
        }
        _broadcastState();
      }),
    );

    // Listen to shuffle and loop mode
    _subscriptions.add(
      service.shuffleStream.listen((_) => _broadcastState()),
    );
    _subscriptions.add(
      service.loopModeStream.listen((_) => _broadcastState()),
    );

    _broadcastState();
  }

  void _broadcastState() {
    final ps = _playerService;
    final isPlaying = ps?.isPlaying ?? false;
    final hasTrack = ps?.currentTrack != null;
    final position = ps?.position ?? Duration.zero;
    final LoopMode loopMode = ps?.loopMode ?? LoopMode.off;
    final shuffle = ps?.shuffleEnabled ?? false;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: hasTrack
            ? AudioProcessingState.ready
            : AudioProcessingState.idle,
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: position,
        speed: 1.0,
        repeatMode: switch (loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
        shuffleMode: shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  @override
  Future<void> play() async {
    final ps = _playerService;
    if (ps != null && !ps.isPlaying) {
      ps.togglePlayPause();
    }
  }

  @override
  Future<void> pause() async {
    final ps = _playerService;
    if (ps != null && ps.isPlaying) {
      ps.togglePlayPause();
    }
  }

  @override
  Future<void> stop() async {
    _playerService?.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    _playerService?.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await _playerService?.nextTrack();
  }

  @override
  Future<void> skipToPrevious() async {
    await _playerService?.previousTrack();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode == AudioServiceShuffleMode.all ||
        shuffleMode == AudioServiceShuffleMode.group;
    _playerService?.setShuffle(enable);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final mode = switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => LoopMode.all,
      AudioServiceRepeatMode.none => LoopMode.off,
    };
    _playerService?.setLoopMode(mode);
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    await stop();
  }
}

