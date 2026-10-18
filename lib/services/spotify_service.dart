import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/local_playlist.dart';

enum SpotifyEntityType { playlist, album, track, unknown }

class SpotifyParsedTarget {
  final SpotifyEntityType type;
  final String id;
  final String originalInput;

  const SpotifyParsedTarget({
    required this.type,
    required this.id,
    required this.originalInput,
  });
}

class SpotifyImportResult {
  final String id;
  final SpotifyEntityType type;
  final String title;
  final String description;
  final String thumbnailUrl;
  final List<LocalPlaylistTrack> tracks;
  final String sourceUrl;

  const SpotifyImportResult({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.tracks,
    required this.sourceUrl,
  });

  LocalPlaylist toLocalPlaylist() {
    return LocalPlaylist(
      id: 'spotify_${id}_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
      source: 'spotify',
      spotifyUrl: sourceUrl,
      spotifyId: id,
      createdAt: DateTime.now(),
      lastSyncedAt: DateTime.now(),
      tracks: tracks,
    );
  }
}

/// Service to parse, import, and sync playlists, albums, and tracks from Spotify.
/// Uses Spotify's public embed endpoints with zero authentication or API keys required.
class SpotifyService {
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/125.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Returns true if the given input is a Spotify link or URI.
  static bool isSpotifyUrl(String input) {
    final trimmed = input.trim();
    return trimmed.contains('spotify.com') ||
        trimmed.contains('spotify.link') ||
        trimmed.startsWith('spotify:');
  }

  /// Parses a Spotify URL or URI into its entity type and ID.
  static SpotifyParsedTarget? parseTarget(String input) {
    final trimmed = input.trim();
    if (!isSpotifyUrl(trimmed)) return null;

    // Handle spotify:playlist:id or spotify:track:id or spotify:album:id
    final uriRegex =
        RegExp(r'^spotify:(playlist|album|track):([a-zA-Z0-9]+)');
    final uriMatch = uriRegex.firstMatch(trimmed);
    if (uriMatch != null) {
      final typeStr = uriMatch.group(1);
      final id = uriMatch.group(2)!;
      final type = switch (typeStr) {
        'playlist' => SpotifyEntityType.playlist,
        'album' => SpotifyEntityType.album,
        'track' => SpotifyEntityType.track,
        _ => SpotifyEntityType.unknown,
      };
      return SpotifyParsedTarget(type: type, id: id, originalInput: trimmed);
    }

    // Handle open.spotify.com/(intl-[a-z]+/)?(playlist|album|track)/id
    final webRegex = RegExp(
        r'spotify\.com/(?:[a-zA-Z\-]+/)?(playlist|album|track)/([a-zA-Z0-9]+)');
    final webMatch = webRegex.firstMatch(trimmed);
    if (webMatch != null) {
      final typeStr = webMatch.group(1);
      final id = webMatch.group(2)!;
      final type = switch (typeStr) {
        'playlist' => SpotifyEntityType.playlist,
        'album' => SpotifyEntityType.album,
        'track' => SpotifyEntityType.track,
        _ => SpotifyEntityType.unknown,
      };
      return SpotifyParsedTarget(type: type, id: id, originalInput: trimmed);
    }

    return null;
  }

  /// Imports a Spotify playlist, album, or track from its URL or URI.
  /// If [clientId] and [clientSecret] are provided, it fetches all tracks
  /// (up to 1,000+ tracks) using the official Spotify Web API with pagination!
  /// Otherwise, it uses the zero-setup public embed endpoint (up to 100 tracks).
  Future<SpotifyImportResult> fetch(
    String input, {
    String? clientId,
    String? clientSecret,
    void Function(int fetched, int total)? onProgress,
  }) async {
    String resolvedInput = input.trim();

    // Check for shortened links like spotify.link/xxx
    if (resolvedInput.contains('spotify.link/')) {
      try {
        final client = http.Client();
        final req = http.Request('GET', Uri.parse(resolvedInput))
          ..followRedirects = true
          ..maxRedirects = 5;
        final res = await client.send(req);
        if (res.headers.containsKey('location')) {
          resolvedInput = res.headers['location']!;
        }
      } catch (e) {
        debugPrint('SpotifyService: failed to follow spotify.link redirect: $e');
      }
    }

    final target = parseTarget(resolvedInput);
    if (target == null) {
      throw Exception(
          'Invalid Spotify URL. Please paste a valid Spotify playlist, album, or track link.');
    }

    final hasCreds = clientId != null &&
        clientId.trim().isNotEmpty &&
        clientSecret != null &&
        clientSecret.trim().isNotEmpty;

    switch (target.type) {
      case SpotifyEntityType.playlist:
        if (hasCreds) {
          try {
            return await _fetchPlaylistViaApi(
              playlistId: target.id,
              clientId: clientId.trim(),
              clientSecret: clientSecret.trim(),
              sourceUrl: resolvedInput,
              onProgress: onProgress,
            );
          } catch (e) {
            debugPrint('SpotifyService: API fetch failed, falling back to embed: $e');
          }
        }
        return _fetchEntity(
          target.id,
          SpotifyEntityType.playlist,
          'https://open.spotify.com/embed/playlist/${target.id}',
          resolvedInput,
        );
      case SpotifyEntityType.album:
        return _fetchEntity(
          target.id,
          SpotifyEntityType.album,
          'https://open.spotify.com/embed/album/${target.id}',
          resolvedInput,
        );
      case SpotifyEntityType.track:
        return _fetchTrack(target.id, resolvedInput);
      case SpotifyEntityType.unknown:
        throw Exception('Unsupported Spotify content type.');
    }
  }

  /// Re-syncs an already imported Spotify playlist with the latest Spotify tracks.
  Future<LocalPlaylist> syncPlaylist(
    LocalPlaylist existing, {
    String? clientId,
    String? clientSecret,
    void Function(int fetched, int total)? onProgress,
  }) async {
    final spotifyId = existing.spotifyId;
    final spotifyUrl = existing.spotifyUrl;
    final query = spotifyId ?? spotifyUrl;

    if (query == null || query.isEmpty) {
      throw Exception('This playlist does not have a linked Spotify source.');
    }

    final imported = await fetch(
      spotifyId != null
          ? 'https://open.spotify.com/playlist/$spotifyId'
          : query,
      clientId: clientId,
      clientSecret: clientSecret,
      onProgress: onProgress,
    );

    // Keep any already resolved YouTube video IDs for matching tracks
    final existingVideoMap = <String, String>{};
    for (final t in existing.tracks) {
      if (t.youtubeVideoId != null) {
        final key = '${t.artist.toLowerCase()} - ${t.title.toLowerCase()}';
        existingVideoMap[key] = t.youtubeVideoId!;
      }
    }

    final mergedTracks = imported.tracks.map((newTrack) {
      final key = '${newTrack.artist.toLowerCase()} - ${newTrack.title.toLowerCase()}';
      if (existingVideoMap.containsKey(key)) {
        return newTrack.copyWith(youtubeVideoId: existingVideoMap[key]);
      }
      return newTrack;
    }).toList();

    return existing.copyWith(
      title: imported.title.isNotEmpty ? imported.title : existing.title,
      description: imported.description.isNotEmpty
          ? imported.description
          : existing.description,
      thumbnailUrl: imported.thumbnailUrl.isNotEmpty
          ? imported.thumbnailUrl
          : existing.thumbnailUrl,
      lastSyncedAt: DateTime.now(),
      tracks: mergedTracks,
    );
  }

  Future<SpotifyImportResult> _fetchEntity(
    String id,
    SpotifyEntityType type,
    String embedUrl,
    String sourceUrl,
  ) async {
    final response = await http.get(Uri.parse(embedUrl), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception(
        'Spotify returned status code ${response.statusCode}. '
        'Please ensure the playlist is Public and not Private.',
      );
    }

    final body = response.body;
    final nextDataRegex = RegExp(
        r'<script id="__NEXT_DATA__" type="application/json">([^<]+)</script>');
    final match = nextDataRegex.firstMatch(body);

    if (match == null) {
      throw Exception(
        'Unable to parse Spotify playlist content. '
        'The playlist may be restricted or unavailable.',
      );
    }

    final jsonStr = match.group(1)!;
    final Map<String, dynamic> data = jsonDecode(jsonStr);

    final entity = data['props']?['pageProps']?['state']?['data']?['entity']
        as Map<String, dynamic>?;

    if (entity == null) {
      throw Exception(
        'No Spotify playlist entity found. Please verify the link is accessible.',
      );
    }

    final title = (entity['name'] ?? entity['title'] ?? 'Spotify Playlist')
        .toString()
        .trim();
    final description = (entity['subtitle'] ?? '').toString().trim();

    String thumbnailUrl = '';
    final coverArt = entity['coverArt'] as Map<String, dynamic>?;
    if (coverArt != null && coverArt['sources'] is List) {
      final sources = coverArt['sources'] as List;
      if (sources.isNotEmpty && sources.first is Map) {
        thumbnailUrl = sources.first['url']?.toString() ?? '';
      }
    }

    if (thumbnailUrl.isEmpty) {
      final visual = entity['visualIdentity'] as Map<String, dynamic>?;
      if (visual != null && visual['image'] is List) {
        final images = visual['image'] as List;
        if (images.isNotEmpty && images.first is Map) {
          thumbnailUrl = images.first['url']?.toString() ?? '';
        }
      }
    }

    final rawTrackList = (entity['trackList'] as List<dynamic>?) ?? [];
    final tracks = <LocalPlaylistTrack>[];

    for (final raw in rawTrackList) {
      if (raw is! Map<String, dynamic>) continue;

      final trackTitle =
          (raw['title'] ?? raw['name'] ?? 'Unknown Title').toString().trim();

      // Artist extraction: try subtitle, or artists list
      String trackArtist = (raw['subtitle'] ?? '').toString().trim();
      if (trackArtist.isEmpty && raw['artists'] is List) {
        final artistsList = raw['artists'] as List;
        trackArtist = artistsList
            .map((a) => (a is Map ? a['name']?.toString() : null))
            .where((n) => n != null && n.isNotEmpty)
            .join(', ');
      }
      if (trackArtist.isEmpty) {
        trackArtist = 'Unknown Artist';
      }

      final durationMs = (raw['duration'] as num?)?.toInt() ?? 0;
      final uri = raw['uri']?.toString();

      tracks.add(
        LocalPlaylistTrack(
          title: trackTitle,
          artist: trackArtist,
          duration: Duration(milliseconds: durationMs),
          spotifyUri: uri,
          thumbnailUrl: thumbnailUrl,
        ),
      );
    }

    return SpotifyImportResult(
      id: id,
      type: type,
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
      tracks: tracks,
      sourceUrl: sourceUrl,
    );
  }

  Future<SpotifyImportResult> _fetchTrack(
    String id,
    String sourceUrl,
  ) async {
    final embedUrl = 'https://open.spotify.com/embed/track/$id';
    final response = await http.get(Uri.parse(embedUrl), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Could not fetch Spotify track (HTTP ${response.statusCode}).');
    }

    final nextDataRegex = RegExp(
        r'<script id="__NEXT_DATA__" type="application/json">([^<]+)</script>');
    final match = nextDataRegex.firstMatch(response.body);

    if (match == null) {
      throw Exception('Could not parse Spotify track.');
    }

    final Map<String, dynamic> data = jsonDecode(match.group(1)!);
    final entity = data['props']?['pageProps']?['state']?['data']?['entity']
        as Map<String, dynamic>?;

    if (entity == null) {
      throw Exception('Track entity not found.');
    }

    final title = (entity['title'] ?? entity['name'] ?? 'Unknown Title')
        .toString()
        .trim();

    String artist = '';
    if (entity['artists'] is List) {
      final artistsList = entity['artists'] as List;
      artist = artistsList
          .map((a) => (a is Map ? a['name']?.toString() : null))
          .where((n) => n != null && n.isNotEmpty)
          .join(', ');
    }
    if (artist.isEmpty) {
      artist = (entity['subtitle'] ?? 'Unknown Artist').toString().trim();
    }

    final durationMs = (entity['duration'] as num?)?.toInt() ?? 0;

    String thumbnailUrl = '';
    final visual = entity['visualIdentity'] as Map<String, dynamic>?;
    if (visual != null && visual['image'] is List) {
      final images = visual['image'] as List;
      if (images.isNotEmpty && images.first is Map) {
        thumbnailUrl = images.first['url']?.toString() ?? '';
      }
    }

    final track = LocalPlaylistTrack(
      title: title,
      artist: artist,
      duration: Duration(milliseconds: durationMs),
      spotifyUri: 'spotify:track:$id',
      thumbnailUrl: thumbnailUrl,
    );

    return SpotifyImportResult(
      id: id,
      type: SpotifyEntityType.track,
      title: title,
      description: artist,
      thumbnailUrl: thumbnailUrl,
      tracks: [track],
      sourceUrl: sourceUrl,
    );
  }

  /// Official Spotify Web API fetcher with pagination up to [maxTracks] (1,000+ tracks).
  Future<SpotifyImportResult> _fetchPlaylistViaApi({
    required String playlistId,
    required String clientId,
    required String clientSecret,
    required String sourceUrl,
    int maxTracks = 2500,
    void Function(int fetched, int total)? onProgress,
  }) async {
    // 1. Authenticate with Client Credentials
    final tokenUrl = Uri.parse('https://accounts.spotify.com/api/token');
    final authHeader = base64Encode(utf8.encode('$clientId:$clientSecret'));
    final tokenRes = await http.post(
      tokenUrl,
      headers: {
        'Authorization': 'Basic $authHeader',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'grant_type': 'client_credentials'},
    );

    if (tokenRes.statusCode != 200) {
      throw Exception(
        'Spotify authorization failed (HTTP ${tokenRes.statusCode}). Check Client ID & Secret.',
      );
    }

    final tokenData = jsonDecode(tokenRes.body) as Map<String, dynamic>;
    final accessToken = tokenData['access_token'] as String;

    // 2. Fetch Playlist Metadata
    final playlistUrl = Uri.parse(
      'https://api.spotify.com/v1/playlists/$playlistId?fields=name,description,images,tracks.total',
    );
    final pRes = await http.get(
      playlistUrl,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (pRes.statusCode != 200) {
      throw Exception(
        'Failed to fetch Spotify playlist (HTTP ${pRes.statusCode}). Ensure playlist is public.',
      );
    }

    final pData = jsonDecode(pRes.body) as Map<String, dynamic>;
    final title = (pData['name'] as String? ?? 'Spotify Playlist').trim();
    final description = (pData['description'] as String? ?? '').trim();
    final images = pData['images'] as List<dynamic>?;
    final thumbnailUrl = (images != null && images.isNotEmpty)
        ? (images.first['url'] as String? ?? '')
        : '';
    final totalTracks = (pData['tracks']?['total'] as num?)?.toInt() ?? 0;

    // 3. Paginate Tracks in batches of 100
    final tracks = <LocalPlaylistTrack>[];
    int offset = 0;
    const limit = 100;

    while (offset < totalTracks && tracks.length < maxTracks) {
      final pageUrl = Uri.parse(
        'https://api.spotify.com/v1/playlists/$playlistId/tracks?limit=$limit&offset=$offset&fields=items(track(name,duration_ms,uri,artists(name),album(images))),total',
      );
      final pageRes = await http.get(
        pageUrl,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (pageRes.statusCode != 200) break;

      final pageData = jsonDecode(pageRes.body) as Map<String, dynamic>;
      final items = pageData['items'] as List<dynamic>? ?? [];
      if (items.isEmpty) break;

      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final trackObj = item['track'] as Map<String, dynamic>?;
        if (trackObj == null) continue;

        final tTitle = (trackObj['name'] as String? ?? 'Unknown Title').trim();
        final artistsList = trackObj['artists'] as List<dynamic>?;
        final tArtist = artistsList
                ?.map((a) => (a is Map ? a['name'] as String? : null))
                .where((n) => n != null && n.isNotEmpty)
                .join(', ')
                .trim() ??
            '';
        final durMs = (trackObj['duration_ms'] as num?)?.toInt() ?? 0;
        final uri = trackObj['uri'] as String?;
        final tImages = trackObj['album']?['images'] as List<dynamic>?;
        final tThumb = (tImages != null && tImages.isNotEmpty)
            ? (tImages.first['url'] as String?)
            : thumbnailUrl;

        tracks.add(
          LocalPlaylistTrack(
            title: tTitle.isNotEmpty ? tTitle : 'Unknown Title',
            artist: tArtist.isNotEmpty ? tArtist : 'Unknown Artist',
            duration: Duration(milliseconds: durMs),
            spotifyUri: uri,
            thumbnailUrl: tThumb,
          ),
        );
      }

      offset += items.length;
      onProgress?.call(tracks.length, totalTracks);
      if (items.length < limit) break;
    }

    return SpotifyImportResult(
      id: playlistId,
      type: SpotifyEntityType.playlist,
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
      tracks: tracks,
      sourceUrl: sourceUrl,
    );
  }
}

