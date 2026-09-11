import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Holds metadata and stream info for a resolved YouTube video.
class ResolvedVideo {
  final String title;
  final String author;
  final Duration duration;
  final String videoUrl;
  final Uri audioStreamUrl;

  const ResolvedVideo({
    required this.title,
    required this.author,
    required this.duration,
    required this.videoUrl,
    required this.audioStreamUrl,
  });

  @override
  String toString() => 'ResolvedVideo(title: $title, author: $author)';
}

/// Thin wrapper around [YoutubeExplode] that resolves a YouTube URL to an
/// audio-only stream URL suitable for playback with `audioplayers`.
class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Maximum number of retry attempts for transient failures.
  static const int _maxRetries = 2;

  /// Given a YouTube URL or video ID, returns metadata + the best audio stream
  /// URL. No file is downloaded — the URL is a direct HTTP stream.
  ///
  /// Retries up to [_maxRetries] times on transient errors (timeouts,
  /// network issues).
  Future<ResolvedVideo> resolveAudioStream(String input) async {
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        // Resolve video metadata.
        final Video video = await _yt.videos.get(input);

        // Fetch stream manifest and pick the highest-bitrate audio-only stream.
        final StreamManifest manifest =
            await _yt.videos.streams.getManifest(video.id);

        // Pick the best audio stream: prefer AAC (mp4a) for maximum
        // compatibility with audioplayers, then fall back to the highest
        // bitrate stream.
        final audioOnly = manifest.audioOnly;
        AudioOnlyStreamInfo audioStream;

        if (audioOnly.isEmpty) {
          throw Exception('No audio streams available for this video.');
        }

        // Prefer AAC / M4A — universally supported by audioplayers.
        final aacStreams = audioOnly
            .where((s) => s.audioCodec.toLowerCase().contains('mp4a'))
            .toList();
        if (aacStreams.isNotEmpty) {
          aacStreams.sort((a, b) =>
              b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
          audioStream = aacStreams.first;
        } else {
          // Fall back: prefer container mp4/m4a, then highest bitrate.
          final mp4Streams = audioOnly
              .where((s) => s.container.name.toLowerCase().contains('mp4'))
              .toList();
          if (mp4Streams.isNotEmpty) {
            mp4Streams.sort((a, b) =>
                b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
            audioStream = mp4Streams.first;
          } else {
            audioStream = audioOnly.withHighestBitrate();
          }
        }

        // Force HTTPS to avoid Android cleartext HTTP restrictions.
        final safeUrl = audioStream.url.replace(scheme: 'https');

        return ResolvedVideo(
          title: video.title,
          author: video.author,
          duration: video.duration ?? Duration.zero,
          videoUrl: video.url,
          audioStreamUrl: safeUrl,
        );
      } on TimeoutException {
        if (attempts <= _maxRetries) {
          debugPrint('Resolve attempt $attempts timed out, retrying…');
          continue;
        }
        throw Exception(
          'Timed out while resolving audio stream. \n'
          'Check your internet connection and try again.',
        );
      } catch (e) {
        rethrow;
      }
    }
  }

  void dispose() {
    _yt.close();
  }
}
