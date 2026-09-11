import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/youtube/v3.dart' as yt;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;

/// Represents a user's YouTube playlist (folder-level metadata).
class UserPlaylist {
  final String id;
  final String title;
  final String description;
  final String thumbnailUrl;
  final int videoCount;

  const UserPlaylist({
    required this.id,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.videoCount,
  });
}

/// Represents a single YouTube playlist item (video) for display.
class PlaylistVideo {
  final String videoId;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  final Duration duration;

  const PlaylistVideo({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.duration,
  });

  String get youtubeUrl => 'https://www.youtube.com/watch?v=$videoId';
}

/// Manages Google Sign-In and YouTube Data API v3 access.
class GoogleAuthService {
  // ---------------------------------------------------------------
  // TODO: Replace these with your own OAuth client IDs.
  //
  // For Android you need TWO client IDs:
  //   1. An "Android" client ID (from Google Cloud Console)
  //   2. A "Web" client ID (used as serverClientId for ID token verification)
  //
  // Steps:
  // 1. Go to https://console.cloud.google.com/
  // 2. Select your "FinAudio" project
  // 3. APIs & Services → Credentials
  // 4. Create OAuth client ID → type "Web" → name it "FinAudio Web"
  // 5. Copy that Web client ID and paste it below
  // ---------------------------------------------------------------
  static const String _serverClientId =
      '1023738817283-365rhlp8emot091uh6jctpdqo1gq29ek.apps.googleusercontent.com';

  static const List<String> _scopes = <String>[
    yt.YouTubeApi.youtubeReadonlyScope,
  ];

  bool _initialized = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  GoogleSignInAccount? _currentUser;
  String? _accessToken;

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  // ------------------------------------------------------------------
  // Initialization (required in v7)
  // ------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _googleSignIn.initialize(
        serverClientId: _serverClientId,
      );
      _initialized = true;
      debugPrint('GoogleSignIn initialized successfully');
    } catch (e) {
      debugPrint('GoogleSignIn.initialize failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // Sign-in / sign-out
  // ------------------------------------------------------------------

  /// Triggers the Google Sign-In flow. Returns the account on success.
  Future<GoogleSignInAccount?> signIn() async {
    await initialize();

    try {
      // v7 API: authenticate() returns the account directly.
      final GoogleSignInAccount account =
          await _googleSignIn.authenticate(scopeHint: _scopes);

      // Get the authorization with YouTube scopes.
      GoogleSignInClientAuthorization authorization;
      try {
        authorization = await _googleSignIn.authorizationClient
            .authorizeScopes(_scopes);
      } catch (_) {
        // If authorizeScopes fails, try authorizationForScopes.
        final existing = await _googleSignIn.authorizationClient
            .authorizationForScopes(_scopes);
        if (existing == null) {
          throw Exception(
            'Could not get authorization for YouTube scopes.',
          );
        }
        authorization = existing;
      }

      _accessToken = authorization.accessToken;
      _currentUser = account;

      debugPrint('Signed in as: ${account.email}');
      debugPrint('Access token obtained: ${_accessToken != null}');

      return account;
    } on GoogleSignInException catch (e) {
      debugPrint('Google Sign-In error: ${e.code.name} — ${e.description}');
      return null;
    } catch (e) {
      debugPrint('Unexpected Google Sign-In error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _accessToken = null;
  }

  // ------------------------------------------------------------------
  // YouTube Data API helpers
  // ------------------------------------------------------------------

  /// Creates an authenticated HTTP client for Google APIs.
  http.Client? _createAuthenticatedClient() {
    if (_accessToken == null) return null;

    return auth.authenticatedClient(
      http.Client(),
      auth.AccessCredentials(
        auth.AccessToken(
          'Bearer',
          _accessToken!,
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
        null, // refresh token — managed by GoogleSignIn internally
        _scopes,
      ),
    );
  }

  yt.YouTubeApi? get _youtubeApi {
    final client = _createAuthenticatedClient();
    if (client == null) return null;
    return yt.YouTubeApi(client);
  }

  // ------------------------------------------------------------------
  // Playlist browsing
  // ------------------------------------------------------------------

  /// Convenience: fetches the user's "Liked Videos" playlist.
  Future<List<PlaylistVideo>> fetchLikedVideos({int maxResults = 50}) async {
    final api = _youtubeApi;
    if (api == null) throw StateError('Not signed in.');

    try {
      final channelsResponse = await api.channels.list(
        ['contentDetails'],
        mine: true,
      );
      final channel = channelsResponse.items?.first;
      if (channel == null) throw Exception('No channel found.');

      final likedId = channel.contentDetails?.relatedPlaylists?.likes;
      if (likedId == null) throw Exception('Liked Videos playlist not found.');

      return await fetchPlaylistVideos(likedId, maxResults: maxResults);
    } catch (e) {
      debugPrint('fetchLikedVideos error: $e');
      rethrow;
    }
  }

  /// Fetches all playlists owned by the signed-in user, then filters
  /// to only those that contain music videos (category 10).
  ///
  /// For each non-empty playlist we sample up to 3 items, batch-check
  /// their video categories, and keep the playlist only if at least one
  /// music video is found.
  Future<List<UserPlaylist>> fetchPlaylists({int maxResults = 50}) async {
    final api = _youtubeApi;
    if (api == null) throw StateError('Not signed in.');

    final allPlaylists = <UserPlaylist>[];
    String? nextPageToken;

    try {
      // 1. Fetch all playlists.
      do {
        final response = await api.playlists.list(
          ['snippet', 'contentDetails'],
          mine: true,
          maxResults: maxResults.clamp(0, 50),
          pageToken: nextPageToken,
        );

        for (final item in response.items ?? []) {
          final snippet = item.snippet;
          if (snippet == null) continue;

          final thumbnails = snippet.thumbnails;
          final thumbUrl = thumbnails?.maxres ??
              thumbnails?.standard ??
              thumbnails?.high ??
              thumbnails?.medium ??
              thumbnails?.default_;

          final count = item.contentDetails?.itemCount ?? 0;
          if (count == 0) continue; // skip empty playlists

          allPlaylists.add(UserPlaylist(
            id: item.id ?? '',
            title: snippet.title ?? 'Untitled Playlist',
            description: snippet.description ?? '',
            thumbnailUrl: thumbUrl?.url ?? '',
            videoCount: count,
          ));
        }

        nextPageToken = response.nextPageToken;
      } while (nextPageToken != null);

      debugPrint('Fetched ${allPlaylists.length} total playlists, filtering…');

      // 2. For each playlist, sample a few items and check if it has music.
      final musicPlaylists = <UserPlaylist>[];

      for (final playlist in allPlaylists) {
        try {
          final sampleResponse = await api.playlistItems.list(
            ['snippet'],
            playlistId: playlist.id,
            maxResults: 3,
          );

          final sampleIds = (sampleResponse.items ?? [])
              .map((i) => i.snippet?.resourceId?.videoId)
              .where((id) => id != null && id.isNotEmpty)
              .cast<String>()
              .toList();

          if (sampleIds.isEmpty) continue;

          // Batch-check video categories.
          final videosResp = await api.videos.list(
            ['snippet'],
            id: sampleIds,
          );

          final hasMusic = (videosResp.items ?? []).any(
            (v) => v.snippet?.categoryId == '10',
          );

          if (hasMusic) {
            musicPlaylists.add(playlist);
          }
        } catch (_) {
          // If the check fails, include the playlist (fail open).
          musicPlaylists.add(playlist);
        }
      }

      debugPrint('Kept ${musicPlaylists.length} music playlists');
      return musicPlaylists;
    } catch (e) {
      debugPrint('fetchPlaylists error: $e');
      rethrow;
    }
  }

  /// Fetches videos from a playlist, filtering out non-music content.
  ///
  /// This works by first fetching playlist items, then batch-checking video
  /// categories via videos.list. Only Music (category 10) videos are kept.
  Future<List<PlaylistVideo>> fetchPlaylistVideos(
    String playlistId, {
    int maxResults = 50,
  }) async {
    final api = _youtubeApi;
    if (api == null) throw StateError('Not signed in.');

    try {
      final response = await api.playlistItems.list(
        ['snippet'],
        playlistId: playlistId,
        maxResults: maxResults,
      );

      // Collect all video IDs from the playlist items.
      final videoIds = <String>[];
      final itemsByVideoId = <String, dynamic>{};
      for (final item in response.items ?? []) {
        final snippet = item.snippet;
        if (snippet == null) continue;

        final videoId = snippet.resourceId?.videoId ?? '';
        if (videoId.isEmpty) continue;

        videoIds.add(videoId);
        itemsByVideoId[videoId] = item;
      }

      if (videoIds.isEmpty) return [];

      // Batch-fetch video details to get category IDs (max 50 per call).
      final musicVideoIds = <String>{};
      for (var i = 0; i < videoIds.length; i += 50) {
        final batch = videoIds.sublist(
          i,
          (i + 50 > videoIds.length) ? videoIds.length : i + 50,
        );
        try {
          final videosResp = await api.videos.list(
            ['snippet'],
            id: batch,
          );
          for (final v in videosResp.items ?? []) {
            if (v.snippet?.categoryId == '10') {
              musicVideoIds.add(v.id ?? '');
            }
          }
        } catch (_) {
          // If category check fails, include all videos (fail open).
          musicVideoIds.addAll(batch);
        }
      }

      // Build the final list, keeping only music videos.
      final videos = <PlaylistVideo>[];
      for (final videoId in videoIds) {
        if (!musicVideoIds.contains(videoId)) continue;

        final item = itemsByVideoId[videoId];
        final snippet = item?.snippet;
        if (snippet == null) continue;

        final thumbnails = snippet.thumbnails;
        final thumbUrl = thumbnails?.maxres ??
            thumbnails?.standard ??
            thumbnails?.high ??
            thumbnails?.medium ??
            thumbnails?.default_;

        videos.add(PlaylistVideo(
          videoId: videoId,
          title: snippet.title ?? 'Untitled',
          channelTitle: snippet.channelTitle ?? '',
          thumbnailUrl: thumbUrl?.url ?? '',
          duration: Duration.zero,
        ));
      }

      debugPrint('Fetched ${videos.length} music videos from playlist $playlistId');
      return videos;
    } catch (e) {
      debugPrint('fetchPlaylistVideos error: $e');
      rethrow;
    }
  }

  /// Searches YouTube for videos matching [query] and returns only Music
  /// results (category id 10).
  ///
  /// Results are limited to [maxResults]; this is capped to avoid quota
  /// spam. Use [debounceMs] when wiring from a search input.
  Future<List<PlaylistVideo>> searchMusic({
    required String query,
    int maxResults = 15,
  }) async {
    final api = _youtubeApi;
    if (api == null) throw StateError('Not signed in.');

    if (query.trim().isEmpty) return [];

    try {
      final response = await api.search.list(
        [
          'snippet',
          'id',
        ],
        q: query.trim(),
        type: ['video'],
        videoCategoryId: '10',
        maxResults: maxResults,
      );

      final videos = <PlaylistVideo>[];
      for (final item in response.items ?? []) {
        final id = item.id;
        if (id == null || id.videoId == null) continue;

        final snippet = item.snippet;
        if (snippet == null) continue;

        final thumbnails = snippet.thumbnails;
        final thumbUrl = thumbnails?.maxres ??
            thumbnails?.standard ??
            thumbnails?.high ??
            thumbnails?.medium ??
            thumbnails?.default_;

        videos.add(PlaylistVideo(
          videoId: id.videoId!,
          title: snippet.title ?? 'Untitled',
          channelTitle: snippet.channelTitle ?? '',
          thumbnailUrl: thumbUrl?.url ?? '',
          duration: Duration.zero,
        ));
      }

      debugPrint('Search returned ${videos.length} music results for "$query"');
      return videos;
    } catch (e) {
      debugPrint('searchMusic error: $e');
      rethrow;
    }
  }
}
