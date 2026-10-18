import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/local_playlist.dart';
import 'download_service.dart';
import 'player_service.dart';
import 'spotify_service.dart';
import 'youtube_service.dart';

/// Service managing persistent playlists (local playlists and imported Spotify playlists).
class PlaylistService extends ChangeNotifier {
  static const String _storageKey = 'local_playlists';
  static const String likedSongsId = 'liked_songs';
  static final PlaylistService instance = PlaylistService._internal();

  factory PlaylistService() => instance;
  PlaylistService._internal();

  final List<LocalPlaylist> _playlists = [];
  final SpotifyService _spotifyService = SpotifyService();
  bool _initialized = false;

  List<LocalPlaylist> get playlists => List.unmodifiable(_playlists);
  bool get isInitialized => _initialized;

  /// Returns the permanent Liked Songs playlist.
  LocalPlaylist get likedSongsPlaylist {
    final found = getPlaylist(likedSongsId);
    if (found != null) return found;
    return LocalPlaylist(
      id: likedSongsId,
      title: 'Liked Songs',
      description: 'Your favorite tracks in one place',
      source: 'system',
      createdAt: DateTime.now(),
    );
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        _playlists.clear();
        _playlists.addAll(LocalPlaylist.decodeList(jsonStr));
      }
    } catch (e) {
      debugPrint('PlaylistService: Error loading playlists: $e');
    }

    // Ensure the permanent Liked Songs playlist always exists and is at the top
    final likedIndex = _playlists.indexWhere((p) => p.id == likedSongsId);
    if (likedIndex < 0) {
      final existingLikedIndex = _playlists.indexWhere(
        (p) => p.title.trim().toLowerCase() == 'liked songs',
      );
      if (existingLikedIndex >= 0) {
        final existing = _playlists[existingLikedIndex];
        _playlists[existingLikedIndex] = existing.copyWith(
          id: likedSongsId,
          source: 'system',
        );
      } else {
        _playlists.insert(
          0,
          LocalPlaylist(
            id: likedSongsId,
            title: 'Liked Songs',
            description: 'Your favorite tracks in one place',
            source: 'system',
            createdAt: DateTime.now(),
            tracks: const [],
          ),
        );
      }
      await _persist();
    }

    _initialized = true;
    notifyListeners();
  }

  LocalPlaylist? getPlaylist(String id) {
    try {
      return _playlists.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> savePlaylist(LocalPlaylist playlist) async {
    final index = _playlists.indexWhere((p) => p.id == playlist.id);
    if (index >= 0) {
      _playlists[index] = playlist;
    } else {
      _playlists.insert(0, playlist);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    // Liked Songs is a permanent playlist that cannot be deleted
    if (id == likedSongsId) {
      debugPrint('PlaylistService: Cannot delete Liked Songs playlist.');
      return;
    }
    _playlists.removeWhere((p) => p.id == id);
    await _persist();
    notifyListeners();
  }

  /// Creates a new custom local playlist and returns it.
  Future<LocalPlaylist> createPlaylist({
    required String title,
    String description = '',
    String thumbnailUrl = '',
  }) async {
    final playlist = LocalPlaylist(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim().isNotEmpty ? title.trim() : 'Custom Playlist',
      description: description,
      thumbnailUrl: thumbnailUrl,
      source: 'local',
      createdAt: DateTime.now(),
      tracks: const [],
    );
    _playlists.insert(0, playlist);
    await _persist();
    notifyListeners();
    return playlist;
  }

  /// Checks if a song is in the Liked Songs playlist.
  bool isTrackLiked(String? videoId, String title, String artist) {
    return isTrackInPlaylist(likedSongsId, videoId, title, artist);
  }

  /// Toggles like status for a track. Returns true if liked, false if unliked.
  Future<bool> toggleLikeTrack(LocalPlaylistTrack track) async {
    final inList = isTrackInPlaylist(likedSongsId, track.youtubeVideoId, track.title, track.artist);
    if (inList) {
      await removeTrackFromPlaylist(likedSongsId, track);
      return false;
    } else {
      await addTrackToPlaylist(likedSongsId, track);
      return true;
    }
  }

  /// Batch adds all given tracks to the Liked Songs playlist.
  /// Returns the number of newly added tracks.
  Future<int> addAllToLikedSongs(List<LocalPlaylistTrack> tracks) async {
    final liked = likedSongsPlaylist;
    final updated = List<LocalPlaylistTrack>.from(liked.tracks);
    int added = 0;

    for (final track in tracks) {
      final cleanTitle = track.title.trim().toLowerCase();
      final cleanArtist = track.artist.trim().toLowerCase();
      final hasVid = track.youtubeVideoId != null && track.youtubeVideoId!.isNotEmpty;

      final alreadyExists = updated.any((t) {
        if (hasVid && t.youtubeVideoId != null && t.youtubeVideoId!.isNotEmpty) {
          if (t.youtubeVideoId == track.youtubeVideoId) return true;
        }
        return t.title.trim().toLowerCase() == cleanTitle &&
               t.artist.trim().toLowerCase() == cleanArtist;
      });

      if (!alreadyExists) {
        updated.add(track);
        added++;
      }
    }

    if (added > 0) {
      await savePlaylist(liked.copyWith(tracks: updated));
    }
    return added;
  }

  /// Checks if a song is in a given playlist by ID.
  bool isTrackInPlaylist(String playlistId, String? videoId, String title, String artist) {
    final p = getPlaylist(playlistId);
    if (p == null) return false;
    final cleanTitle = title.trim().toLowerCase();
    final cleanArtist = artist.trim().toLowerCase();
    final hasVid = videoId != null && videoId.isNotEmpty;

    return p.tracks.any((t) {
      if (hasVid && t.youtubeVideoId != null && t.youtubeVideoId!.isNotEmpty) {
        if (t.youtubeVideoId == videoId) return true;
      }
      return t.title.trim().toLowerCase() == cleanTitle &&
             t.artist.trim().toLowerCase() == cleanArtist;
    });
  }

  /// Adds a track to a playlist if not already present.
  Future<void> addTrackToPlaylist(String playlistId, LocalPlaylistTrack track) async {
    final p = getPlaylist(playlistId);
    if (p == null) return;
    if (isTrackInPlaylist(playlistId, track.youtubeVideoId, track.title, track.artist)) {
      return;
    }
    final updatedTracks = List<LocalPlaylistTrack>.from(p.tracks)..insert(0, track);
    await savePlaylist(p.copyWith(tracks: updatedTracks));
  }

  /// Removes a track from a playlist.
  Future<void> removeTrackFromPlaylist(String playlistId, LocalPlaylistTrack track) async {
    final p = getPlaylist(playlistId);
    if (p == null) return;
    final cleanTitle = track.title.trim().toLowerCase();
    final cleanArtist = track.artist.trim().toLowerCase();
    final hasVid = track.youtubeVideoId != null && track.youtubeVideoId!.isNotEmpty;

    final updatedTracks = p.tracks.where((t) {
      if (hasVid && t.youtubeVideoId != null && t.youtubeVideoId!.isNotEmpty) {
        if (t.youtubeVideoId == track.youtubeVideoId) return false;
      }
      return !(t.title.trim().toLowerCase() == cleanTitle &&
               t.artist.trim().toLowerCase() == cleanArtist);
    }).toList();

    await savePlaylist(p.copyWith(tracks: updatedTracks));
  }

  /// Creates and saves a playlist imported from Spotify.
  Future<LocalPlaylist> createFromSpotify(SpotifyImportResult importResult) async {
    // Check if we already imported this Spotify playlist ID
    final existingIndex =
        _playlists.indexWhere((p) => p.spotifyId == importResult.id);

    final playlist = importResult.toLocalPlaylist();

    if (existingIndex >= 0) {
      // Update existing
      final existing = _playlists[existingIndex];
      final updated = playlist.copyWith(
        id: existing.id,
        createdAt: existing.createdAt,
      );
      _playlists[existingIndex] = updated;
      await _persist();
      notifyListeners();
      return updated;
    } else {
      _playlists.insert(0, playlist);
      await _persist();
      notifyListeners();
      return playlist;
    }
  }

  /// Parses text lines and creates a local playlist.
  /// Supports:
  ///   - CSV / Exportify export formats ("Track Name,Artist Name(s),...")
  ///   - "Artist - Title" or "1. Artist - Title"
  ///   - "Artist – Title"
  ///   - "Title by Artist"
  Future<LocalPlaylist> createFromText({
    required String title,
    required String rawText,
    String description = 'Imported from text list',
  }) async {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final tracks = <LocalPlaylistTrack>[];

    // Check if first line is a CSV header row (e.g. Exportify)
    int startIndex = 0;
    int titleCol = -1;
    int artistCol = -1;

    if (lines.isNotEmpty) {
      final header = lines.first.toLowerCase();
      if (header.contains('track name') ||
          header.contains('artist name') ||
          header.contains('track uri') ||
          header.contains('song name')) {
        startIndex = 1; // Skip header
        final cols = lines.first.split(',').map((c) => c.replaceAll('"', '').trim().toLowerCase()).toList();
        titleCol = cols.indexWhere((c) => c.contains('track name') || c.contains('song') || c == 'title');
        artistCol = cols.indexWhere((c) => c.contains('artist'));
      }
    }

    for (int i = startIndex; i < lines.length; i++) {
      final rawLine = lines[i];

      // If recognized as CSV format with known columns
      if (titleCol >= 0 && artistCol >= 0 && rawLine.contains(',')) {
        final regex = RegExp(r'(?:^|,)(?:"([^"]*)"|([^,]*))');
        final matches = regex.allMatches(rawLine).map((m) => (m.group(1) ?? m.group(2) ?? '').trim()).toList();
        if (matches.length > titleCol && matches.length > artistCol) {
          final tTitle = matches[titleCol];
          final rawArtist = matches[artistCol];
          if (tTitle.isNotEmpty) {
            final split = LocalPlaylistTrack.splitArtists(rawArtist);
            final cleanArtist = split.isNotEmpty ? split.join(', ') : (rawArtist.isNotEmpty ? rawArtist : 'Unknown Artist');
            tracks.add(
              LocalPlaylistTrack(
                title: tTitle,
                artist: cleanArtist,
              ),
            );
            continue;
          }
        }
      }

      // Remove leading numbering like "1.", "1 -", "[1]"
      var line = rawLine.replaceFirst(RegExp(r'^\s*\[?\d+\]?[\.\-\)\s]+\s*'), '');

      String trackTitle = line;
      String artist = 'Unknown Artist';

      if (line.contains(' - ')) {
        final parts = line.split(' - ');
        if (parts.length >= 2) {
          artist = parts[0].trim();
          trackTitle = parts.sublist(1).join(' - ').trim();
        }
      } else if (line.contains(' – ')) {
        final parts = line.split(' – ');
        if (parts.length >= 2) {
          artist = parts[0].trim();
          trackTitle = parts.sublist(1).join(' – ').trim();
        }
      } else if (line.contains(' by ') && !line.contains(' - ')) {
        final parts = line.split(' by ');
        if (parts.length >= 2) {
          trackTitle = parts[0].trim();
          artist = parts.sublist(1).join(' by ').trim();
        }
      } else if (line.contains(',')) {
        final parts = line.split(',');
        if (parts.length >= 2) {
          trackTitle = parts[0].trim();
          artist = parts.sublist(1).join(',').trim();
        }
      }

      final split = LocalPlaylistTrack.splitArtists(artist);
      final cleanArtist = split.isNotEmpty ? split.join(', ') : (artist.isNotEmpty ? artist : 'Unknown Artist');

      tracks.add(
        LocalPlaylistTrack(
          title: trackTitle,
          artist: cleanArtist,
        ),
      );
    }

    final playlist = LocalPlaylist(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim().isNotEmpty ? title.trim() : 'Custom Playlist',
      description: description,
      source: 'text',
      createdAt: DateTime.now(),
      tracks: tracks,
    );

    _playlists.insert(0, playlist);
    await _persist();
    notifyListeners();
    resolvePlaylistTracks(playlist.id).catchError((e) {
      debugPrint('PlaylistService: Background resolution failed: $e');
      return 0;
    });
    return playlist;
  }

  /// Re-syncs a Spotify playlist by ID and saves the updated tracks.
  Future<LocalPlaylist> syncSpotifyPlaylist(
    String playlistId, {
    String? clientId,
    String? clientSecret,
    void Function(int fetched, int total)? onProgress,
  }) async {
    final existing = getPlaylist(playlistId);
    if (existing == null) {
      throw Exception('Playlist not found.');
    }
    if (!existing.isSpotify) {
      throw Exception('This playlist is not linked to Spotify.');
    }

    final updated = await _spotifyService.syncPlaylist(
      existing,
      clientId: clientId,
      clientSecret: clientSecret,
      onProgress: onProgress,
    );
    await savePlaylist(updated);
    resolvePlaylistTracks(updated.id).catchError((e) {
      debugPrint('PlaylistService: Background resolution failed: $e');
      return 0;
    });
    return updated;
  }

  /// Resolves matching YouTube video IDs for all tracks in [playlistId] that lack one.
  /// Uses sanitized progressive search queries and InnerTube YTMusic fallback.
  /// Updates tracks in real-time, persists changes, and notifies listeners.
  Future<int> resolvePlaylistTracks(
    String playlistId, {
    void Function(int resolved, int total)? onProgress,
  }) async {
    final playlist = getPlaylist(playlistId);
    if (playlist == null || playlist.tracks.isEmpty) return 0;

    final yt = YoutubeService();
    int resolvedCount = 0;
    final total = playlist.tracks.length;

    final updatedTracks = List<LocalPlaylistTrack>.from(playlist.tracks);
    bool hasChanges = false;

    for (int i = 0; i < updatedTracks.length; i++) {
      final track = updatedTracks[i];
      if (track.youtubeVideoId != null && track.youtubeVideoId!.isNotEmpty) {
        resolvedCount++;
        onProgress?.call(resolvedCount, total);
        continue;
      }

      try {
        final queryTrack = Track(
          id: 'temp_$i',
          title: track.title,
          author: track.artist,
          youtubeUrl: '',
          duration: track.duration,
          thumbnailUrl: track.thumbnailUrl,
        );

        final queries = DownloadService.buildSearchQueries(queryTrack);
        String? foundVideoId;
        String? foundThumbnail;
        Duration? foundDuration;

        // 1. Try progressive clean queries with YoutubeExplode
        for (final q in queries) {
          try {
            final results = await yt.search(q);
            if (results.isNotEmpty) {
              final first = results.first;
              foundVideoId = first.id.value;
              foundThumbnail = first.thumbnails.highResUrl;
              foundDuration = first.duration;
              break;
            }
          } catch (_) {}
        }

        // 2. Try InnerTube YTMusic fallback if search returned no results
        if (foundVideoId == null) {
          for (final q in queries.take(2)) {
            try {
              final musicResults = await yt.searchYTMusic(q);
              for (final item in musicResults) {
                if (item is Map && item['videoId'] != null) {
                  final vId = item['videoId'].toString();
                  if (vId.isNotEmpty) {
                    foundVideoId = vId;
                    foundThumbnail = 'https://img.youtube.com/vi/$vId/hqdefault.jpg';
                    break;
                  }
                }
              }
              if (foundVideoId != null) break;
            } catch (_) {}
          }
        }

        if (foundVideoId != null && foundVideoId.isNotEmpty) {
          updatedTracks[i] = track.copyWith(
            youtubeVideoId: foundVideoId,
            thumbnailUrl: track.thumbnailUrl ?? foundThumbnail,
            duration: (track.duration == Duration.zero && foundDuration != null)
                ? foundDuration
                : track.duration,
          );
          hasChanges = true;
          resolvedCount++;
        }
      } catch (e) {
        debugPrint('PlaylistService: Could not resolve video ID for ${track.title}: $e');
      }

      onProgress?.call(resolvedCount, total);

      // Periodic persist every 5 tracks so progress is saved incrementally
      if (hasChanges && (i % 5 == 0 || i == updatedTracks.length - 1)) {
        final currentPlaylist = getPlaylist(playlistId);
        if (currentPlaylist != null) {
          await savePlaylist(currentPlaylist.copyWith(tracks: updatedTracks));
        }
      }

      // Yield politely to active audio playback and UI gestures
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (hasChanges) {
      final currentPlaylist = getPlaylist(playlistId);
      if (currentPlaylist != null) {
        await savePlaylist(currentPlaylist.copyWith(tracks: updatedTracks));
      }
    }

    return resolvedCount;
  }

  /// Updates a specific track's resolved YouTube ID and metadata across all playlists.
  Future<void> updateTrackResolvedVideoId({
    required String title,
    required String artist,
    required String youtubeVideoId,
    String? thumbnailUrl,
    Duration? duration,
  }) async {
    final cleanTitle = title.trim().toLowerCase();
    final cleanArtist = artist.trim().toLowerCase();
    bool anyChanged = false;

    for (int pIdx = 0; pIdx < _playlists.length; pIdx++) {
      final p = _playlists[pIdx];
      bool playlistChanged = false;
      final updatedTracks = List<LocalPlaylistTrack>.from(p.tracks);

      for (int tIdx = 0; tIdx < updatedTracks.length; tIdx++) {
        final t = updatedTracks[tIdx];
        if (t.title.trim().toLowerCase() == cleanTitle &&
            (t.artist.trim().toLowerCase() == cleanArtist || t.artist.isEmpty || cleanArtist.isEmpty)) {
          if (t.youtubeVideoId != youtubeVideoId) {
            updatedTracks[tIdx] = t.copyWith(
              youtubeVideoId: youtubeVideoId,
              thumbnailUrl: t.thumbnailUrl ?? thumbnailUrl,
              duration: t.duration == Duration.zero && duration != null ? duration : t.duration,
            );
            playlistChanged = true;
          }
        }
      }

      if (playlistChanged) {
        _playlists[pIdx] = p.copyWith(tracks: updatedTracks);
        anyChanged = true;
      }
    }

    if (anyChanged) {
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, LocalPlaylist.encodeList(_playlists));
    } catch (e) {
      debugPrint('PlaylistService: Error saving playlists: $e');
    }
  }
}

