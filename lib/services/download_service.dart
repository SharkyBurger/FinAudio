import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_service.dart';
import 'youtube_service.dart';

/// Represents a track that has been downloaded and is available for offline playback.
class DownloadedTrack {
  final String id;
  final String? youtubeVideoId;
  final String title;
  final String artist;
  final Duration duration;
  final String audioFilePath;
  final String? thumbnailFilePath;
  final String? thumbnailUrl;
  final String audioCodec;
  final int? bitrate;
  final int fileSizeBytes;
  final DateTime downloadedAt;

  const DownloadedTrack({
    required this.id,
    this.youtubeVideoId,
    required this.title,
    required this.artist,
    required this.duration,
    required this.audioFilePath,
    this.thumbnailFilePath,
    this.thumbnailUrl,
    this.audioCodec = 'OPUS',
    this.bitrate,
    required this.fileSizeBytes,
    required this.downloadedAt,
  });

  /// Converts this downloaded track into a playable [Track] instance.
  Track toTrack() {
    final effectiveYtId = (youtubeVideoId != null && youtubeVideoId!.isNotEmpty)
        ? youtubeVideoId!
        : (id.length == 11 && !id.contains(' ') ? id : '');

    final publicThumb = (thumbnailUrl != null &&
            thumbnailUrl!.isNotEmpty &&
            (thumbnailUrl!.startsWith('http://') || thumbnailUrl!.startsWith('https://')))
        ? thumbnailUrl!
        : (effectiveYtId.isNotEmpty ? 'https://img.youtube.com/vi/$effectiveYtId/hqdefault.jpg' : '');

    return Track(
      id: effectiveYtId.isNotEmpty ? effectiveYtId : id,
      title: title,
      author: artist,
      youtubeUrl: effectiveYtId.isNotEmpty ? 'https://www.youtube.com/watch?v=$effectiveYtId' : '',
      duration: duration,
      streamUrl: Uri.file(audioFilePath),
      thumbnailUrl: publicThumb.isNotEmpty ? publicThumb : null,
      localThumbnailPath: thumbnailFilePath,
      audioCodec: audioCodec,
      bitrate: bitrate,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'youtubeVideoId': youtubeVideoId,
        'title': title,
        'artist': artist,
        'durationMs': duration.inMilliseconds,
        'audioFilePath': audioFilePath,
        'thumbnailFilePath': thumbnailFilePath,
        'thumbnailUrl': thumbnailUrl,
        'audioCodec': audioCodec,
        'bitrate': bitrate,
        'fileSizeBytes': fileSizeBytes,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  factory DownloadedTrack.fromJson(Map<String, dynamic> json) {
    final rawThumbUrl = json['thumbnailUrl'] as String?;
    final rawThumbFile = json['thumbnailFilePath'] as String?;
    final rawYtId = json['youtubeVideoId'] as String?;
    final id = json['id'] as String? ?? '';
    final ytId = (rawYtId != null && rawYtId.isNotEmpty)
        ? rawYtId
        : (id.length == 11 && !id.contains(' ') ? id : null);

    // If legacy json stored a file URI or local path as thumbnailUrl, restore public YouTube thumbnail
    String? cleanThumb = rawThumbUrl;
    if (cleanThumb == null ||
        cleanThumb.isEmpty ||
        cleanThumb.startsWith('file://') ||
        (!cleanThumb.startsWith('http://') && !cleanThumb.startsWith('https://'))) {
      if (ytId != null && ytId.isNotEmpty) {
        cleanThumb = 'https://img.youtube.com/vi/$ytId/hqdefault.jpg';
      } else {
        cleanThumb = null;
      }
    }

    return DownloadedTrack(
      id: id,
      youtubeVideoId: ytId,
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      audioFilePath: json['audioFilePath'] as String? ?? '',
      thumbnailFilePath: rawThumbFile,
      thumbnailUrl: cleanThumb,
      audioCodec: json['audioCodec'] as String? ?? 'OPUS',
      bitrate: json['bitrate'] as int?,
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      downloadedAt: json['downloadedAt'] != null
          ? DateTime.tryParse(json['downloadedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

enum DownloadStatus { queued, downloading, completed, failed, canceled }

/// Represents an active or pending download in progress.
class DownloadTask {
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String? thumbnailUrl;
  DownloadStatus status;
  double progress; // 0.0 to 1.0
  int downloadedBytes;
  int totalBytes;
  int speedBytesPerSec;
  String? error;
  http.Client? _client;

  DownloadTask({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.thumbnailUrl,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.error,
  });

  void cancel() {
    status = DownloadStatus.canceled;
    _client?.close();
  }
}

/// Service managing offline music downloads, progress tracking, and storage optimization.
class DownloadService extends ChangeNotifier {
  static const String _prefsKey = 'finaudio_downloaded_tracks_v1';
  static final DownloadService instance = DownloadService._internal();

  factory DownloadService() => instance;
  DownloadService._internal();

  final List<DownloadedTrack> _downloadedTracks = [];
  final Map<String, DownloadTask> _activeTasks = {};
  bool _initialized = false;
  String? _downloadsDir;

  static const int maxConcurrentDownloads = 2;
  final List<Track> _downloadQueue = [];
  final Set<String> _runningTrackIds = {};
  final Map<String, ({String quality, String? preferredCodec})> _taskOptions = {};

  List<DownloadedTrack> get downloadedTracks => List.unmodifiable(_downloadedTracks);
  List<DownloadTask> get activeTasks => _activeTasks.values.toList();
  int get downloadedCount => _downloadedTracks.length;
  bool get hasActiveDownloads => _activeTasks.isNotEmpty;
  int get queuedCount => _activeTasks.values.where((t) => t.status == DownloadStatus.queued).length;
  int get runningCount => _activeTasks.values.where((t) => t.status == DownloadStatus.downloading).length;

  /// Initializes the service and restores persisted downloads from storage.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${docDir.path}/finaudio_downloads');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _downloadsDir = dir.path;

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
        _downloadedTracks.clear();
        for (final item in list) {
          try {
            final track = DownloadedTrack.fromJson(item as Map<String, dynamic>);
            // Verify file still exists on disk
            if (File(track.audioFilePath).existsSync()) {
              _downloadedTracks.add(track);
            }
          } catch (e) {
            debugPrint('DownloadService: Failed to parse item: $e');
          }
        }
      }
      debugPrint('DownloadService: Initialized with ${_downloadedTracks.length} offline tracks');
    } catch (e) {
      debugPrint('DownloadService: init failed: $e');
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_downloadedTracks.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, raw);
    } catch (e) {
      debugPrint('DownloadService: Save failed: $e');
    }
  }

  /// Total physical bytes used by all downloaded audio and artwork files.
  int get totalBytesUsed {
    int total = 0;
    for (final t in _downloadedTracks) {
      total += t.fileSizeBytes;
    }
    return total;
  }

  /// Formatted storage string, e.g. "24.5 MB" or "1.2 GB".
  String get formattedStorageUsed {
    final bytes = totalBytesUsed;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{\)\]\}]'), '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Finds a downloaded track matching by track ID, YouTube video ID, or normalized title + artist.
  DownloadedTrack? findDownloadedTrack({
    String? id,
    String? title,
    String? artist,
    String? youtubeVideoId,
  }) {
    for (final t in _downloadedTracks) {
      bool candidate = false;
      // 1. Direct ID match
      if (id != null && id.isNotEmpty) {
        if (t.id == id || t.youtubeVideoId == id) candidate = true;
      }
      // 2. YouTube Video ID match
      if (!candidate && youtubeVideoId != null && youtubeVideoId.isNotEmpty) {
        if (t.id == youtubeVideoId || t.youtubeVideoId == youtubeVideoId) candidate = true;
      }
      // 3. Title + Artist fuzzy/normalized match
      if (!candidate && title != null && title.trim().isNotEmpty) {
        final tTitle = _normalize(t.title);
        final qTitle = _normalize(title);
        if (tTitle.isNotEmpty && (tTitle == qTitle || tTitle.contains(qTitle) || qTitle.contains(tTitle))) {
          if (artist == null || artist.trim().isEmpty) {
            candidate = true;
          } else {
            final tArtist = _normalize(t.artist);
            final qArtist = _normalize(artist);
            if (tArtist.isEmpty || qArtist.isEmpty || tArtist == qArtist || tArtist.contains(qArtist) || qArtist.contains(tArtist)) {
              candidate = true;
            }
          }
        }
      }

      if (candidate && File(t.audioFilePath).existsSync()) {
        return t;
      }
    }
    return null;
  }

  /// Checks if a track with the given ID or title/artist is downloaded and exists locally.
  bool isDownloaded(String trackId, {String? title, String? artist}) {
    return findDownloadedTrack(id: trackId, title: title, artist: artist) != null;
  }

  /// Gets the downloaded track if it exists, matching by track ID or title/artist.
  DownloadedTrack? getDownloadedTrack(String trackId, {String? title, String? artist}) {
    return findDownloadedTrack(id: trackId, title: title, artist: artist);
  }

  /// Generates progressive search queries for resolving YouTube matches,
  /// cleaning multi-artist semicolons, slashes, and parenthetical subtitles.
  static List<String> buildSearchQueries(Track track) {
    final queries = <String>[];
    final title = track.title.trim();
    final rawArtist = track.author.trim();

    // 1. Clean artists (split on semicolon, slash, or comma)
    final artists = rawArtist
        .split(RegExp(r'[;/]'))
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();
    final primaryArtist = artists.isNotEmpty ? artists.first : rawArtist;
    final spacedArtists = artists.join(' ');

    // 2. Clean title (strip "(feat. ...)", "(tippy tappy toes)", "[...]", etc.)
    final cleanTitle = title
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\s+-\s+.*$'), '')
        .trim();

    // Query 1: Primary artist + clean title (e.g. "Scrawny Six Legs" or "MIMI minimum")
    if (cleanTitle.isNotEmpty) {
      queries.add('$primaryArtist $cleanTitle');
    }

    // Query 2: Spaced artists + clean title (e.g. "Scrawny Elio Mei Six Legs")
    if (cleanTitle.isNotEmpty && spacedArtists.isNotEmpty && spacedArtists != primaryArtist) {
      queries.add('$spacedArtists $cleanTitle');
    }

    // Query 3: Spaced artists + full title
    if (spacedArtists.isNotEmpty && spacedArtists != rawArtist) {
      queries.add('$spacedArtists $title');
    } else {
      queries.add('$rawArtist $title');
    }

    // Query 4: Raw artist + title + "audio"
    queries.add('$rawArtist $title audio');

    // Query 5: Clean title alone (if distinctive)
    if (cleanTitle.isNotEmpty && cleanTitle.length > 5 && cleanTitle != title) {
      queries.add(cleanTitle);
    }

    // Deduplicate while preserving order
    final result = <String>[];
    for (final q in queries) {
      final norm = q.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (norm.isNotEmpty && !result.contains(norm)) {
        result.add(norm);
      }
    }
    return result;
  }

  /// Returns whether a candidate ID looks like a valid 11-char YouTube video ID.
  static bool isValidYouTubeVideoId(String? id, {String? title}) {
    if (id == null || id.isEmpty) return false;
    final trimmed = id.trim();
    if (trimmed.length != 11) return false;
    if (trimmed.contains(' ')) return false;
    if (title != null && trimmed.toLowerCase() == title.trim().toLowerCase()) {
      return false; // Title happens to have 11 characters (e.g. "Mockingbird")
    }
    if (trimmed.startsWith('track_') || trimmed.startsWith('spotify:') || trimmed.startsWith('local_')) {
      return false;
    }
    return RegExp(r'^[0-9A-Za-z_-]{11}$').hasMatch(trimmed);
  }

  /// Searches YouTube using progressively simplified queries, handling FormatException
  /// and falling back to InnerTube YTMusic search if needed.
  Future<String?> _resolveVideoIdFromSearch(Track track, YoutubeService yt) async {
    final queries = buildSearchQueries(track);
    for (final q in queries) {
      try {
        debugPrint('DownloadService: Searching YouTube for "$q"…');
        final results = await yt.search(q);
        if (results.isNotEmpty) {
          final first = results.first;
          return first.id.value;
        }
      } catch (e) {
        debugPrint('DownloadService: yt.search failed on "$q": $e');
        // Continue to next query if FormatException or search error occurs
      }
    }

    // Fallback: search via InnerTube YTMusic
    for (final q in queries.take(2)) {
      try {
        debugPrint('DownloadService: Searching YTMusic InnerTube fallback for "$q"…');
        final musicResults = await yt.searchYTMusic(q);
        for (final item in musicResults) {
          if (item is Map) {
            final vid = item['videoId'] as String?;
            if (vid != null && vid.isNotEmpty) {
              return vid;
            }
          }
        }
      } catch (e) {
        debugPrint('DownloadService: yt.searchYTMusic fallback failed on "$q": $e');
      }
    }

    return null;
  }

  /// Pumps queued download tasks up to [maxConcurrentDownloads].
  void _pumpQueue() {
    while (_runningTrackIds.length < maxConcurrentDownloads && _downloadQueue.isNotEmpty) {
      final track = _downloadQueue.removeAt(0);
      final task = _activeTasks[track.id];
      if (task == null || task.status == DownloadStatus.canceled) {
        continue;
      }
      _runningTrackIds.add(track.id);
      final opts = _taskOptions[track.id] ?? (quality: 'low', preferredCodec: null);
      _executeDownload(track, quality: opts.quality, preferredCodec: opts.preferredCodec).whenComplete(() {
        _runningTrackIds.remove(track.id);
        _taskOptions.remove(track.id);
        _pumpQueue();
      });
    }
  }

  /// Enqueues a single track for offline download.
  Future<void> startDownload(
    Track track, {
    String quality = 'low',
    String? preferredCodec,
  }) =>
      downloadTrack(track, quality: quality, preferredCodec: preferredCodec);

  /// Enqueues a single track for offline download.
  Future<void> downloadTrack(
    Track track, {
    String quality = 'low', // Default to low (space saver ~1.3MB/song)
    String? preferredCodec,
  }) async {
    final trackId = track.id;
    if (trackId.isEmpty || isDownloaded(trackId)) return;
    if (_activeTasks.containsKey(trackId)) {
      final existing = _activeTasks[trackId]!;
      if (existing.status == DownloadStatus.downloading || existing.status == DownloadStatus.queued) {
        return;
      }
    }

    await _ensureDownloadsDir();

    final task = DownloadTask(
      id: trackId,
      title: track.title,
      artist: track.author,
      duration: track.duration,
      thumbnailUrl: track.thumbnailUrl,
      status: DownloadStatus.queued,
    );
    _activeTasks[trackId] = task;
    _taskOptions[trackId] = (quality: quality, preferredCodec: preferredCodec);
    _downloadQueue.removeWhere((t) => t.id == trackId);
    _downloadQueue.add(track);
    notifyListeners();
    _pumpQueue();
  }

  Future<void> _ensureDownloadsDir() async {
    if (_downloadsDir != null) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${docDir.path}/finaudio_downloads');
      if (!await dir.exists()) await dir.create(recursive: true);
      _downloadsDir = dir.path;
    } catch (e) {
      debugPrint('DownloadService: Falling back to temp directory for downloads: $e');
      _downloadsDir = Directory.systemTemp.path;
    }
  }

  /// Batch download a list of tracks (e.g. for "Download All / Download Playlist").
  /// Queues tasks with bounded worker concurrency to keep phone performance 100% smooth.
  Future<void> downloadTracks(
    List<Track> tracks, {
    String quality = 'low',
    String? preferredCodec,
  }) async {
    await _ensureDownloadsDir();

    bool addedAny = false;
    for (final track in tracks) {
      final trackId = track.id;
      if (trackId.isEmpty || isDownloaded(trackId)) continue;
      if (_activeTasks.containsKey(trackId)) {
        final existing = _activeTasks[trackId]!;
        if (existing.status == DownloadStatus.downloading || existing.status == DownloadStatus.queued) {
          continue;
        }
      }

      final task = DownloadTask(
        id: trackId,
        title: track.title,
        artist: track.author,
        duration: track.duration,
        thumbnailUrl: track.thumbnailUrl,
        status: DownloadStatus.queued,
      );
      _activeTasks[trackId] = task;
      _taskOptions[trackId] = (quality: quality, preferredCodec: preferredCodec);
      _downloadQueue.removeWhere((t) => t.id == trackId);
      _downloadQueue.add(track);
      addedAny = true;
    }

    if (addedAny) {
      notifyListeners();
      _pumpQueue();
    }
  }

  /// Worker method executing the actual download stream acquisition and file write.
  Future<void> _executeDownload(
    Track track, {
    String quality = 'low',
    String? preferredCodec,
  }) async {
    final trackId = track.id;
    final task = _activeTasks[trackId];
    if (task == null || task.status == DownloadStatus.canceled) return;

    task.status = DownloadStatus.downloading;
    notifyListeners();

    try {
      final yt = YoutubeService();

      // Check for candidate YouTube video ID from youtubeUrl or trackId
      String? candidateVideoId;
      if (track.youtubeUrl.isNotEmpty) {
        final match = RegExp(r'(?:v=|\/|youtu\.be\/)([0-9A-Za-z_-]{11})').firstMatch(track.youtubeUrl);
        if (match != null && isValidYouTubeVideoId(match.group(1), title: track.title)) {
          candidateVideoId = match.group(1);
        }
      }
      if (candidateVideoId == null && isValidYouTubeVideoId(trackId, title: track.title)) {
        candidateVideoId = trackId;
      }

      ResolvedVideo? resolved;
      String effectiveVideoId = '';

      if (candidateVideoId != null) {
        try {
          debugPrint('DownloadService: Attempting stream resolution for candidate ID "$candidateVideoId"…');
          resolved = await yt.resolveAudioStream(candidateVideoId, quality: quality);
          effectiveVideoId = candidateVideoId;
        } catch (candidateErr) {
          debugPrint('DownloadService: Direct resolution failed for "$candidateVideoId" ($candidateErr). Falling back to search.');
          resolved = null;
        }
      }

      if (resolved == null) {
        final foundId = await _resolveVideoIdFromSearch(track, yt);
        if (foundId == null) {
          throw Exception('No YouTube match found for "${track.title}"');
        }
        effectiveVideoId = foundId;
        debugPrint('DownloadService: Resolving stream for searched ID $effectiveVideoId ($quality quality)...');
        resolved = await yt.resolveAudioStream(effectiveVideoId, quality: quality);
      }

      final ext = (resolved.container.toLowerCase().contains('webm') ||
              resolved.audioCodec.toUpperCase() == 'OPUS')
          ? 'opus'
          : (resolved.container.toLowerCase().contains('m4a') ? 'm4a' : 'opus');

      final safeKey = (effectiveVideoId.isNotEmpty && effectiveVideoId.length == 11 && !effectiveVideoId.contains(' '))
          ? effectiveVideoId
          : trackId.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final audioPath = '$_downloadsDir/$safeKey.$ext';
      final tempAudioPath = '$audioPath.tmp';
      final thumbPath = '$_downloadsDir/$safeKey.jpg';

      final client = http.Client();
      task._client = client;

      final tempFile = File(tempAudioPath);
      if (await tempFile.exists()) await tempFile.delete();
      final sink = tempFile.openWrite();

      final streamUri = resolved.audioStreamUrl;
      const headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        'Referer': 'https://www.youtube.com/',
        'Origin': 'https://www.youtube.com',
      };

      // Discover stream total content length using Range probe or HEAD request
      int totalBytes = 0;
      try {
        final probeReq = http.Request('GET', streamUri);
        probeReq.headers.addAll(headers);
        probeReq.headers['Range'] = 'bytes=0-1';
        final probeRes = await client.send(probeReq).timeout(const Duration(seconds: 5));
        final cr = probeRes.headers['content-range'];
        if (cr != null) {
          final m = RegExp(r'/(\d+)').firstMatch(cr);
          if (m != null) totalBytes = int.tryParse(m.group(1)!) ?? 0;
        }
        if (totalBytes <= 0 && probeRes.contentLength != null && probeRes.contentLength! > 2) {
          totalBytes = probeRes.contentLength!;
        }
      } catch (_) {}

      final stopwatch = Stopwatch()..start();
      int receivedBytes = 0;
      int lastEmittedBytes = 0;
      int lastEmittedMs = 0;

      if (totalBytes > 0) {
        // High-speed Chunked Range Downloading (512KB chunks bypass YouTube media pacing)
        task.totalBytes = totalBytes;
        const chunkSize = 512 * 1024; // 512 KB per chunk
        int currentByte = 0;

        while (currentByte < totalBytes) {
          if (task.status == DownloadStatus.canceled) break;
          final nextByte = min(currentByte + chunkSize - 1, totalBytes - 1);

          bool chunkSuccess = false;
          int retries = 0;
          while (!chunkSuccess && retries < 3) {
            retries++;
            try {
              final chunkReq = http.Request('GET', streamUri);
              chunkReq.headers.addAll(headers);
              chunkReq.headers['Range'] = 'bytes=$currentByte-$nextByte';
              final chunkRes = await client.send(chunkReq).timeout(const Duration(seconds: 15));

              if (chunkRes.statusCode == 206 || chunkRes.statusCode == 200) {
                final chunkBytes = await chunkRes.stream.toBytes();
                sink.add(chunkBytes);
                currentByte += chunkBytes.length;
                receivedBytes = currentByte;
                chunkSuccess = true;

                final elapsedMs = stopwatch.elapsedMilliseconds;
                if (elapsedMs - lastEmittedMs > 250 || currentByte >= totalBytes) {
                  final deltaBytes = receivedBytes - lastEmittedBytes;
                  final deltaSec = (elapsedMs - lastEmittedMs) / 1000.0;
                  final speed = deltaSec > 0 ? (deltaBytes / deltaSec).round() : 0;
                  lastEmittedBytes = receivedBytes;
                  lastEmittedMs = elapsedMs;

                  task.downloadedBytes = receivedBytes;
                  task.progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
                  task.speedBytesPerSec = speed;
                  notifyListeners();
                }
              } else {
                throw Exception('HTTP status ${chunkRes.statusCode}');
              }
            } catch (chunkErr) {
              if (retries >= 3) rethrow;
              await Future.delayed(const Duration(milliseconds: 350));
            }
          }
        }
      } else {
        // Fallback: standard progressive stream download
        final request = http.Request('GET', streamUri);
        request.headers.addAll(headers);
        final response = await client.send(request);
        if (response.statusCode >= 400) {
          throw Exception('Download stream rejected with HTTP ${response.statusCode}');
        }
        totalBytes = response.contentLength ?? 0;
        task.totalBytes = totalBytes;

        await response.stream.listen(
          (chunk) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            final elapsedMs = stopwatch.elapsedMilliseconds;
            if (elapsedMs - lastEmittedMs > 350) {
              final deltaBytes = receivedBytes - lastEmittedBytes;
              final deltaSec = (elapsedMs - lastEmittedMs) / 1000.0;
              final speed = deltaSec > 0 ? (deltaBytes / deltaSec).round() : 0;
              lastEmittedBytes = receivedBytes;
              lastEmittedMs = elapsedMs;

              task.downloadedBytes = receivedBytes;
              task.progress = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
              task.speedBytesPerSec = speed;
              notifyListeners();
            }
          },
          cancelOnError: true,
        ).asFuture();
      }

      await sink.flush();
      await sink.close();

      if (task.status == DownloadStatus.canceled) {
        if (await tempFile.exists()) await tempFile.delete();
        _activeTasks.remove(trackId);
        notifyListeners();
        return;
      }

      // Rename temp file to destination
      final finalFile = File(audioPath);
      if (await finalFile.exists()) await finalFile.delete();
      await tempFile.rename(audioPath);

      // Download thumbnail image for offline UI
      final effectiveThumb = (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
          ? track.thumbnailUrl!
          : 'https://img.youtube.com/vi/$effectiveVideoId/hqdefault.jpg';

      try {
        final thumbRes = await http.get(Uri.parse(effectiveThumb)).timeout(const Duration(seconds: 6));
        if (thumbRes.statusCode == 200) {
          await File(thumbPath).writeAsBytes(thumbRes.bodyBytes);
        }
      } catch (thumbErr) {
        debugPrint('DownloadService: Thumbnail download non-fatal error: $thumbErr');
      }

      final finalFileSize = await finalFile.length();
      final downloadedTrack = DownloadedTrack(
        id: trackId,
        youtubeVideoId: effectiveVideoId,
        title: track.title,
        artist: track.author,
        duration: resolved.duration != Duration.zero ? resolved.duration : track.duration,
        audioFilePath: audioPath,
        thumbnailFilePath: File(thumbPath).existsSync() ? thumbPath : null,
        thumbnailUrl: effectiveThumb,
        audioCodec: resolved.audioCodec,
        bitrate: resolved.bitrate,
        fileSizeBytes: finalFileSize,
        downloadedAt: DateTime.now(),
      );

      _downloadedTracks.removeWhere((t) =>
          t.id == trackId ||
          (t.youtubeVideoId != null && t.youtubeVideoId == effectiveVideoId));
      _downloadedTracks.insert(0, downloadedTrack);
      await _saveToPrefs();

      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      _activeTasks.remove(trackId);
      notifyListeners();
      debugPrint('DownloadService: Completed download for $trackId ($finalFileSize bytes, ${resolved.audioCodec})');
    } catch (e) {
      debugPrint('DownloadService: Error downloading $trackId: $e');
      task.status = DownloadStatus.failed;
      task.error = e.toString().replaceFirst('Exception: ', '');
      // Retain in active tasks so the user sees the error and can tap Retry
      notifyListeners();
    }
  }

  /// Retries a failed download task.
  void retryDownload(String trackId) {
    final task = _activeTasks[trackId];
    if (task != null) {
      final t = Track(
        id: task.id,
        title: task.title,
        author: task.artist,
        youtubeUrl: isValidYouTubeVideoId(task.id, title: task.title)
            ? 'https://www.youtube.com/watch?v=${task.id}'
            : '',
        duration: task.duration,
        thumbnailUrl: task.thumbnailUrl,
      );
      _activeTasks.remove(trackId);
      _runningTrackIds.remove(trackId);
      _downloadQueue.removeWhere((item) => item.id == trackId);
      downloadTrack(t);
    }
  }

  /// Dismisses an in-progress or failed download task.
  void dismissTask(String trackId) {
    _downloadQueue.removeWhere((t) => t.id == trackId);
    _taskOptions.remove(trackId);
    final task = _activeTasks[trackId];
    if (task != null) {
      task.cancel();
      _runningTrackIds.remove(trackId);
      _activeTasks.remove(trackId);
      notifyListeners();
      _pumpQueue();
    }
  }

  /// Cancels an in-progress or queued download task.
  void cancelDownload(String trackId) {
    _downloadQueue.removeWhere((t) => t.id == trackId);
    _taskOptions.remove(trackId);
    final task = _activeTasks[trackId];
    if (task != null) {
      task.cancel();
      _runningTrackIds.remove(trackId);
      _activeTasks.remove(trackId);
      notifyListeners();
      _pumpQueue();
    }
  }

  /// Deletes a downloaded track and its associated audio/thumbnail files.
  Future<void> deleteDownload(String trackId) async {
    final index = _downloadedTracks.indexWhere((t) => t.id == trackId);
    if (index != -1) {
      final track = _downloadedTracks.removeAt(index);
      try {
        final audioFile = File(track.audioFilePath);
        if (await audioFile.exists()) await audioFile.delete();
        if (track.thumbnailFilePath != null) {
          final thumbFile = File(track.thumbnailFilePath!);
          if (await thumbFile.exists()) await thumbFile.delete();
        }
      } catch (e) {
        debugPrint('DownloadService: Error deleting files for $trackId: $e');
      }
      await _saveToPrefs();
      notifyListeners();
    }
  }

  /// Deletes all downloaded tracks and clears offline storage.
  Future<void> deleteAllDownloads() async {
    for (final track in _downloadedTracks) {
      try {
        final audioFile = File(track.audioFilePath);
        if (await audioFile.exists()) await audioFile.delete();
        if (track.thumbnailFilePath != null) {
          final thumbFile = File(track.thumbnailFilePath!);
          if (await thumbFile.exists()) await thumbFile.delete();
        }
      } catch (_) {}
    }
    _downloadedTracks.clear();
    await _saveToPrefs();
    notifyListeners();
  }
}

