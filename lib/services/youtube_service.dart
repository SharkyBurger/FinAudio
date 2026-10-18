import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:ytmusicapi_dart/enums.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

/// Holds metadata and direct stream info for a resolved YouTube video.
class ResolvedVideo {
  final String id;
  final String title;
  final String author;
  final Duration duration;
  final String youtubeUrl;
  final Uri audioStreamUrl;
  final String container;
  final String audioCodec;
  final int? bitrate;

  const ResolvedVideo({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.youtubeUrl,
    required this.audioStreamUrl,
    this.container = 'webm',
    this.audioCodec = 'AAC',
    this.bitrate,
  });

  @override
  String toString() =>
      'ResolvedVideo(id: $id, title: $title, author: $author, codec: $audioCodec, bitrate: $bitrate)';
}

/// Service providing YouTube video metadata resolution, InnerTube music catalog,
/// search queries, recommendations, and direct audio-only stream extraction.
class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();
  YTMusic? _ytMusic;
  static const MethodChannel _newPipeChannel =
      MethodChannel('com.example.finaudio/newpipe');
  static const int _maxRetries = 2;

  /// Lazily initializes and returns the InnerTube YTMusic client.
  Future<YTMusic> get ytMusic async {
    return _ytMusic ??= await YTMusic.create();
  }

  /// Gets video metadata without stream manifest requests.
  Future<Video> getVideoMetadata(String input) async {
    return await _yt.videos.get(input);
  }

  /// Searches for music videos matching the query using youtube_explode_dart.
  Future<List<Video>> search(String query) async {
    final searchList = await _yt.search.search(query);
    return searchList.toList();
  }

  /// Retrieves search auto-complete query suggestions.
  Future<List<String>> getSearchSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      final suggestions = await _yt.search.getQuerySuggestions(trimmed);
      return suggestions.toList();
    } catch (_) {
      return [];
    }
  }

  /// Searches YouTube Music catalogue via InnerTube (dart_ytmusicapi).
  Future<List<dynamic>> searchYTMusic(
    String query, {
    SearchFilterType? filter = SearchFilterType.songs,
    int limit = 20,
  }) async {
    final client = await ytMusic;
    return await client.search(query, filter: filter, limit: limit);
  }

  /// Retrieves an artist's profile and discography catalog via InnerTube.
  Future<Map<String, dynamic>> getArtist(String channelId) async {
    final client = await ytMusic;
    final res = await client.getArtist(channelId);
    return Map<String, dynamic>.from(res);
  }

  /// Retrieves YouTube Music home feed shelves and curated categories via InnerTube.
  Future<List<dynamic>> getHome({int limit = 3}) async {
    final client = await ytMusic;
    return await client.getHome(limit: limit);
  }

  /// Retrieves queue/recommendations watch playlist for a given video/playlist via InnerTube.
  Future<Map<String, dynamic>> getWatchPlaylist({
    String? videoId,
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
  }) async {
    final client = await ytMusic;
    final res = await client.getWatchPlaylist(
      videoId: videoId,
      playlistId: playlistId,
      limit: limit,
      radio: radio,
      shuffle: shuffle,
    );
    return Map<String, dynamic>.from(res);
  }

  /// Retrieves YouTube Music playlist metadata and tracklist via InnerTube.
  Future<Map<String, dynamic>> getPlaylist(
    String playlistId, {
    int? limit = 100,
  }) async {
    final client = await ytMusic;
    final res = await client.getPlaylist(playlistId, limit: limit);
    return Map<String, dynamic>.from(res);
  }

  /// Retrieves recommended tracks for a given video ID using InnerTube getWatchPlaylist.
  Future<List<Map<String, dynamic>>> getRecommendations(
    String videoId, {
    int limit = 25,
  }) async {
    try {
      final res = await getWatchPlaylist(videoId: videoId, limit: limit);
      final rawTracks = res['tracks'] as List? ?? [];
      final results = <Map<String, dynamic>>[];

      for (final item in rawTracks) {
        if (item is! Map) continue;
        final vId = item['videoId'] as String?;
        if (vId == null || vId.isEmpty || vId == videoId) continue;

        final title = (item['title'] as String?)?.isNotEmpty == true
            ? item['title'] as String
            : 'Untitled';

        String artist = '';
        final artists = item['artists'];
        if (artists is List && artists.isNotEmpty) {
          artist = artists
              .map((a) =>
                  a is Map ? (a['name']?.toString() ?? '') : a.toString())
              .where((s) => s.isNotEmpty)
              .join(', ');
        }
        if (artist.isEmpty && item['author'] != null) {
          artist = item['author'].toString();
        }

        String thumbUrl = 'https://img.youtube.com/vi/$vId/hqdefault.jpg';
        final thumbs = item['thumbnail'] ?? item['thumbnails'];
        if (thumbs is List && thumbs.isNotEmpty) {
          final last = thumbs.last;
          if (last is Map && last['url'] != null) {
            thumbUrl = last['url'].toString();
          }
        }

        Duration dur = Duration.zero;
        if (item['length'] is String) {
          dur = _parseDuration(item['length'] as String);
        }

        results.add({
          'videoId': vId,
          'title': title,
          'author': artist,
          'thumbnailUrl': thumbUrl,
          'duration': dur,
        });
      }
      return results;
    } catch (e) {
      debugPrint('YoutubeService: getRecommendations failed ($e)');
      return [];
    }
  }

  /// Parses duration formatted as "mm:ss" or "hh:mm:ss".
  static Duration _parseDuration(String durationStr) {
    final parts = durationStr.trim().split(':');
    if (parts.length == 2) {
      final mins = int.tryParse(parts[0]) ?? 0;
      final secs = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: mins, seconds: secs);
    } else if (parts.length == 3) {
      final hrs = int.tryParse(parts[0]) ?? 0;
      final mins = int.tryParse(parts[1]) ?? 0;
      final secs = int.tryParse(parts[2]) ?? 0;
      return Duration(hours: hrs, minutes: mins, seconds: secs);
    }
    return Duration.zero;
  }

  /// Resolves a video ID or URL to metadata + a direct audio-only stream URL
  /// by selecting appropriate stream based on [quality] ('high', 'medium', 'low')
  /// via native NewPipeExtractor on Android or youtube_explode_dart fallback.
  Future<ResolvedVideo> resolveAudioStream(String input, {String quality = 'high'}) async {
    final trimmed = input.trim();
    final idRegex = RegExp(r'(?:v=|\/|youtu\.be\/)([0-9A-Za-z_-]{11})');
    final match = idRegex.firstMatch(trimmed);
    final videoId = match != null
        ? match.group(1)!
        : (trimmed.length == 11 && !trimmed.contains(' ') ? trimmed : null);

    // On Android, use native NewPipeExtractor first to bypass botguard/cipher restrictions
    if (defaultTargetPlatform == TargetPlatform.android && videoId != null) {
      try {
        debugPrint('YoutubeService: Resolving $videoId via native NewPipeExtractor (quality: $quality)…');
        final res = await _newPipeChannel.invokeMapMethod<String, dynamic>(
          'getAudioStream',
          {'videoId': videoId, 'quality': quality},
        );

        if (res != null &&
            res['url'] != null &&
            (res['url'] as String).isNotEmpty) {
          final streamUrl = Uri.parse(res['url'] as String);
          final title = (res['title'] as String?)?.isNotEmpty == true
              ? res['title'] as String
              : 'YouTube Track';
          final uploader = (res['uploader'] as String?)?.isNotEmpty == true
              ? res['uploader'] as String
              : 'YouTube';
          final durationSec = (res['duration'] as num?)?.toInt() ?? 0;
          final format = (res['format'] as String?) ?? 'm4a';
          final codec = (res['codec'] as String?) ??
              (format.toLowerCase().contains('webm') ? 'OPUS' : 'AAC');
          final bitrate = (res['bitrate'] as num?)?.toInt();

          debugPrint('YoutubeService: Native NewPipeExtractor succeeded for $videoId ($codec, ${bitrate ?? 0} bps)');
          return ResolvedVideo(
            id: videoId,
            title: title,
            author: uploader,
            duration: Duration(seconds: durationSec),
            youtubeUrl: 'https://www.youtube.com/watch?v=$videoId',
            audioStreamUrl: streamUrl,
            container: format,
            audioCodec: codec,
            bitrate: bitrate,
          );
        }
      } catch (e) {
        debugPrint(
            'YoutubeService: Native NewPipeExtractor failed ($e), falling back to YoutubeExplode');
      }
    }

    // Fallback: YoutubeExplode audio-only stream manifest with requireWatchPage: false to bypass botguard/rate limits
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        final effectiveId = videoId ?? (input.length == 11 ? input : null);
        Video? video;
        try {
          video = await _yt.videos.get(input);
        } catch (getErr) {
          debugPrint('YoutubeService: _yt.videos.get failed ($getErr), continuing with stream manifest');
        }

        final vId = video?.id.value ?? effectiveId ?? input;
        StreamManifest? manifest;
        try {
          manifest = await _yt.videos.streams.getManifest(
            vId,
            requireWatchPage: false,
            ytClients: [
              YoutubeApiClient.androidSdkless,
            ],
          );
        } catch (manifestErr) {
          debugPrint(
              'YoutubeService: androidSdkless getManifest failed ($manifestErr), attempting fallback clients');
          manifest = await _yt.videos.streams.getManifest(
            vId,
            requireWatchPage: false,
          );
        }

        StreamInfo? chosenStream;
        final rateBypassMuxed = manifest.muxed.where(
          (s) => s.tag == 18 || s.url.toString().contains('ratebypass=yes'),
        ).toList();

        if (quality == 'low') {
          // Low quality: lowest bitrate audioOnly stream (itag 249/139 ~48-70k)
          if (manifest.audioOnly.isNotEmpty) {
            final sorted = manifest.audioOnly.toList()
              ..sort((a, b) => a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
            chosenStream = sorted.first;
          }
        }

        // Prioritize ratebypass streams (e.g. itag 18 MP4) to guarantee playback without 403 on desktop
        if (chosenStream == null && rateBypassMuxed.isNotEmpty) {
          chosenStream = rateBypassMuxed.first;
        }

        if (chosenStream == null && manifest.audioOnly.isNotEmpty) {
          if (quality == 'medium') {
            final sorted = manifest.audioOnly.toList()
              ..sort((a, b) => (a.bitrate.bitsPerSecond - 128000)
                  .abs()
                  .compareTo((b.bitrate.bitsPerSecond - 128000).abs()));
            chosenStream = sorted.first;
          } else {
            chosenStream = manifest.audioOnly.sortByBitrate().first;
          }
        }

        if (chosenStream == null) {
          if (manifest.muxed.isNotEmpty) {
            chosenStream = manifest.muxed.first;
          } else if (manifest.audioOnly.isNotEmpty) {
            chosenStream = manifest.audioOnly.sortByBitrate().first;
          } else {
            throw Exception('No playable audio streams available for this video.');
          }
        }

        final safeUrl = chosenStream.url.replace(scheme: 'https');

        String detectedCodec = 'AAC';
        if (chosenStream is AudioOnlyStreamInfo) {
          final c = chosenStream.audioCodec.toLowerCase();
          final cont = chosenStream.container.name.toLowerCase();
          if (c.contains('opus') || cont.contains('webm')) {
            detectedCodec = 'OPUS';
          } else {
            detectedCodec = 'AAC';
          }
        } else {
          final cont = chosenStream.container.name.toLowerCase();
          if (cont.contains('webm')) {
            detectedCodec = 'OPUS';
          } else {
            detectedCodec = 'AAC';
          }
        }

        final bitrate = chosenStream.bitrate.bitsPerSecond;

        return ResolvedVideo(
          id: vId,
          title: video?.title ?? 'YouTube Track',
          author: video?.author ?? 'YouTube',
          duration: video?.duration ?? Duration.zero,
          youtubeUrl: video?.url ?? 'https://www.youtube.com/watch?v=$vId',
          audioStreamUrl: safeUrl,
          container: chosenStream.container.name,
          audioCodec: detectedCodec,
          bitrate: bitrate,
        );
      } on TimeoutException {
        if (attempts <= _maxRetries) {
          debugPrint('Resolve attempt $attempts timed out, retrying…');
          continue;
        }
        throw Exception(
            'Timed out while resolving audio stream. Check internet connection.');
      } catch (e) {
        if (attempts <= _maxRetries) {
          debugPrint('Resolve attempt $attempts failed ($e), retrying…');
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        rethrow;
      }
    }
  }

  void dispose() {
    _yt.close();
    _ytMusic?.close();
  }
}
