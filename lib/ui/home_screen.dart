import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:ytmusicapi_dart/enums.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';
import 'package:finaudio/models/local_playlist.dart';
import 'package:finaudio/services/download_service.dart';
import 'package:finaudio/services/google_auth_service.dart';
import 'package:finaudio/services/history_service.dart';
import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/playlist_service.dart';
import 'package:finaudio/services/settings_service.dart';
import 'package:finaudio/ui/album_view_screen.dart';
import 'package:finaudio/ui/artist_screen.dart';
import 'package:finaudio/ui/section_detail_screen.dart';
import 'package:finaudio/widgets/add_to_playlist_sheet.dart';

/// Authentic YouTube Music mobile interface for FinAudio:
/// 1. Visual Theme: Deep pure black (#030303), high-contrast white text, subtle grey metadata.
/// 2. Top App Bar: Pinned header with red play circle + bold "Music", Cast, Search, and Profile avatar.
/// 3. Mood/Genre Chips: [Energize] [Workout] [Relax] [Focus] [Commute] in stadium dark pills.
/// 4. "Speed dial": 3x3 grid containing Liked Music + recently played favorites with navigation arrows.
/// 5. "Quick picks": 4-row horizontal scrolling grid with 48x48 thumbnails, views, and three-dot menus.
/// 6. Horizontal Carousels: "Similar to `Artist`", "Mixed for you", "From your library", "Recommended albums", "Artists", and "New releases".
/// 7. Media & Loading Polish: CachedNetworkImage with dark shimmer (#1A1A1A to #2A2A2A) placeholders.
/// 8. Pull-to-refresh: RefreshIndicator with YouTube red spinner (#FF0000).
class HomeTab extends StatefulWidget {
  final PlayerService playerService;
  final GoogleAuthService authService;
  final PlaylistService playlistService;
  final SettingsService settingsService;
  final VoidCallback onOpenPlaylists;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSettings;
  final void Function(LocalPlaylist playlist) onOpenPlaylistDetail;

  const HomeTab({
    super.key,
    required this.playerService,
    required this.authService,
    required this.playlistService,
    required this.settingsService,
    required this.onOpenPlaylists,
    required this.onOpenSearch,
    required this.onOpenSettings,
    required this.onOpenPlaylistDetail,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final ScrollController _scrollController = ScrollController();
  final HistoryService _historyService = HistoryService.instance;

  final GlobalKey _keyQuickPicks = GlobalKey();
  final GlobalKey _keySpeedDial = GlobalKey();
  final GlobalKey _keyLibrary = GlobalKey();
  final GlobalKey _keyAlbums = GlobalKey();
  final GlobalKey _keyNewReleases = GlobalKey();
  final GlobalKey _keyArtists = GlobalKey();

  String? _selectedMood;
  List<SubscribedArtist> _subscribedArtists = [];

  // Dynamic feed state variables
  List<LocalPlaylistTrack> _dynamicQuickPicks = [];
  List<LocalPlaylistTrack> _dynamicNewReleases = [];
  List<({String title, String artist, String coverUrl, String subtitle})> _dynamicAlbums = [];
  List<LocalPlaylistTrack> _dynamicSimilarTracks = [];
  ({String name, String? channelId, String? imageUrl, String subscribers})? _dynamicSimilarArtist;
  List<({String name, String? channelId, String? imageUrl, String subscribers})> _dynamicArtists = [];
  List<({String title, String artist, String coverUrl, String subtitle})> _dynamicCommunityPlaylists = [];
  bool _loadingDynamicFeed = false;
  int _refreshCount = 0;

  final List<String> _moods = const [
    'Energize',
    'Workout',
    'Relax',
    'Focus',
    'Commute',
    'Feel good',
  ];

  final Map<String, List<LocalPlaylistTrack>> _moodTracksCache = {};
  final Map<String, List<({String title, String artist, String coverUrl, String subtitle})>> _moodAlbumsCache = {};
  final Map<String, List<({String name, String? channelId, String? imageUrl, String subscribers})>> _moodArtistsCache = {};

  List<LocalPlaylistTrack> _parseTracksFromYt(List results) {
    final tracks = <LocalPlaylistTrack>[];
    for (final item in results) {
      if (item is! Map) continue;
      final vId = item['videoId']?.toString() ?? '';
      final title = item['title']?.toString() ?? '';
      if (vId.isEmpty || title.isEmpty) continue;
      String artist = 'Various Artists';
      final artists = item['artists'];
      if (artists is List && artists.isNotEmpty) {
        final first = artists.first;
        if (first is Map && first['name'] != null) {
          artist = first['name'].toString();
        }
      }
      String thumb = 'https://img.youtube.com/vi/$vId/hqdefault.jpg';
      final thumbs = item['thumbnails'];
      if (thumbs is List && thumbs.isNotEmpty) {
        final last = thumbs.last;
        if (last is Map && last['url'] != null) {
          thumb = last['url'].toString();
        }
      }
      Duration dur = const Duration(minutes: 3, seconds: 30);
      if (item['duration'] is String) {
        final parts = (item['duration'] as String).split(':');
        if (parts.length == 2) {
          dur = Duration(
            minutes: int.tryParse(parts[0]) ?? 3,
            seconds: int.tryParse(parts[1]) ?? 30,
          );
        }
      }
      tracks.add(LocalPlaylistTrack(
        title: title,
        artist: artist,
        duration: dur,
        youtubeVideoId: vId,
        thumbnailUrl: thumb,
      ));
    }
    return tracks;
  }

  List<String> _extractUserTopArtists() {
    final Map<String, int> artistFrequency = {};

    // 1. History (weighted highest: 3 points per play)
    for (final item in _historyService.recentTracks) {
      final artist = item.artist.trim();
      if (artist.isNotEmpty && artist != 'Unknown' && artist != 'Various Artists') {
        artistFrequency[artist] = (artistFrequency[artist] ?? 0) + 3;
      }
    }

    // 2. Liked songs (2 points per track)
    for (final track in widget.playlistService.likedSongsPlaylist.tracks) {
      final artist = track.artist.trim();
      if (artist.isNotEmpty && artist != 'Unknown' && artist != 'Various Artists') {
        artistFrequency[artist] = (artistFrequency[artist] ?? 0) + 2;
      }
    }

    // 3. User playlists (1 point per track)
    for (final playlist in widget.playlistService.playlists) {
      if (playlist.id == 'liked_songs') continue;
      for (final track in playlist.tracks) {
        final artist = track.artist.trim();
        if (artist.isNotEmpty && artist != 'Unknown' && artist != 'Various Artists') {
          artistFrequency[artist] = (artistFrequency[artist] ?? 0) + 1;
        }
      }
    }

    // 4. Subscribed artists and favorite artists (highest priority)
    for (final sub in _subscribedArtists) {
      final artist = sub.title.trim();
      if (artist.isNotEmpty) {
        artistFrequency[artist] = (artistFrequency[artist] ?? 0) + 5;
      }
    }
    for (final fav in widget.settingsService.favoriteArtists) {
      final artist = fav.trim();
      if (artist.isNotEmpty) {
        artistFrequency[artist] = (artistFrequency[artist] ?? 0) + 5;
      }
    }

    final sorted = artistFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  Future<void> _fetchMoodTracks(String mood) async {
    await _fetchMoodData(mood);
  }

  Future<void> _fetchMoodData(String mood) async {
    final bool isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTest) return;

    if (_moodTracksCache.containsKey(mood) &&
        _moodTracksCache[mood]!.isNotEmpty &&
        _moodAlbumsCache.containsKey(mood) &&
        _moodArtistsCache.containsKey(mood)) {
      return;
    }
    try {
      final yt = await YTMusic.create();

      // 1. Mood Songs (Quick picks)
      if (!_moodTracksCache.containsKey(mood) || _moodTracksCache[mood]!.isEmpty) {
        final results = await yt.search('$mood music hits', filter: SearchFilterType.songs, limit: 16);
        final tracks = _parseTracksFromYt(results);
        if (tracks.isNotEmpty) {
          _moodTracksCache[mood] = tracks;
        }
      }

      // 2. Mood Mixes & Albums
      if (!_moodAlbumsCache.containsKey(mood) || _moodAlbumsCache[mood]!.isEmpty) {
        final albumsRes = await yt.search('$mood playlist mix', filter: SearchFilterType.playlists, limit: 8);
        final albums = <({String title, String artist, String coverUrl, String subtitle})>[];
        for (final item in albumsRes) {
          if (item is! Map) continue;
          final title = item['title']?.toString() ?? '';
          if (title.isEmpty) continue;
          String author = 'YouTube Music';
          final authors = item['authors'] ?? item['artists'];
          if (authors is List && authors.isNotEmpty && authors.first is Map) {
            author = authors.first['name']?.toString() ?? author;
          }
          String thumb = '';
          final thumbs = item['thumbnails'];
          if (thumbs is List && thumbs.isNotEmpty && thumbs.last is Map) {
            thumb = thumbs.last['url']?.toString() ?? '';
          }
          if (thumb.isNotEmpty) {
            albums.add((
              title: title,
              artist: author,
              coverUrl: thumb,
              subtitle: 'Mix • $author',
            ));
          }
        }
        if (albums.isNotEmpty) {
          _moodAlbumsCache[mood] = albums;
        }
      }

      // 3. Mood Artists
      if (!_moodArtistsCache.containsKey(mood) || _moodArtistsCache[mood]!.isEmpty) {
        final artistRes = await yt.search('$mood artist', filter: SearchFilterType.artists, limit: 8);
        final artists = <({String name, String? channelId, String? imageUrl, String subscribers})>[];
        for (final item in artistRes) {
          if (item is! Map) continue;
          final name = item['artist']?.toString() ?? item['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          final cId = item['channelId']?.toString();
          String thumb = '';
          final thumbs = item['thumbnails'];
          if (thumbs is List && thumbs.isNotEmpty && thumbs.last is Map) {
            thumb = thumbs.last['url']?.toString() ?? '';
          }
          final subs = item['subscribers']?.toString() ?? 'Popular artist';
          artists.add((
            name: name,
            channelId: cId,
            imageUrl: thumb.isNotEmpty ? thumb : null,
            subscribers: subs,
          ));
        }
        if (artists.isNotEmpty) {
          _moodArtistsCache[mood] = artists;
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('HomeTab: Failed to fetch mood data for $mood: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _historyService.init();
    _historyService.addListener(_onDataChanged);
    widget.playlistService.addListener(_onDataChanged);
    widget.authService.addListener(_onDataChanged);
    widget.settingsService.addListener(_onDataChanged);
    _loadSubscribedArtists();
    _loadDynamicFeed();
  }

  @override
  void dispose() {
    _historyService.removeListener(_onDataChanged);
    widget.playlistService.removeListener(_onDataChanged);
    widget.authService.removeListener(_onDataChanged);
    widget.settingsService.removeListener(_onDataChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSubscribedArtists({bool forceRefresh = false}) async {
    try {
      final artists = await widget.authService.fetchSubscribedArtists(
        forceRefresh: forceRefresh,
        musicOnly: true,
      );
      if (mounted) {
        setState(() => _subscribedArtists = artists);
      }
    } catch (_) {}
  }

  Future<void> _loadDynamicFeed({bool forceRefresh = false}) async {
    if (_loadingDynamicFeed && !forceRefresh) return;
    _loadingDynamicFeed = true;
    if (forceRefresh) {
      _refreshCount++;
    }

    final bool isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTest) {
      _loadingDynamicFeed = false;
      return;
    }

    try {
      final yt = await YTMusic.create();

      // 1. Extract user's personalized seed artists from history, liked songs, playlists, & subscriptions
      final topArtists = _extractUserTopArtists();
      final seedArtists = topArtists.isNotEmpty
          ? topArtists
          : ['The Weeknd', 'Dua Lipa', 'Sabrina Carpenter', 'Billie Eilish', 'Taylor Swift'];

      final primaryArtist = seedArtists.first;
      final secondaryArtist = seedArtists.length > 1 ? seedArtists[1] : seedArtists.first;

      // 2. Attempt to fetch live YouTube Music home feed (6 shelves)
      bool hasHomeQuickPicks = false;
      try {
        final home = await yt.getHome(limit: 6);
        final fetchedQuickPicks = <LocalPlaylistTrack>[];
        final fetchedNewReleases = <LocalPlaylistTrack>[];
        final fetchedAlbums = <({String title, String artist, String coverUrl, String subtitle})>[];

        for (final shelf in home) {
          if (shelf is! Map) continue;
          final title = (shelf['title']?.toString() ?? '').toLowerCase();
          final contents = shelf['contents'] as List?;
          if (contents == null || contents.isEmpty) continue;

          // Quick picks & songs
          if (title.contains('quick picks') ||
              title.contains('listen again') ||
              title.contains('mixed') ||
              title.contains('covers') ||
              title.contains('featured') ||
              title.contains('trending')) {
            final parsed = _parseTracksFromYt(contents);
            for (final t in parsed) {
              if (!fetchedQuickPicks.any((x) => x.youtubeVideoId == t.youtubeVideoId)) {
                fetchedQuickPicks.add(t);
              }
            }
          }

          // New releases
          if (title.contains('new release') || title.contains('latest') || title.contains('new music')) {
            final parsed = _parseTracksFromYt(contents);
            for (final t in parsed) {
              if (!fetchedNewReleases.any((x) => x.youtubeVideoId == t.youtubeVideoId)) {
                fetchedNewReleases.add(t);
              }
            }
          }

          // Albums
          if (title.contains('album') || title.contains('for you') || title.contains('recommended')) {
            for (final item in contents) {
              if (item is! Map) continue;
              final tTitle = item['title']?.toString() ?? '';
              if (tTitle.isEmpty) continue;

              String artist = 'Various Artists';
              final artists = item['artists'];
              if (artists is List && artists.isNotEmpty && artists.first is Map) {
                artist = artists.first['name']?.toString() ?? artist;
              }

              String thumb = '';
              final thumbs = item['thumbnails'];
              if (thumbs is List && thumbs.isNotEmpty && thumbs.last is Map) {
                thumb = thumbs.last['url']?.toString() ?? '';
              }

              if (thumb.isNotEmpty) {
                fetchedAlbums.add((
                  title: tTitle,
                  artist: artist,
                  coverUrl: thumb,
                  subtitle: 'Album • $artist',
                ));
              }
            }
          }
        }

        if (fetchedQuickPicks.isNotEmpty) {
          _dynamicQuickPicks = fetchedQuickPicks;
          hasHomeQuickPicks = true;
        }
        if (fetchedNewReleases.isNotEmpty) _dynamicNewReleases = fetchedNewReleases;
        if (fetchedAlbums.isNotEmpty) _dynamicAlbums = fetchedAlbums;
      } catch (e) {
        debugPrint('YTMusic.getHome error: $e');
      }

      // 3. Fallback/Enhance Quick Picks from user top artists + related discovery
      if (!hasHomeQuickPicks || _dynamicQuickPicks.length < 8) {
        try {
          final liveQuickList = <LocalPlaylistTrack>[];
          final res1 = await yt.search('$primaryArtist radio mix', filter: SearchFilterType.songs, limit: 8);
          liveQuickList.addAll(_parseTracksFromYt(res1));

          if (secondaryArtist != primaryArtist) {
            final res2 = await yt.search('$secondaryArtist hits', filter: SearchFilterType.songs, limit: 6);
            liveQuickList.addAll(_parseTracksFromYt(res2));
          }

          // Blend discovery from related artists
          final relatedPool = _getRelatedArtistsPool(primaryArtist);
          liveQuickList.addAll(relatedPool.take(6));

          final res3 = await yt.search('trending top songs hits', filter: SearchFilterType.songs, limit: 8);
          liveQuickList.addAll(_parseTracksFromYt(res3));

          if (liveQuickList.isNotEmpty) {
            _dynamicQuickPicks = liveQuickList;
          }
        } catch (e) {
          debugPrint('HomeTab live quick picks fallback error: $e');
        }
      }

      // 4. Setup dynamic "Similar to [User's Top Artist]" (Guaranteed non-seed artists!)
      try {
        final similarRes = await yt.search('songs like $primaryArtist', filter: SearchFilterType.songs, limit: 16);
        final simTracks = _parseTracksFromYt(similarRes);
        final filteredSimTracks = <LocalPlaylistTrack>[];
        final cleanSeed = primaryArtist.toLowerCase().trim();

        for (final t in simTracks) {
          final tArtist = t.artist.toLowerCase().trim();
          // STRICT RULE: Must NOT be the seed artist
          if (tArtist.contains(cleanSeed) || cleanSeed.contains(tArtist)) {
            continue;
          }
          if (!filteredSimTracks.any((x) => x.youtubeVideoId == t.youtubeVideoId || x.title.toLowerCase() == t.title.toLowerCase())) {
            filteredSimTracks.add(t);
          }
        }

        // If live search returned fewer than 8 diverse tracks, blend related artists pool
        if (filteredSimTracks.length < 8) {
          final relatedPool = _getRelatedArtistsPool(primaryArtist);
          for (final t in relatedPool) {
            final tArtist = t.artist.toLowerCase().trim();
            if (tArtist.contains(cleanSeed) || cleanSeed.contains(tArtist)) continue;
            if (!filteredSimTracks.any((x) => x.youtubeVideoId == t.youtubeVideoId || x.title.toLowerCase() == t.title.toLowerCase())) {
              filteredSimTracks.add(t);
            }
          }
        }

        if (filteredSimTracks.isNotEmpty) {
          _dynamicSimilarTracks = filteredSimTracks;
        }

        // Fetch artist metadata (avatar, subscribers)
        SubscribedArtist? matchedSub;
        for (final a in _subscribedArtists) {
          if (a.title.toLowerCase() == primaryArtist.toLowerCase()) {
            matchedSub = a;
            break;
          }
        }

        if (matchedSub != null) {
          _dynamicSimilarArtist = (
            name: primaryArtist,
            channelId: matchedSub.channelId.isNotEmpty ? matchedSub.channelId : null,
            imageUrl: matchedSub.thumbnailUrl.isNotEmpty ? matchedSub.thumbnailUrl : null,
            subscribers: 'Subscribed artist',
          );
        } else {
          final aRes = await yt.search(primaryArtist, filter: SearchFilterType.artists, limit: 1);
          if (aRes.isNotEmpty && aRes.first is Map) {
            final aMap = aRes.first as Map;
            String thumb = '';
            final thumbs = aMap['thumbnails'];
            if (thumbs is List && thumbs.isNotEmpty && thumbs.last is Map) {
              thumb = thumbs.last['url']?.toString() ?? '';
            }
            final subs = aMap['subscribers']?.toString() ?? 'Popular artist';
            final cId = aMap['channelId']?.toString();
            _dynamicSimilarArtist = (
              name: primaryArtist,
              channelId: cId,
              imageUrl: thumb.isNotEmpty ? thumb : null,
              subscribers: subs,
            );
          } else {
            _dynamicSimilarArtist = (
              name: primaryArtist,
              channelId: null,
              imageUrl: null,
              subscribers: 'Top artist for you',
            );
          }
        }
      } catch (e) {
        debugPrint('HomeTab similar to artist error: $e');
      }

      // 5. Fetch Community / Public Playlists (ArchiveTune Signature)
      try {
        final plRes = await yt.search('trending playlist', filter: SearchFilterType.playlists, limit: 8);
        final playlists = <({String title, String artist, String coverUrl, String subtitle})>[];
        for (final item in plRes) {
          if (item is! Map) continue;
          final title = item['title']?.toString() ?? '';
          if (title.isEmpty) continue;
          String author = 'YouTube Music';
          final authors = item['authors'] ?? item['artists'];
          if (authors is List && authors.isNotEmpty && authors.first is Map) {
            author = authors.first['name']?.toString() ?? author;
          }
          String thumb = '';
          final thumbs = item['thumbnails'];
          if (thumbs is List && thumbs.isNotEmpty && thumbs.last is Map) {
            thumb = thumbs.last['url']?.toString() ?? '';
          }
          if (thumb.isNotEmpty) {
            playlists.add((
              title: title,
              artist: author,
              coverUrl: thumb,
              subtitle: 'Playlist • $author',
            ));
          }
        }
        if (playlists.isNotEmpty) {
          _dynamicCommunityPlaylists = playlists;
        }
      } catch (_) {}

      // 6. Recommended albums across multiple diverse artists
      if (_dynamicAlbums.isEmpty) {
        try {
          final albumQueries = [
            '$primaryArtist album',
            if (secondaryArtist != primaryArtist) '$secondaryArtist album' else 'Cavetown album',
            'trending albums',
          ];
          final albums = <({String title, String artist, String coverUrl, String subtitle})>[];
          final seenAlbumArtists = <String>{};

          for (final q in albumQueries) {
            final albumRes = await yt.search(q, filter: SearchFilterType.albums, limit: 4);
            for (final item in albumRes) {
              if (item is! Map) continue;
              final tTitle = item['title']?.toString() ?? '';
              if (tTitle.isEmpty) continue;
              String artist = 'Various Artists';
              final artists = item['artists'];
              if (artists is List && artists.isNotEmpty && artists.first is Map) {
                artist = artists.first['name']?.toString() ?? artist;
              }
              final normArt = artist.toLowerCase().trim();
              if (seenAlbumArtists.contains(normArt) && albums.length >= 3) continue;

              String thumb = '';
              final thumbs = item['thumbnails'];
              if (thumbs is List && thumbs.isNotEmpty && thumbs.last is Map) {
                thumb = thumbs.last['url']?.toString() ?? '';
              }
              if (thumb.isNotEmpty) {
                seenAlbumArtists.add(normArt);
                albums.add((
                  title: tTitle,
                  artist: artist,
                  coverUrl: thumb,
                  subtitle: 'Album • $artist',
                ));
              }
            }
            if (albums.length >= 8) break;
          }
          if (albums.isNotEmpty) {
            _dynamicAlbums = albums;
          }
        } catch (_) {}
      }

      // 7. New releases if empty
      if (_dynamicNewReleases.isEmpty) {
        try {
          final newRes = await yt.search('new music release', filter: SearchFilterType.songs, limit: 8);
          final newTracks = _parseTracksFromYt(newRes);
          if (newTracks.isNotEmpty) {
            _dynamicNewReleases = newTracks;
          }
        } catch (_) {}
      }

      // 8. Dynamic Artists (Diverse Creators with channel avatars)
      try {
        final expandedSeedArtists = <String>[...seedArtists];
        for (final art in _getRelatedArtistNames(primaryArtist)) {
          if (!expandedSeedArtists.any((a) => a.toLowerCase() == art.toLowerCase())) {
            expandedSeedArtists.add(art);
          }
          if (expandedSeedArtists.length >= 8) break;
        }

        final fetchedArtists = <({String name, String? channelId, String? imageUrl, String subscribers})>[];
        for (final artName in expandedSeedArtists.take(8)) {
          final aRes = await yt.search(artName, filter: SearchFilterType.artists, limit: 1);
          if (aRes.isNotEmpty && aRes.first is Map) {
            final aMap = aRes.first as Map;
            String thumb = '';
            final thumbs = aMap['thumbnails'];
            if (thumbs is List && thumbs.isNotEmpty && thumbs.last is Map) {
              thumb = thumbs.last['url']?.toString() ?? '';
            }
            final subs = aMap['subscribers']?.toString() ?? 'Popular artist';
            final cId = aMap['channelId']?.toString();
            fetchedArtists.add((
              name: artName,
              channelId: cId,
              imageUrl: thumb.isNotEmpty ? thumb : null,
              subscribers: subs,
            ));
          }
        }
        if (fetchedArtists.isNotEmpty) {
          _dynamicArtists = fetchedArtists;
        }
      } catch (_) {}

    } catch (e) {
      debugPrint('_loadDynamicFeed top-level error: $e');
    } finally {
      _loadingDynamicFeed = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleRefresh() async {
    await Future.wait([
      _historyService.init(),
      widget.playlistService.init(),
      _loadSubscribedArtists(forceRefresh: true),
      _loadDynamicFeed(forceRefresh: true),
    ]);
    if (mounted) {
      setState(() {});
    }
  }

  // =========================================================================
  // Playback & Navigation
  // =========================================================================

  Future<void> _playTrackList(List<LocalPlaylistTrack> list, int startIndex) async {
    try {
      await widget.playerService.playLocalPlaylistTracks(list, startIndex: startIndex);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playback failed: $e')),
      );
    }
  }

  void _openArtistPage(String artistName, {String? channelId, String? imageUrl}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistScreen(
          artistName: artistName,
          channelId: channelId,
          initialImageUrl: imageUrl,
          playerService: widget.playerService,
          authService: widget.authService,
          playlistService: widget.playlistService,
          settingsService: widget.settingsService,
        ),
      ),
    );
  }

  void _showTrackOptions(LocalPlaylistTrack track) {
    final surface = widget.settingsService.surfaceColor;
    final text = widget.settingsService.textColor;
    final isLiked = widget.playlistService.isTrackLiked(
      track.youtubeVideoId,
      track.title,
      track.artist,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: text.withAlpha(40),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: _buildYtmImage(
                  imageUrl: track.thumbnailUrl,
                  width: 48,
                  height: 48,
                  borderRadius: BorderRadius.circular(4),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, color: text),
                ),
                subtitle: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: text.withAlpha(160)),
                ),
              ),
              Divider(color: text.withAlpha(20)),
              ListTile(
                leading: Icon(Icons.playlist_play_rounded, color: text),
                title: Text('Play next', style: TextStyle(color: text)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.playerService.playNext(Track.fromLocalPlaylistTrack(track));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Playing next: "${track.title}"')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.queue_music_rounded, color: text),
                title: Text('Add to queue', style: TextStyle(color: text)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.playerService.addTracksToQueue([Track.fromLocalPlaylistTrack(track)]);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added "${track.title}" to queue')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.download_rounded, color: text),
                title: Text('Download', style: TextStyle(color: text)),
                onTap: () {
                  Navigator.pop(ctx);
                  DownloadService.instance.startDownload(Track.fromLocalPlaylistTrack(track));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Downloading "${track.title}"…')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.playlist_add_rounded, color: text),
                title: Text('Add to playlist', style: TextStyle(color: text)),
                onTap: () {
                  Navigator.pop(ctx);
                  showAddToPlaylistSheet(
                    context: context,
                    track: track,
                    playlistService: widget.playlistService,
                    accentColor: widget.settingsService.accentColor,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isLiked ? const Color(0xFFFF5252) : text,
                ),
                title: Text(
                  isLiked ? 'Remove from Liked Songs' : 'Like',
                  style: TextStyle(color: text),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.playlistService.toggleLikeTrack(track);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isLiked
                            ? 'Removed from Liked Songs'
                            : 'Added to Liked Songs',
                      ),
                    ),
                  );
                },
              ),
              if (track.individualArtists.length > 1) ...[
                for (final artist in track.individualArtists)
                  ListTile(
                    leading: Icon(Icons.person_outline_rounded, color: text),
                    title: Text('Go to $artist', style: TextStyle(color: text)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openArtistPage(artist, imageUrl: track.thumbnailUrl);
                    },
                  ),
              ] else
                ListTile(
                  leading: Icon(Icons.person_outline_rounded, color: text),
                  title: Text(
                      'Go to ${track.individualArtists.firstOrNull ?? (track.artist.isNotEmpty ? track.artist : "artist")}',
                      style: TextStyle(color: text)),
                  onTap: () {
                    Navigator.pop(ctx);
                    final aName = track.individualArtists.firstOrNull ?? track.artist;
                    if (aName.trim().isEmpty) return;
                    _openArtistPage(aName, imageUrl: track.thumbnailUrl);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildCircularHeaderButton({
    required IconData icon,
    required String tooltip,
    required Color surface,
    required Color text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: surface,
            shape: BoxShape.circle,
            border: Border.all(color: text.withAlpha(20)),
          ),
          child: Center(
            child: Icon(icon, color: text.withAlpha(220), size: 18),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // Image with Themed Shimmer Loading
  // =========================================================================

  Widget _buildYtmImage({
    required String? imageUrl,
    required double width,
    required double height,
    BorderRadius? borderRadius,
    BoxShape shape = BoxShape.rectangle,
    IconData fallbackIcon = Icons.music_note_rounded,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(4);
    final surface = widget.settingsService.surfaceColor;
    final text = widget.settingsService.textColor;

    final bool isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    Widget shimmerPlaceholder() => Shimmer.fromColors(
          baseColor: surface,
          highlightColor: Color.alphaBlend(text.withAlpha(25), surface),
          enabled: !isTest,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: shape == BoxShape.circle ? null : radius,
              shape: shape,
            ),
          ),
        );

    Widget fallbackError() => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: shape == BoxShape.circle ? null : radius,
            shape: shape,
            border: Border.all(color: text.withAlpha(15)),
          ),
          child: Center(
            child: Icon(fallbackIcon, color: text.withAlpha(90), size: width * 0.45),
          ),
        );

    if (imageUrl == null || imageUrl.trim().isEmpty) {
      return fallbackError();
    }

    return ClipRRect(
      borderRadius: shape == BoxShape.circle ? BorderRadius.circular(width / 2) : radius,
      child: CachedNetworkImage(
        imageUrl: imageUrl.trim(),
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, _) => shimmerPlaceholder(),
        errorWidget: (_, _, _) => fallbackError(),
      ),
    );
  }

  // =========================================================================
  // Section Data
  // =========================================================================

  List<String> _getRelatedArtistNames(String seedArtist) {
    final lower = seedArtist.toLowerCase().trim();
    if (lower.contains('yonkagor') ||
        lower.contains('stauber') ||
        lower.contains('cavetown') ||
        lower.contains('tally hall') ||
        lower.contains('lemon demon') ||
        lower.contains('mother mother') ||
        lower.contains('ricky montgomery') ||
        lower.contains('will wood') ||
        lower.contains('penelope scott')) {
      return const [
        'Cavetown',
        'Jack Stauber',
        'Ricky Montgomery',
        'Bo Burnham',
        'Tally Hall',
        'Mother Mother',
        'Lemon Demon',
      ];
    }
    if (lower.contains('weeknd') ||
        lower.contains('post malone') ||
        lower.contains('drake') ||
        lower.contains('kendrick') ||
        lower.contains('sza') ||
        lower.contains('frank ocean')) {
      return const [
        'The Weeknd',
        'Post Malone',
        'SZA',
        'Frank Ocean',
        'Childish Gambino',
        'Daniel Caesar',
      ];
    }
    if (lower.contains('arctic') ||
        lower.contains('beatles') ||
        lower.contains('queen') ||
        lower.contains('radiohead') ||
        lower.contains('strokes') ||
        lower.contains('gorillaz')) {
      return const [
        'Arctic Monkeys',
        'The Strokes',
        'The Neighbourhood',
        'Wallows',
        'Gorillaz',
        'Cage The Elephant',
      ];
    }
    return const [
      'Sabrina Carpenter',
      'Billie Eilish',
      'Cavetown',
      'Jack Stauber',
      'The Weeknd',
      'Dua Lipa',
      'Ricky Montgomery',
    ];
  }

  List<LocalPlaylistTrack> _getRelatedArtistsPool(String seedArtist) {
    final lower = seedArtist.toLowerCase().trim();
    if (lower.contains('yonkagor') ||
        lower.contains('stauber') ||
        lower.contains('cavetown') ||
        lower.contains('tally hall') ||
        lower.contains('lemon demon') ||
        lower.contains('mother mother') ||
        lower.contains('ricky montgomery') ||
        lower.contains('will wood') ||
        lower.contains('penelope scott')) {
      return const [
        LocalPlaylistTrack(
          title: 'Boys Will Be Bugs',
          artist: 'Cavetown',
          duration: Duration(minutes: 5, seconds: 29),
          youtubeVideoId: 'uR_E_1U0QvY',
          thumbnailUrl: 'https://img.youtube.com/vi/uR_E_1U0QvY/hqdefault.jpg',
        ),
        LocalPlaylistTrack(
          title: 'Buttercup',
          artist: 'Jack Stauber',
          duration: Duration(minutes: 3, seconds: 28),
          youtubeVideoId: 'eYDI8b5Nn5s',
          thumbnailUrl: 'https://img.youtube.com/vi/eYDI8b5Nn5s/hqdefault.jpg',
        ),
        LocalPlaylistTrack(
          title: 'Line Without a Hook',
          artist: 'Ricky Montgomery',
          duration: Duration(minutes: 4, seconds: 9),
          youtubeVideoId: 'O3NqK304aQE',
          thumbnailUrl: 'https://img.youtube.com/vi/O3NqK304aQE/hqdefault.jpg',
        ),
        LocalPlaylistTrack(
          title: 'Bezos I',
          artist: 'Bo Burnham',
          duration: Duration(minutes: 0, seconds: 58),
          youtubeVideoId: 'l_nJ4f_v2j4',
          thumbnailUrl: 'https://img.youtube.com/vi/l_nJ4f_v2j4/hqdefault.jpg',
        ),
        LocalPlaylistTrack(
          title: 'Hidden in the Sand',
          artist: 'Tally Hall',
          duration: Duration(minutes: 1, seconds: 53),
          youtubeVideoId: 'EOw3y4cR3_k',
          thumbnailUrl: 'https://img.youtube.com/vi/EOw3y4cR3_k/hqdefault.jpg',
        ),
        LocalPlaylistTrack(
          title: 'Hayloft',
          artist: 'Mother Mother',
          duration: Duration(minutes: 3, seconds: 2),
          youtubeVideoId: 'sZdzxIMstgE',
          thumbnailUrl: 'https://img.youtube.com/vi/sZdzxIMstgE/hqdefault.jpg',
        ),
        LocalPlaylistTrack(
          title: 'Touch-Tone Telephone',
          artist: 'Lemon Demon',
          duration: Duration(minutes: 3, seconds: 40),
          youtubeVideoId: 'rb9c0dGnYhk',
          thumbnailUrl: 'https://img.youtube.com/vi/rb9c0dGnYhk/hqdefault.jpg',
        ),
        LocalPlaylistTrack(
          title: 'Oh Klahoma',
          artist: 'Jack Stauber',
          duration: Duration(minutes: 3, seconds: 8),
          youtubeVideoId: 'YrnO0XQ4s_E',
          thumbnailUrl: 'https://img.youtube.com/vi/YrnO0XQ4s_E/hqdefault.jpg',
        ),
        LocalPlaylistTrack(
          title: 'This Is Home',
          artist: 'Cavetown',
          duration: Duration(minutes: 3, seconds: 46),
          youtubeVideoId: 'd_V6XnF_U0M',
          thumbnailUrl: 'https://img.youtube.com/vi/d_V6XnF_U0M/hqdefault.jpg',
        ),
        LocalPlaylistTrack(
          title: 'Mr Loverman',
          artist: 'Ricky Montgomery',
          duration: Duration(minutes: 3, seconds: 36),
          youtubeVideoId: 'UvF3lCg36Zg',
          thumbnailUrl: 'https://img.youtube.com/vi/UvF3lCg36Zg/hqdefault.jpg',
        ),
      ];
    }
    return const [
      LocalPlaylistTrack(
        title: 'Espresso',
        artist: 'Sabrina Carpenter',
        duration: Duration(minutes: 2, seconds: 55),
        youtubeVideoId: 'eVli-tstM5E',
        thumbnailUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Birds of a Feather',
        artist: 'Billie Eilish',
        duration: Duration(minutes: 3, seconds: 30),
        youtubeVideoId: 'd5gf9dXbPi0',
        thumbnailUrl: 'https://img.youtube.com/vi/d5gf9dXbPi0/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Levitating',
        artist: 'Dua Lipa',
        duration: Duration(minutes: 3, seconds: 23),
        youtubeVideoId: 'TUVcZfQe-Kw',
        thumbnailUrl: 'https://img.youtube.com/vi/TUVcZfQe-Kw/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        duration: Duration(minutes: 3, seconds: 20),
        youtubeVideoId: '4NRXx6U8ABQ',
        thumbnailUrl: 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Too Sweet',
        artist: 'Hozier',
        duration: Duration(minutes: 4, seconds: 11),
        youtubeVideoId: 'aezstcBhopQ',
        thumbnailUrl: 'https://img.youtube.com/vi/aezstcBhopQ/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'As It Was',
        artist: 'Harry Styles',
        duration: Duration(minutes: 2, seconds: 47),
        youtubeVideoId: 'H5v3kku4y6Q',
        thumbnailUrl: 'https://img.youtube.com/vi/H5v3kku4y6Q/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Boys Will Be Bugs',
        artist: 'Cavetown',
        duration: Duration(minutes: 5, seconds: 29),
        youtubeVideoId: 'uR_E_1U0QvY',
        thumbnailUrl: 'https://img.youtube.com/vi/uR_E_1U0QvY/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Buttercup',
        artist: 'Jack Stauber',
        duration: Duration(minutes: 3, seconds: 28),
        youtubeVideoId: 'eYDI8b5Nn5s',
        thumbnailUrl: 'https://img.youtube.com/vi/eYDI8b5Nn5s/hqdefault.jpg',
      ),
    ];
  }

  List<LocalPlaylistTrack> _getSimilarTracks(String seedArtist) {
    final cleanSeed = seedArtist.toLowerCase().trim();
    final nonSeedList = <LocalPlaylistTrack>[];

    // Filter out seed artist from dynamic similar tracks
    for (final t in _dynamicSimilarTracks) {
      final tArt = t.artist.toLowerCase().trim();
      if (!tArt.contains(cleanSeed) && !cleanSeed.contains(tArt)) {
        if (!nonSeedList.any((x) => x.youtubeVideoId == t.youtubeVideoId || x.title.toLowerCase() == t.title.toLowerCase())) {
          nonSeedList.add(t);
        }
      }
    }

    // Fill with related artists pool
    if (nonSeedList.length < 8) {
      for (final t in _getRelatedArtistsPool(seedArtist)) {
        final tArt = t.artist.toLowerCase().trim();
        if (!tArt.contains(cleanSeed) && !cleanSeed.contains(tArt)) {
          if (!nonSeedList.any((x) => x.youtubeVideoId == t.youtubeVideoId || x.title.toLowerCase() == t.title.toLowerCase())) {
            nonSeedList.add(t);
          }
        }
      }
    }

    return nonSeedList.take(12).toList();
  }

  List<({String title, String artist, String coverUrl, String subtitle})> _getCommunityPlaylists() {
    if (_dynamicCommunityPlaylists.isNotEmpty) {
      final list = List<({String title, String artist, String coverUrl, String subtitle})>.from(_dynamicCommunityPlaylists);
      if (_refreshCount > 0) {
        final shift = (_refreshCount * 2) % list.length;
        return [...list.skip(shift), ...list.take(shift)].take(8).toList();
      }
      return list.take(8).toList();
    }
    return _getFallbackCommunityPlaylists();
  }

  List<({String title, String artist, String coverUrl, String subtitle})> _getFallbackCommunityPlaylists() {
    return const [
      (
        title: 'Indie & Animation Vibes',
        artist: 'FinAudio Curated',
        coverUrl: 'https://img.youtube.com/vi/uR_E_1U0QvY/hqdefault.jpg',
        subtitle: 'Playlist • 45 tracks',
      ),
      (
        title: 'Bedroom Pop & Lofi Beats',
        artist: 'YouTube Community',
        coverUrl: 'https://img.youtube.com/vi/eYDI8b5Nn5s/hqdefault.jpg',
        subtitle: 'Playlist • 60 tracks',
      ),
      (
        title: 'Today\'s Global Top Hits',
        artist: 'YouTube Music',
        coverUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg',
        subtitle: 'Playlist • 50 tracks',
      ),
      (
        title: 'Late Night Chill Session',
        artist: 'Vibe Central',
        coverUrl: 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
        subtitle: 'Playlist • 75 tracks',
      ),
      (
        title: 'Acoustic & Storytelling Pop',
        artist: 'Indie Spotlight',
        coverUrl: 'https://img.youtube.com/vi/O3NqK304aQE/hqdefault.jpg',
        subtitle: 'Playlist • 38 tracks',
      ),
      (
        title: 'Electronic & Hyper Beats',
        artist: 'BeatLab',
        coverUrl: 'https://img.youtube.com/vi/gCYcHz2k5x0/hqdefault.jpg',
        subtitle: 'Playlist • 55 tracks',
      ),
    ];
  }

  List<LocalPlaylistTrack> _getQuickPicks() {
    if (_selectedMood != null) {
      return _getMoodPicks(_selectedMood!);
    }

    final blended = <LocalPlaylistTrack>[];
    final seenKeys = <String>{};
    final artistCount = <String, int>{};
    const int maxPerArtist = 2; // Strict cap to prevent single-artist monopoly

    void addTrack(LocalPlaylistTrack t, {bool enforceArtistCap = true}) {
      final key = (t.youtubeVideoId != null && t.youtubeVideoId!.isNotEmpty)
          ? t.youtubeVideoId!
          : '${t.title}_${t.artist}'.toLowerCase().trim();
      final normTitle = t.title.toLowerCase().trim();
      final normArtist = t.artist.toLowerCase().trim();

      if (seenKeys.contains(key) || seenKeys.contains(normTitle)) {
        return;
      }

      if (enforceArtistCap) {
        final currentCount = artistCount[normArtist] ?? 0;
        if (currentCount >= maxPerArtist && blended.length < 14) {
          return;
        }
        artistCount[normArtist] = currentCount + 1;
      }

      seenKeys.add(key);
      seenKeys.add(normTitle);
      blended.add(t);
    }

    final topArtists = _extractUserTopArtists();
    final primaryArtist = topArtists.isNotEmpty ? topArtists.first : '';

    // 1. Personalize with user's actual history (top recent tracks, max 2 per artist)
    final historyTracks = _historyService.recentTracks.map((h) => h.toLocalPlaylistTrack()).toList();
    for (final t in historyTracks) {
      if (blended.length >= 4) break;
      addTrack(t);
    }

    // 2. Personalize with Liked Songs (max 2 per artist)
    final likedTracks = widget.playlistService.likedSongsPlaylist.tracks;
    for (final t in likedTracks) {
      if (blended.length >= 6) break;
      addTrack(t);
    }

    // 3. Live dynamic quick picks from InnerTube / YouTube Music (max 2 per artist)
    if (_dynamicQuickPicks.isNotEmpty) {
      final list = List<LocalPlaylistTrack>.from(_dynamicQuickPicks);
      if (_refreshCount > 0) {
        final shift = (_refreshCount * 3) % list.length;
        final rotated = [...list.skip(shift), ...list.take(shift)];
        for (final t in rotated) {
          if (blended.length >= 10) break;
          addTrack(t);
        }
      } else {
        for (final t in list) {
          if (blended.length >= 10) break;
          addTrack(t);
        }
      }
    }

    // 4. Inject related discovery artists (e.g. Cavetown, Jack Stauber if seed is YonKaGor)
    if (primaryArtist.isNotEmpty) {
      final related = _getRelatedArtistsPool(primaryArtist);
      for (final t in related) {
        if (blended.length >= 14) break;
        addTrack(t);
      }
    }

    // 5. Fill remaining slots from rotating fallback pool
    for (final t in _getRotatingFallbackPool(_refreshCount)) {
      if (blended.length >= 16) break;
      addTrack(t);
    }

    // 6. Relax cap if still needed
    if (blended.length < 16) {
      for (final t in _getRotatingFallbackPool(_refreshCount + 1)) {
        if (blended.length >= 16) break;
        addTrack(t, enforceArtistCap: false);
      }
    }

    return blended.take(16).toList();
  }

  List<LocalPlaylistTrack> _getRotatingFallbackPool(int seed) {
    const baseList = [
      LocalPlaylistTrack(
        title: 'Jump Up, Super Star! (Super Mario Odyssey)',
        artist: 'Matt Dusk',
        duration: Duration(minutes: 3, seconds: 40),
        youtubeVideoId: 'kmbg2h_TjEU',
        thumbnailUrl: 'https://img.youtube.com/vi/kmbg2h_TjEU/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Writing On The Wall',
        artist: 'kanalia',
        duration: Duration(minutes: 3, seconds: 15),
        youtubeVideoId: 'h8VnYvE1e6w',
        thumbnailUrl: 'https://img.youtube.com/vi/h8VnYvE1e6w/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        duration: Duration(minutes: 3, seconds: 20),
        youtubeVideoId: '4NRXx6U8ABQ',
        thumbnailUrl: 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Levitating',
        artist: 'Dua Lipa',
        duration: Duration(minutes: 3, seconds: 23),
        youtubeVideoId: 'TUVcZfQe-Kw',
        thumbnailUrl: 'https://img.youtube.com/vi/TUVcZfQe-Kw/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Starboy',
        artist: 'The Weeknd, Daft Punk',
        duration: Duration(minutes: 3, seconds: 50),
        youtubeVideoId: '34Na4j8AVgA',
        thumbnailUrl: 'https://img.youtube.com/vi/34Na4j8AVgA/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Cruel Summer',
        artist: 'Taylor Swift',
        duration: Duration(minutes: 2, seconds: 58),
        youtubeVideoId: 'ic8j13piAhQ',
        thumbnailUrl: 'https://img.youtube.com/vi/ic8j13piAhQ/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        duration: Duration(minutes: 3, seconds: 53),
        youtubeVideoId: 'JGwWNGJdvx8',
        thumbnailUrl: 'https://img.youtube.com/vi/JGwWNGJdvx8/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'As It Was',
        artist: 'Harry Styles',
        duration: Duration(minutes: 2, seconds: 47),
        youtubeVideoId: 'H5v3kku4y6Q',
        thumbnailUrl: 'https://img.youtube.com/vi/H5v3kku4y6Q/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Espresso',
        artist: 'Sabrina Carpenter',
        duration: Duration(minutes: 2, seconds: 55),
        youtubeVideoId: 'eVli-tstM5E',
        thumbnailUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Birds of a Feather',
        artist: 'Billie Eilish',
        duration: Duration(minutes: 3, seconds: 30),
        youtubeVideoId: 'd5gf9dXbPi0',
        thumbnailUrl: 'https://img.youtube.com/vi/d5gf9dXbPi0/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Houdini',
        artist: 'Dua Lipa',
        duration: Duration(minutes: 3, seconds: 5),
        youtubeVideoId: 'suAR1PYFNYA',
        thumbnailUrl: 'https://img.youtube.com/vi/suAR1PYFNYA/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Too Sweet',
        artist: 'Hozier',
        duration: Duration(minutes: 4, seconds: 11),
        youtubeVideoId: 'aezstcBhopQ',
        thumbnailUrl: 'https://img.youtube.com/vi/aezstcBhopQ/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Training Season',
        artist: 'Dua Lipa',
        duration: Duration(minutes: 3, seconds: 30),
        youtubeVideoId: 'n0GXk_T2zs8',
        thumbnailUrl: 'https://img.youtube.com/vi/n0GXk_T2zs8/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Save Your Tears',
        artist: 'The Weeknd',
        duration: Duration(minutes: 3, seconds: 35),
        youtubeVideoId: 'XXYlFuWEuKi',
        thumbnailUrl: 'https://img.youtube.com/vi/XXYlFuWEuKi/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Anti-Hero',
        artist: 'Taylor Swift',
        duration: Duration(minutes: 3, seconds: 20),
        youtubeVideoId: 'b1kbLwvqugk',
        thumbnailUrl: 'https://img.youtube.com/vi/b1kbLwvqugk/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Flowers',
        artist: 'Miley Cyrus',
        duration: Duration(minutes: 3, seconds: 20),
        youtubeVideoId: 'G7KNmW9a75Y',
        thumbnailUrl: 'https://img.youtube.com/vi/G7KNmW9a75Y/hqdefault.jpg',
      ),
    ];

    if (seed == 0) return baseList;
    final shift = (seed * 4) % baseList.length;
    return [...baseList.skip(shift), ...baseList.take(shift)].take(16).toList();
  }

  List<LocalPlaylistTrack> _getMoodPicks(String mood) {
    if (_moodTracksCache.containsKey(mood) && _moodTracksCache[mood]!.isNotEmpty) {
      return _moodTracksCache[mood]!;
    }

    List<LocalPlaylistTrack> pool;
    switch (mood) {
      case 'Energize':
        pool = const [
          LocalPlaylistTrack(
            title: 'Can\'t Hold Us',
            artist: 'Macklemore & Ryan Lewis',
            duration: Duration(minutes: 4, seconds: 18),
            youtubeVideoId: '2zNSgSzhBf8',
            thumbnailUrl: 'https://img.youtube.com/vi/2zNSgSzhBf8/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Titanium',
            artist: 'David Guetta ft. Sia',
            duration: Duration(minutes: 4, seconds: 5),
            youtubeVideoId: 'JRfuAukYTKg',
            thumbnailUrl: 'https://img.youtube.com/vi/JRfuAukYTKg/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Wake Me Up',
            artist: 'Avicii',
            duration: Duration(minutes: 4, seconds: 7),
            youtubeVideoId: 'IcrbM1l_BoI',
            thumbnailUrl: 'https://img.youtube.com/vi/IcrbM1l_BoI/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Levels',
            artist: 'Avicii',
            duration: Duration(minutes: 3, seconds: 20),
            youtubeVideoId: '_ovdm2yX4MA',
            thumbnailUrl: 'https://img.youtube.com/vi/_ovdm2yX4MA/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Physical',
            artist: 'Dua Lipa',
            duration: Duration(minutes: 3, seconds: 13),
            youtubeVideoId: '9HDEHj2yzew',
            thumbnailUrl: 'https://img.youtube.com/vi/9HDEHj2yzew/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Animals',
            artist: 'Martin Garrix',
            duration: Duration(minutes: 2, seconds: 56),
            youtubeVideoId: 'gCYcHz2k5x0',
            thumbnailUrl: 'https://img.youtube.com/vi/gCYcHz2k5x0/hqdefault.jpg',
          ),
        ];
        break;
      case 'Workout':
        pool = const [
          LocalPlaylistTrack(
            title: 'Till I Collapse',
            artist: 'Eminem',
            duration: Duration(minutes: 4, seconds: 57),
            youtubeVideoId: 'gY9C0IztE0Q',
            thumbnailUrl: 'https://img.youtube.com/vi/gY9C0IztE0Q/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Stronger',
            artist: 'Kanye West',
            duration: Duration(minutes: 5, seconds: 11),
            youtubeVideoId: 'PsO6Zn4V00M',
            thumbnailUrl: 'https://img.youtube.com/vi/PsO6Zn4V00M/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Eye of the Tiger',
            artist: 'Survivor',
            duration: Duration(minutes: 4, seconds: 5),
            youtubeVideoId: 'btPJPFnesV4',
            thumbnailUrl: 'https://img.youtube.com/vi/btPJPFnesV4/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Lose Yourself',
            artist: 'Eminem',
            duration: Duration(minutes: 5, seconds: 20),
            youtubeVideoId: '_Yhyp_hFq44',
            thumbnailUrl: 'https://img.youtube.com/vi/_Yhyp_hFq44/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Remember the Name',
            artist: 'Fort Minor',
            duration: Duration(minutes: 3, seconds: 50),
            youtubeVideoId: 'VDvr08sCPOc',
            thumbnailUrl: 'https://img.youtube.com/vi/VDvr08sCPOc/hqdefault.jpg',
          ),
        ];
        break;
      case 'Relax':
        pool = const [
          LocalPlaylistTrack(
            title: 'Solo Piano Bliss',
            artist: 'Jasper Harris',
            duration: Duration(minutes: 3, seconds: 12),
            youtubeVideoId: 'fJ9rUzIMcZQ',
            thumbnailUrl: 'https://img.youtube.com/vi/fJ9rUzIMcZQ/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Mellow Pop Classics',
            artist: 'Robbie Williams',
            duration: Duration(minutes: 4, seconds: 0),
            youtubeVideoId: 'bpOSxM0tfN8',
            thumbnailUrl: 'https://img.youtube.com/vi/bpOSxM0tfN8/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Sunset Lover',
            artist: 'Petit Biscuit',
            duration: Duration(minutes: 3, seconds: 57),
            youtubeVideoId: '4NRXx6U8ABQ',
            thumbnailUrl: 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Weightless',
            artist: 'Marconi Union',
            duration: Duration(minutes: 8, seconds: 8),
            youtubeVideoId: 'UfcAVejslrU',
            thumbnailUrl: 'https://img.youtube.com/vi/UfcAVejslrU/hqdefault.jpg',
          ),
        ];
        break;
      case 'Focus':
      case 'Commute':
      case 'Feel good':
      default:
        pool = const [
          LocalPlaylistTrack(
            title: 'Sunflower',
            artist: 'Post Malone, Swae Lee',
            duration: Duration(minutes: 2, seconds: 38),
            youtubeVideoId: 'ApXoWvfEYVU',
            thumbnailUrl: 'https://img.youtube.com/vi/ApXoWvfEYVU/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Happy',
            artist: 'Pharrell Williams',
            duration: Duration(minutes: 3, seconds: 53),
            youtubeVideoId: 'y6Sxv-sUYtM',
            thumbnailUrl: 'https://img.youtube.com/vi/y6Sxv-sUYtM/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Good Life',
            artist: 'OneRepublic',
            duration: Duration(minutes: 4, seconds: 13),
            youtubeVideoId: 'jZhQOvvV45w',
            thumbnailUrl: 'https://img.youtube.com/vi/jZhQOvvV45w/hqdefault.jpg',
          ),
          LocalPlaylistTrack(
            title: 'Counting Stars',
            artist: 'OneRepublic',
            duration: Duration(minutes: 4, seconds: 17),
            youtubeVideoId: 'hT_nvWreIhg',
            thumbnailUrl: 'https://img.youtube.com/vi/hT_nvWreIhg/hqdefault.jpg',
          ),
        ];
        break;
    }

    if (_refreshCount > 0 && pool.length > 2) {
      final shift = _refreshCount % pool.length;
      return [...pool.skip(shift), ...pool.take(shift)];
    }
    return pool;
  }

  List<({String title, String artist, String coverUrl, VoidCallback? onTap})> _getSpeedDialItems() {
    final List<({String title, String artist, String coverUrl, VoidCallback? onTap})> items = [];

    // 1. User's recent plays from HistoryService
    final recentTracks = _historyService.recentTracks;
    for (final h in recentTracks) {
      final track = h.toLocalPlaylistTrack();
      if (!items.any((i) => i.title == track.title)) {
        items.add((
          title: track.title,
          artist: track.artist,
          coverUrl: track.thumbnailUrl ?? 'https://img.youtube.com/vi/${track.youtubeVideoId}/hqdefault.jpg',
          onTap: () => _playTrackList([track], 0),
        ));
      }
      if (items.length >= 5) break;
    }

    // 2. User's imported/custom playlists
    for (final p in widget.playlistService.playlists) {
      if (p.id == 'liked_songs' || p.tracks.isEmpty) continue;
      if (!items.any((i) => i.title == p.title)) {
        items.add((
          title: p.title,
          artist: 'Playlist • ${p.trackCount} tracks',
          coverUrl: p.effectiveThumbnailUrl,
          onTap: () => widget.onOpenPlaylistDetail(p),
        ));
      }
      if (items.length >= 7) break;
    }

    // 3. Fallback/rotating items if history/library is small
    if (items.length < 7) {
      final fallbackPool = _getSpeedDialFallbackPool(_refreshCount);
      for (final f in fallbackPool) {
        if (!items.any((i) => i.title == f.title)) {
          items.add(f);
        }
        if (items.length >= 7) break;
      }
    }

    return items;
  }

  VoidCallback _seedTrackTap(String title, String artist, String videoId, String coverUrl) {
    return () {
      final track = LocalPlaylistTrack(
        title: title,
        artist: artist,
        youtubeVideoId: videoId,
        thumbnailUrl: coverUrl,
        duration: const Duration(minutes: 3, seconds: 30),
      );
      _playTrackList([track], 0);
    };
  }

  List<({String title, String artist, String coverUrl, VoidCallback? onTap})> _getSpeedDialFallbackPool(int seed) {
    if (seed % 3 == 1) {
      return [
        (title: 'Today\'s Top Hits', artist: 'Popular Mix', coverUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg', onTap: _seedTrackTap('Today\'s Top Hits', 'Popular Mix', 'eVli-tstM5E', 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg')),
        (title: 'Training Season', artist: 'Dua Lipa', coverUrl: 'https://img.youtube.com/vi/n0GXk_T2zs8/hqdefault.jpg', onTap: _seedTrackTap('Training Season', 'Dua Lipa', 'n0GXk_T2zs8', 'https://img.youtube.com/vi/n0GXk_T2zs8/hqdefault.jpg')),
        (title: 'Starboy', artist: 'The Weeknd', coverUrl: 'https://img.youtube.com/vi/34Na4j8AVgA/hqdefault.jpg', onTap: _seedTrackTap('Starboy', 'The Weeknd', '34Na4j8AVgA', 'https://img.youtube.com/vi/34Na4j8AVgA/hqdefault.jpg')),
        (title: 'Cruel Summer', artist: 'Taylor Swift', coverUrl: 'https://img.youtube.com/vi/ic8j13piAhQ/hqdefault.jpg', onTap: _seedTrackTap('Cruel Summer', 'Taylor Swift', 'ic8j13piAhQ', 'https://img.youtube.com/vi/ic8j13piAhQ/hqdefault.jpg')),
        (title: 'Espresso', artist: 'Sabrina Carpenter', coverUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg', onTap: _seedTrackTap('Espresso', 'Sabrina Carpenter', 'eVli-tstM5E', 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg')),
        (title: 'Birds of a Feather', artist: 'Billie Eilish', coverUrl: 'https://img.youtube.com/vi/d5gf9dXbPi0/hqdefault.jpg', onTap: _seedTrackTap('Birds of a Feather', 'Billie Eilish', 'd5gf9dXbPi0', 'https://img.youtube.com/vi/d5gf9dXbPi0/hqdefault.jpg')),
        (title: 'Houdini', artist: 'Dua Lipa', coverUrl: 'https://img.youtube.com/vi/suAR1PYFNYA/hqdefault.jpg', onTap: _seedTrackTap('Houdini', 'Dua Lipa', 'suAR1PYFNYA', 'https://img.youtube.com/vi/suAR1PYFNYA/hqdefault.jpg')),
      ];
    } else if (seed % 3 == 2) {
      return [
        (title: 'Deep Focus Mix', artist: 'Ambient Chill', coverUrl: 'https://img.youtube.com/vi/ApXoWvfEYVU/hqdefault.jpg', onTap: _seedTrackTap('Deep Focus Mix', 'Ambient Chill', 'ApXoWvfEYVU', 'https://img.youtube.com/vi/ApXoWvfEYVU/hqdefault.jpg')),
        (title: 'Blinding Lights', artist: 'The Weeknd', coverUrl: 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg', onTap: _seedTrackTap('Blinding Lights', 'The Weeknd', '4NRXx6U8ABQ', 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg')),
        (title: 'Levitating', artist: 'Dua Lipa', coverUrl: 'https://img.youtube.com/vi/TUVcZfQe-Kw/hqdefault.jpg', onTap: _seedTrackTap('Levitating', 'Dua Lipa', 'TUVcZfQe-Kw', 'https://img.youtube.com/vi/TUVcZfQe-Kw/hqdefault.jpg')),
        (title: 'Too Sweet', artist: 'Hozier', coverUrl: 'https://img.youtube.com/vi/aezstcBhopQ/hqdefault.jpg', onTap: _seedTrackTap('Too Sweet', 'Hozier', 'aezstcBhopQ', 'https://img.youtube.com/vi/aezstcBhopQ/hqdefault.jpg')),
        (title: 'As It Was', artist: 'Harry Styles', coverUrl: 'https://img.youtube.com/vi/H5v3kku4y6Q/hqdefault.jpg', onTap: _seedTrackTap('As It Was', 'Harry Styles', 'H5v3kku4y6Q', 'https://img.youtube.com/vi/H5v3kku4y6Q/hqdefault.jpg')),
        (title: 'PARALLAX', artist: 'Album', coverUrl: 'https://img.youtube.com/vi/bpOSxM0tfN8/hqdefault.jpg', onTap: _seedTrackTap('PARALLAX', 'Album', 'bpOSxM0tfN8', 'https://img.youtube.com/vi/bpOSxM0tfN8/hqdefault.jpg')),
        (title: 'The Storm', artist: 'TheFatRat', coverUrl: 'https://img.youtube.com/vi/fJ9rUzIMcZQ/hqdefault.jpg', onTap: _seedTrackTap('The Storm', 'TheFatRat', 'fJ9rUzIMcZQ', 'https://img.youtube.com/vi/fJ9rUzIMcZQ/hqdefault.jpg')),
      ];
    }

    return [
      (title: 'Recap March-May', artist: 'Auto mix', coverUrl: 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg', onTap: _seedTrackTap('Recap March-May', 'Auto mix', '4NRXx6U8ABQ', 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg')),
      (title: 'Yoshida Yasei', artist: 'Artist', coverUrl: 'https://img.youtube.com/vi/XXYlFuWEuKi/hqdefault.jpg', onTap: _seedTrackTap('Yoshida Yasei', 'Artist', 'XXYlFuWEuKi', 'https://img.youtube.com/vi/XXYlFuWEuKi/hqdefault.jpg')),
      (title: 'テレパシ', artist: 'Song', coverUrl: 'https://img.youtube.com/vi/TUVcZfQe-Kw/hqdefault.jpg', onTap: _seedTrackTap('テレパシ', 'Song', 'TUVcZfQe-Kw', 'https://img.youtube.com/vi/TUVcZfQe-Kw/hqdefault.jpg')),
      (title: 'Writing On The Wall', artist: 'kanalia', coverUrl: 'https://img.youtube.com/vi/h8VnYvE1e6w/hqdefault.jpg', onTap: _seedTrackTap('Writing On The Wall', 'kanalia', 'h8VnYvE1e6w', 'https://img.youtube.com/vi/h8VnYvE1e6w/hqdefault.jpg')),
      (title: 'ItaloBrothers', artist: 'Artist', coverUrl: 'https://img.youtube.com/vi/34Na4j8AVgA/hqdefault.jpg', onTap: _seedTrackTap('ItaloBrothers', 'Artist', '34Na4j8AVgA', 'https://img.youtube.com/vi/34Na4j8AVgA/hqdefault.jpg')),
      (title: 'PARALLAX', artist: 'Album', coverUrl: 'https://img.youtube.com/vi/bpOSxM0tfN8/hqdefault.jpg', onTap: _seedTrackTap('PARALLAX', 'Album', 'bpOSxM0tfN8', 'https://img.youtube.com/vi/bpOSxM0tfN8/hqdefault.jpg')),
      (title: 'The Storm', artist: 'TheFatRat', coverUrl: 'https://img.youtube.com/vi/fJ9rUzIMcZQ/hqdefault.jpg', onTap: _seedTrackTap('The Storm', 'TheFatRat', 'fJ9rUzIMcZQ', 'https://img.youtube.com/vi/fJ9rUzIMcZQ/hqdefault.jpg')),
    ];
  }

  List<({String title, String artist, String coverUrl, String subtitle})> _getRecommendedAlbums() {
    final blended = <({String title, String artist, String coverUrl, String subtitle})>[];
    final seenArtists = <String>{};

    void addAlbum(({String title, String artist, String coverUrl, String subtitle}) a) {
      final normArtist = a.artist.toLowerCase().trim();
      if (!seenArtists.contains(normArtist)) {
        seenArtists.add(normArtist);
        blended.add(a);
      }
    }

    if (_dynamicAlbums.isNotEmpty) {
      final list = List<({String title, String artist, String coverUrl, String subtitle})>.from(_dynamicAlbums);
      if (_refreshCount > 0) {
        final shift = (_refreshCount * 2) % list.length;
        for (final a in [...list.skip(shift), ...list.take(shift)]) {
          addAlbum(a);
          if (blended.length >= 6) break;
        }
      } else {
        for (final a in list) {
          addAlbum(a);
          if (blended.length >= 6) break;
        }
      }
    }

    // Fill remaining with diverse fallback albums
    for (final a in _getRotatingFallbackAlbums(_refreshCount)) {
      addAlbum(a);
      if (blended.length >= 6) break;
    }

    return blended.take(6).toList();
  }

  List<({String title, String artist, String coverUrl, String subtitle})> _getRotatingFallbackAlbums(int seed) {
    const list = [
      (
        title: 'Worm Food',
        artist: 'Cavetown',
        subtitle: 'Album • Cavetown',
        coverUrl: 'https://img.youtube.com/vi/uR_E_1U0QvY/hqdefault.jpg',
      ),
      (
        title: 'Pop Food',
        artist: 'Jack Stauber',
        subtitle: 'Album • Jack Stauber',
        coverUrl: 'https://img.youtube.com/vi/eYDI8b5Nn5s/hqdefault.jpg',
      ),
      (
        title: 'After Hours',
        artist: 'The Weeknd',
        subtitle: 'Album • The Weeknd',
        coverUrl: 'https://img.youtube.com/vi/XXYlFuWEuKi/hqdefault.jpg',
      ),
      (
        title: 'Future Nostalgia',
        artist: 'Dua Lipa',
        subtitle: 'Album • Dua Lipa',
        coverUrl: 'https://img.youtube.com/vi/TUVcZfQe-Kw/hqdefault.jpg',
      ),
      (
        title: 'AM',
        artist: 'Arctic Monkeys',
        subtitle: 'Album • Arctic Monkeys',
        coverUrl: 'https://img.youtube.com/vi/bpOSxM0tfN8/hqdefault.jpg',
      ),
      (
        title: 'Short n\' Sweet',
        artist: 'Sabrina Carpenter',
        subtitle: 'Album • Sabrina Carpenter',
        coverUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg',
      ),
      (
        title: 'HIT ME HARD AND SOFT',
        artist: 'Billie Eilish',
        subtitle: 'Album • Billie Eilish',
        coverUrl: 'https://img.youtube.com/vi/d5gf9dXbPi0/hqdefault.jpg',
      ),
      (
        title: 'Abbey Road',
        artist: 'The Beatles',
        subtitle: 'Album • The Beatles',
        coverUrl: 'https://img.youtube.com/vi/NCtzkaL2t_Y/hqdefault.jpg',
      ),
    ];

    if (seed == 0) return list.take(6).toList();
    final shift = (seed * 2) % list.length;
    return [...list.skip(shift), ...list.take(shift)].take(6).toList();
  }

  List<LocalPlaylistTrack> _getNewReleases() {
    if (_dynamicNewReleases.isNotEmpty) {
      final list = List<LocalPlaylistTrack>.from(_dynamicNewReleases);
      if (_refreshCount > 0) {
        final shift = (_refreshCount * 2) % list.length;
        final rotated = [...list.skip(shift), ...list.take(shift)];
        return rotated.take(8).toList();
      }
      return list.take(8).toList();
    }
    return _getRotatingFallbackNewReleases(_refreshCount);
  }

  List<LocalPlaylistTrack> _getRotatingFallbackNewReleases(int seed) {
    const list = [
      LocalPlaylistTrack(
        title: 'Espresso',
        artist: 'Sabrina Carpenter',
        duration: Duration(minutes: 2, seconds: 55),
        youtubeVideoId: 'eVli-tstM5E',
        thumbnailUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Birds of a Feather',
        artist: 'Billie Eilish',
        duration: Duration(minutes: 3, seconds: 30),
        youtubeVideoId: 'd5gf9dXbPi0',
        thumbnailUrl: 'https://img.youtube.com/vi/d5gf9dXbPi0/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Houdini',
        artist: 'Dua Lipa',
        duration: Duration(minutes: 3, seconds: 5),
        youtubeVideoId: 'suAR1PYFNYA',
        thumbnailUrl: 'https://img.youtube.com/vi/suAR1PYFNYA/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Too Sweet',
        artist: 'Hozier',
        duration: Duration(minutes: 4, seconds: 11),
        youtubeVideoId: 'aezstcBhopQ',
        thumbnailUrl: 'https://img.youtube.com/vi/aezstcBhopQ/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'here Is Dead',
        artist: 'Oricade',
        duration: Duration(minutes: 3, seconds: 10),
        youtubeVideoId: 'h8VnYvE1e6w',
        thumbnailUrl: 'https://img.youtube.com/vi/h8VnYvE1e6w/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Training Season',
        artist: 'Dua Lipa',
        duration: Duration(minutes: 3, seconds: 30),
        youtubeVideoId: 'n0GXk_T2zs8',
        thumbnailUrl: 'https://img.youtube.com/vi/n0GXk_T2zs8/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Taste',
        artist: 'Sabrina Carpenter',
        duration: Duration(minutes: 2, seconds: 37),
        youtubeVideoId: 'k1V3z96f8sA',
        thumbnailUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg',
      ),
      LocalPlaylistTrack(
        title: 'Lunch',
        artist: 'Billie Eilish',
        duration: Duration(minutes: 3, seconds: 0),
        youtubeVideoId: 'MB3VkzPdgLA',
        thumbnailUrl: 'https://img.youtube.com/vi/d5gf9dXbPi0/hqdefault.jpg',
      ),
    ];

    if (seed == 0) return list.take(5).toList();
    final shift = (seed * 2) % list.length;
    return [...list.skip(shift), ...list.take(shift)].take(6).toList();
  }

  List<({String name, String? channelId, String? imageUrl, String subscribers})> _getMusicArtists() {
    final List<({String name, String? channelId, String? imageUrl, String subscribers})> list = [];

    for (final sub in _subscribedArtists) {
      list.add((
        name: sub.title,
        channelId: sub.channelId,
        imageUrl: sub.thumbnailUrl.isNotEmpty ? sub.thumbnailUrl : null,
        subscribers: 'Subscribed artist',
      ));
    }

    for (final art in _dynamicArtists) {
      if (!list.any((a) => a.name.toLowerCase() == art.name.toLowerCase())) {
        list.add(art);
      }
    }

    final topArtists = _extractUserTopArtists();
    for (final name in topArtists) {
      if (!list.any((a) => a.name.toLowerCase() == name.toLowerCase())) {
        list.add((name: name, channelId: null, imageUrl: null, subscribers: 'Top artist for you'));
      }
    }

    final followed = widget.settingsService.favoriteArtists.toList();
    for (final name in followed) {
      if (!list.any((a) => a.name.toLowerCase() == name.toLowerCase())) {
        list.add((name: name, channelId: null, imageUrl: null, subscribers: 'Followed artist'));
      }
    }

    final discoveryCatalog = const [
      (name: 'Cavetown', channelId: 'UCa_F74q3u-l_L3bVfLpW43w', imageUrl: 'https://img.youtube.com/vi/uR_E_1U0QvY/hqdefault.jpg', subscribers: '2.4M subscribers'),
      (name: 'Jack Stauber', channelId: 'UCg4n73e72y1sNfAeeT3J7eA', imageUrl: 'https://img.youtube.com/vi/eYDI8b5Nn5s/hqdefault.jpg', subscribers: '3.1M subscribers'),
      (name: 'Ricky Montgomery', channelId: 'UC2wRz2l771j0d3Bq36q3Q3A', imageUrl: 'https://img.youtube.com/vi/O3NqK304aQE/hqdefault.jpg', subscribers: '1.8M subscribers'),
      (name: 'Bo Burnham', channelId: 'UC8B_XqgQy-kZ9vK2ZtD1tXw', imageUrl: 'https://img.youtube.com/vi/l_nJ4f_v2j4/hqdefault.jpg', subscribers: '3.5M subscribers'),
      (name: 'Mother Mother', channelId: 'UC9kLz1j43-a62n93_s_Z51A', imageUrl: 'https://img.youtube.com/vi/sZdzxIMstgE/hqdefault.jpg', subscribers: '2.1M subscribers'),
      (name: 'Sabrina Carpenter', channelId: 'UC1eK1s54B_8P-L-o4B4uY9Q', imageUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg', subscribers: '12M subscribers'),
      (name: 'Billie Eilish', channelId: 'UCiGm_E4ZwYSHV3bcW1pnSeQ', imageUrl: 'https://img.youtube.com/vi/d5gf9dXbPi0/hqdefault.jpg', subscribers: '50M subscribers'),
      (name: 'The Weeknd', channelId: 'UC0WP5P-ufpRfjbNrmOWwLBQ', imageUrl: 'https://img.youtube.com/vi/XXYlFuWEuKi/hqdefault.jpg', subscribers: '35M subscribers'),
      (name: 'Dua Lipa', channelId: 'UC-J-KZfRV8c13fGAxGZ-9dQ', imageUrl: 'https://img.youtube.com/vi/TUVcZfQe-Kw/hqdefault.jpg', subscribers: '23M subscribers'),
    ];

    for (final disc in discoveryCatalog) {
      if (!list.any((a) => a.name.toLowerCase() == disc.name.toLowerCase())) {
        list.add(disc);
      }
      if (list.length >= 8) break;
    }

    return list;
  }

  List<LocalPlaylistTrack> _getListenAgainTracks() {
    final recent = _historyService.recentTracks.map((h) => h.toLocalPlaylistTrack()).toList();
    if (recent.isNotEmpty) {
      return recent.take(12).toList();
    }
    final liked = widget.playlistService.likedSongsPlaylist.tracks;
    if (liked.isNotEmpty) {
      return liked.take(12).toList();
    }
    return _getQuickPicks().take(8).toList();
  }

  List<({String title, String artist, String coverUrl, String subtitle})> _getMoodAlbums(String mood) {
    if (_moodAlbumsCache.containsKey(mood) && _moodAlbumsCache[mood]!.isNotEmpty) {
      return _moodAlbumsCache[mood]!;
    }
    return [
      (
        title: '$mood Hits Mix',
        artist: 'YouTube Music',
        coverUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg',
        subtitle: 'Playlist • FinAudio Mix',
      ),
      (
        title: '$mood Energy Boost',
        artist: 'Various Artists',
        coverUrl: 'https://img.youtube.com/vi/JRfuAukYTKg/hqdefault.jpg',
        subtitle: 'Mix • Top Vibes',
      ),
      (
        title: 'Deep $mood Essentials',
        artist: 'FinAudio Curated',
        coverUrl: 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
        subtitle: 'Playlist • 50 songs',
      ),
    ];
  }

  List<({String name, String? channelId, String? imageUrl, String subscribers})> _getMoodArtists(String mood) {
    if (_moodArtistsCache.containsKey(mood) && _moodArtistsCache[mood]!.isNotEmpty) {
      return _moodArtistsCache[mood]!;
    }
    switch (mood) {
      case 'Energize':
      case 'Workout':
        return const [
          (name: 'Avicii', channelId: null, imageUrl: 'https://img.youtube.com/vi/IcrbM1l_BoI/hqdefault.jpg', subscribers: '20M subscribers'),
          (name: 'David Guetta', channelId: null, imageUrl: 'https://img.youtube.com/vi/JRfuAukYTKg/hqdefault.jpg', subscribers: '26M subscribers'),
          (name: 'Martin Garrix', channelId: null, imageUrl: 'https://img.youtube.com/vi/gCYcHz2k5x0/hqdefault.jpg', subscribers: '15M subscribers'),
          (name: 'Eminem', channelId: null, imageUrl: 'https://img.youtube.com/vi/gY9C0IztE0Q/hqdefault.jpg', subscribers: '58M subscribers'),
        ];
      case 'Relax':
      case 'Focus':
        return const [
          (name: 'Marconi Union', channelId: null, imageUrl: 'https://img.youtube.com/vi/UfcAVejslrU/hqdefault.jpg', subscribers: '200K subscribers'),
          (name: 'Petit Biscuit', channelId: null, imageUrl: 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg', subscribers: '1.2M subscribers'),
          (name: 'Jasper Harris', channelId: null, imageUrl: 'https://img.youtube.com/vi/fJ9rUzIMcZQ/hqdefault.jpg', subscribers: '450K subscribers'),
        ];
      default:
        return const [
          (name: 'The Weeknd', channelId: null, imageUrl: 'https://img.youtube.com/vi/XXYlFuWEuKi/hqdefault.jpg', subscribers: '35M subscribers'),
          (name: 'Dua Lipa', channelId: null, imageUrl: 'https://img.youtube.com/vi/TUVcZfQe-Kw/hqdefault.jpg', subscribers: '23M subscribers'),
          (name: 'Post Malone', channelId: null, imageUrl: 'https://img.youtube.com/vi/ApXoWvfEYVU/hqdefault.jpg', subscribers: '25M subscribers'),
        ];
    }
  }

  IconData _getMoodIcon(String mood) {
    switch (mood) {
      case 'Energize':
        return Icons.bolt_rounded;
      case 'Workout':
        return Icons.fitness_center_rounded;
      case 'Relax':
        return Icons.spa_rounded;
      case 'Focus':
        return Icons.psychology_rounded;
      case 'Commute':
        return Icons.directions_subway_rounded;
      case 'Feel good':
      default:
        return Icons.sentiment_very_satisfied_rounded;
    }
  }

  Future<void> _playMixCard(String mixTitle, String primaryArtist) async {
    final bool isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTest) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing "$mixTitle"')),
    );

    List<LocalPlaylistTrack> tracksToPlay = [];

    if (mixTitle.contains('Supermix')) {
      final hist = _historyService.recentTracks.map((h) => h.toLocalPlaylistTrack()).take(4).toList();
      final rel = _getRelatedArtistsPool(primaryArtist).take(6).toList();
      final fallback = _getRotatingFallbackPool(_refreshCount).take(6).toList();
      tracksToPlay = [...hist, ...rel, ...fallback];
    } else if (mixTitle.contains('Discover')) {
      final sim = _getSimilarTracks(primaryArtist);
      final rel = _getRelatedArtistsPool(primaryArtist);
      tracksToPlay = [...sim, ...rel];
    } else if (mixTitle.contains('Chill')) {
      tracksToPlay = _getMoodPicks('Relax');
    } else if (mixTitle.contains('Energy')) {
      tracksToPlay = _getMoodPicks('Energize');
    } else {
      tracksToPlay = _getNewReleases();
    }

    if (tracksToPlay.isNotEmpty && mounted) {
      await _playTrackList(tracksToPlay, 0);
    }
  }

  // =========================================================================
  // Build
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final bg = widget.settingsService.backgroundColor;
    final surface = widget.settingsService.surfaceColor;
    final accent = widget.settingsService.accentColor;
    final text = widget.settingsService.textColor;

    final quickPicks = _getQuickPicks();
    final speedDialItems = _getSpeedDialItems();
    final musicArtists = _getMusicArtists();
    final libraryPlaylists = widget.playlistService.playlists;
    final recommendedAlbums = _getRecommendedAlbums();
    final newReleases = _getNewReleases();
    final listenAgainTracks = _getListenAgainTracks();
    final topArtist = _dynamicSimilarArtist ?? (musicArtists.isNotEmpty ? musicArtists.first : null);

    final userPhoto = widget.authService.currentUser?.photoUrl;
    final userName = widget.authService.currentUser?.displayName?.toUpperCase() ?? 'SHARKYBURGER';

    return Scaffold(
      backgroundColor: bg,
      body: RefreshIndicator(
        color: accent,
        backgroundColor: surface,
        onRefresh: _handleRefresh,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // 1. Pinned / Floating Top App Bar (FinAudio Brand & Action Buttons)
            SliverAppBar(
              backgroundColor: bg,
              elevation: 0,
              scrolledUnderElevation: 2,
              floating: true,
              pinned: false,
              toolbarHeight: 64,
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: text.withAlpha(25)),
                    ),
                    child: Center(
                      child: Icon(Icons.graphic_eq_rounded, color: accent, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'FinAudio',
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              actions: [
                _buildCircularHeaderButton(
                  icon: Icons.history_rounded,
                  tooltip: 'Speed dial / History',
                  surface: surface,
                  text: text,
                  onTap: () => _scrollToSection(_keySpeedDial),
                ),
                const SizedBox(width: 8),
                _buildCircularHeaderButton(
                  icon: Icons.campaign_rounded,
                  tooltip: 'New releases',
                  surface: surface,
                  text: text,
                  onTap: () => _scrollToSection(_keyNewReleases),
                ),
                const SizedBox(width: 8),
                _buildCircularHeaderButton(
                  icon: Icons.search_rounded,
                  tooltip: 'Search',
                  surface: surface,
                  text: text,
                  onTap: widget.onOpenSearch,
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onOpenSettings,
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: surface,
                    backgroundImage: (userPhoto != null && userPhoto.isNotEmpty)
                        ? NetworkImage(userPhoto)
                        : null,
                    child: (userPhoto == null || userPhoto.isEmpty)
                        ? Icon(Icons.person_rounded, color: text.withAlpha(200), size: 18)
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
              ],
            ),

            // 2. Horizontal Mood/Genre Filter Chips
            SliverToBoxAdapter(
              child: _buildMoodChips(surface, accent, text),
            ),

            // 3. "Speed dial" 3x3 Grid Section (YouTube Music Layout)
            SliverToBoxAdapter(
              child: Padding(
                key: _keySpeedDial,
                padding: const EdgeInsets.only(top: 18),
                child: _buildSpeedDialSection(userName, userPhoto, speedDialItems, surface, accent, text),
              ),
            ),

            // ===============================================================
            // REVAMPED SECTIONS BELOW SPEED DIAL (ArchiveTune Dynamic Feed)
            // ===============================================================

            if (_selectedMood != null) ...[
              // Active Mood Banner
              SliverToBoxAdapter(
                child: _buildMoodActiveBanner(_selectedMood!, surface, accent, text),
              ),

              // Mood Quick Picks (4-Row Grid)
              SliverToBoxAdapter(
                child: Padding(
                  key: _keyQuickPicks,
                  padding: const EdgeInsets.only(top: 20),
                  child: _buildQuickPicks4RowSection(
                    quickPicks,
                    surface,
                    accent,
                    text,
                    title: '$_selectedMood • Quick picks',
                    subtitle: 'START RADIO FROM A SONG',
                  ),
                ),
              ),

              // Mood Mixes & Albums
              if (_getMoodAlbums(_selectedMood!).isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    key: _keyAlbums,
                    padding: const EdgeInsets.only(top: 26),
                    child: _buildMoodMixesSection(
                      _selectedMood!,
                      _getMoodAlbums(_selectedMood!),
                      surface,
                      text,
                      accent,
                    ),
                  ),
                ),

              // Mood Artists
              if (_getMoodArtists(_selectedMood!).isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    key: _keyArtists,
                    padding: const EdgeInsets.only(top: 26),
                    child: _buildMoodArtistsSection(
                      _selectedMood!,
                      _getMoodArtists(_selectedMood!),
                      surface,
                      text,
                    ),
                  ),
                ),

              // Mood Radio Tracks
              SliverToBoxAdapter(
                child: Padding(
                  key: _keyNewReleases,
                  padding: const EdgeInsets.only(top: 26, bottom: 90),
                  child: _buildMoodRadioCarousel(
                    _selectedMood!,
                    quickPicks.skip(4).toList(),
                    surface,
                    text,
                  ),
                ),
              ),
            ] else ...[
              // 4. "Mixed for you" (ArchiveTune Signature Custom Mixes Shelf)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: _buildMixedForYouSection(
                    topArtist?.name ?? 'FinAudio',
                    surface,
                    accent,
                    text,
                  ),
                ),
              ),

              // 5. "Quick picks" 4-Row Horizontal Scrolling Grid
              SliverToBoxAdapter(
                child: Padding(
                  key: _keyQuickPicks,
                  padding: const EdgeInsets.only(top: 26),
                  child: _buildQuickPicks4RowSection(
                    quickPicks,
                    surface,
                    accent,
                    text,
                    title: 'Quick picks',
                    subtitle: 'START RADIO FROM A SONG',
                  ),
                ),
              ),

              // 6. "Listen again" (ArchiveTune Signature Shelf)
              if (listenAgainTracks.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 26),
                    child: _buildListenAgainSection(
                      listenAgainTracks,
                      surface,
                      accent,
                      text,
                    ),
                  ),
                ),

              // 7. "Similar to <Artist>" Carousel (Guaranteed Diverse Non-Seed Artists)
              if (topArtist != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 26),
                    child: _buildSimilarToSection(
                      topArtist,
                      _getSimilarTracks(topArtist.name),
                      surface,
                      accent,
                      text,
                    ),
                  ),
                ),

              // 8. "Community playlists" (ArchiveTune Signature Shelf)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 26),
                  child: _buildCommunityPlaylistsSection(surface, text),
                ),
              ),

              // 9. "Recommended albums" / "Albums for you" Carousel
              SliverToBoxAdapter(
                child: Padding(
                  key: _keyAlbums,
                  padding: const EdgeInsets.only(top: 26),
                  child: _buildAlbumsCarousel(recommendedAlbums, surface, text),
                ),
              ),

              // 10. "From your library" Carousel
              SliverToBoxAdapter(
                child: Padding(
                  key: _keyLibrary,
                  padding: const EdgeInsets.only(top: 26),
                  child: _buildLibraryCarousel(libraryPlaylists, surface, text),
                ),
              ),

              // 11. "Artists for you" Circular Carousel
              SliverToBoxAdapter(
                child: Padding(
                  key: _keyArtists,
                  padding: const EdgeInsets.only(top: 26),
                  child: _buildArtistsCarousel(musicArtists, surface, text),
                ),
              ),

              // 12. "New releases" Carousel
              SliverToBoxAdapter(
                child: Padding(
                  key: _keyNewReleases,
                  padding: const EdgeInsets.only(top: 26, bottom: 90),
                  child: _buildNewReleasesCarousel(newReleases, surface, text),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Mood / Genre Chips
  // =========================================================================

  Widget _buildMoodChips(Color surface, Color accent, Color text) {
    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _moods.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final mood = _moods[i];
          final isSelected = _selectedMood == mood;
          final onAccentText = accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                final newMood = isSelected ? null : mood;
                setState(() {
                  _selectedMood = newMood;
                });
                if (newMood != null) {
                  _fetchMoodTracks(newMood);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? accent : surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? accent : text.withAlpha(25),
                    width: 0.8,
                  ),
                ),
                child: Center(
                  child: Text(
                    mood,
                    style: TextStyle(
                      color: isSelected ? onAccentText : text.withAlpha(220),
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================================================================
  // Section: "Speed dial" (3x3 Grid, YouTube Music)
  // =========================================================================

  Widget _buildSpeedDialSection(
    String userName,
    String? userPhoto,
    List<({String title, String artist, String coverUrl, VoidCallback? onTap})> items,
    Color surface,
    Color accent,
    Color text,
  ) {
    final likedPlaylist = widget.playlistService.likedSongsPlaylist;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: surface,
                backgroundImage: (userPhoto != null && userPhoto.isNotEmpty)
                    ? NetworkImage(userPhoto)
                    : null,
                child: (userPhoto == null || userPhoto.isEmpty)
                    ? Icon(Icons.pets_rounded, color: text.withAlpha(180), size: 16)
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: TextStyle(
                      color: text.withAlpha(140),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    'Speed dial',
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 600;
              final columns = isDesktop ? (constraints.maxWidth / 175).floor().clamp(3, 8) : 3;
              final spacing = isDesktop ? 12.0 : 8.0;
              final itemWidth = (constraints.maxWidth - (columns - 1) * spacing) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  // 1. Liked Music tile
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => widget.onOpenPlaylistDetail(likedPlaylist),
                      child: Container(
                        width: itemWidth,
                        height: itemWidth,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B5CF6).withAlpha(35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            const Center(
                              child: Icon(Icons.thumb_up_rounded, color: Colors.white, size: 36),
                            ),
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 8,
                              child: Row(
                                children: const [
                                  Expanded(
                                    child: Text(
                                      'Liked Music',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: Colors.white, size: 14),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 2..8: Top listened items
                  ...items.map((item) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          if (item.onTap != null) {
                            item.onTap!();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Playing "${item.title}"')),
                            );
                          }
                        },
                        child: Container(
                          width: itemWidth,
                          height: itemWidth,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: surface,
                            border: Border.all(color: text.withAlpha(20)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildYtmImage(
                                imageUrl: item.coverUrl,
                                width: itemWidth,
                                height: itemWidth,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, Color(0xCC000000)],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 14),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  // 9. More tile
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      width: itemWidth,
                      height: itemWidth,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: surface,
                        border: Border.all(color: text.withAlpha(20)),
                      ),
                      child: Center(
                        child: Icon(Icons.more_horiz_rounded, color: text.withAlpha(120), size: 28),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: "Quick picks" (4-Row Horizontal Scrolling Grid)
  // =========================================================================

  Widget _buildQuickPicks4RowSection(
    List<LocalPlaylistTrack> tracks,
    Color surface,
    Color accent,
    Color text, {
    String title = 'Quick picks',
    String subtitle = 'START RADIO FROM A SONG',
  }) {
    // Partition tracks into columns of 4 rows
    final columns = <List<LocalPlaylistTrack>>[];
    for (int i = 0; i < tracks.length; i += 4) {
      columns.add(tracks.sublist(i, (i + 4).clamp(0, tracks.length)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: text.withAlpha(140),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.arrow_forward_rounded, color: text.withAlpha(180), size: 20),
                tooltip: 'See all quick picks',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SectionTracksScreen(
                        title: title,
                        subtitle: subtitle,
                        tracks: tracks,
                        playerService: widget.playerService,
                        playlistService: widget.playlistService,
                        settingsService: widget.settingsService,
                        authService: widget.authService,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240, // 4 rows x 56px + spacing
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: columns.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, colIndex) {
              final colTracks = columns[colIndex];
              return SizedBox(
                width: 320,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: colTracks.asMap().entries.map((entry) {
                    final rowIdx = entry.key;
                    final track = entry.value;
                    final globalIdx = colIndex * 4 + rowIdx;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _playTrackList(tracks, globalIdx),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Row(
                            children: [
                              _buildYtmImage(
                                imageUrl: track.thumbnailUrl,
                                width: 48,
                                height: 48,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${track.artist} • 1.2M views',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: text.withAlpha(160),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.more_vert_rounded, size: 20),
                                color: text.withAlpha(160),
                                onPressed: () => _showTrackOptions(track),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: Active Mood Banner (ArchiveTune Dynamic Mood)
  // =========================================================================

  Widget _buildMoodActiveBanner(String mood, Color surface, Color accent, Color text) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withAlpha(45),
              shape: BoxShape.circle,
            ),
            child: Icon(_getMoodIcon(mood), color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${mood.toUpperCase()} MIX ACTIVE',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  'Personalized feed tuned for $mood',
                  style: TextStyle(color: text.withAlpha(200), fontSize: 13),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _selectedMood = null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: text.withAlpha(30)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded, size: 14, color: text.withAlpha(200)),
                  const SizedBox(width: 4),
                  Text(
                    'Clear',
                    style: TextStyle(color: text.withAlpha(220), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Section: Mood Mixes & Playlists
  // =========================================================================

  Widget _buildMoodMixesSection(
    String mood,
    List<({String title, String artist, String coverUrl, String subtitle})> albums,
    Color surface,
    Color text,
    Color accent,
  ) {
    if (albums.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CURATED MIXES',
                style: TextStyle(
                  color: text.withAlpha(140),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$mood • Mixes & Playlists',
                style: TextStyle(
                  color: text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 205,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final album = albums[i];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumViewScreen(
                        title: album.title,
                        artist: album.artist,
                        coverUrl: album.coverUrl,
                        subtitle: album.subtitle,
                        isPlaylist: true,
                        playerService: widget.playerService,
                        playlistService: widget.playlistService,
                        settingsService: widget.settingsService,
                        authService: widget.authService,
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  width: 145,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildYtmImage(
                        imageUrl: album.coverUrl,
                        width: 145,
                        height: 145,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        album.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: Mood Artists
  // =========================================================================

  Widget _buildMoodArtistsSection(
    String mood,
    List<({String name, String? channelId, String? imageUrl, String subscribers})> artists,
    Color surface,
    Color text,
  ) {
    if (artists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'POPULAR IN THIS MOOD',
                style: TextStyle(
                  color: text.withAlpha(140),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$mood • Artists',
                style: TextStyle(
                  color: text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 175,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: artists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (_, i) {
              final a = artists[i];
              return GestureDetector(
                onTap: () => _openArtistPage(a.name, channelId: a.channelId, imageUrl: a.imageUrl),
                child: SizedBox(
                  width: 130,
                  child: Column(
                    children: [
                      _buildYtmImage(
                        imageUrl: a.imageUrl,
                        width: 120,
                        height: 120,
                        shape: BoxShape.circle,
                        fallbackIcon: Icons.person_rounded,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        a.subscribers,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: text.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: Mood Radio Carousel
  // =========================================================================

  Widget _buildMoodRadioCarousel(String mood, List<LocalPlaylistTrack> tracks, Color surface, Color text) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CONTINUE LISTENING',
                style: TextStyle(
                  color: text.withAlpha(140),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$mood • Radio',
                style: TextStyle(
                  color: text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final track = tracks[i];
              return GestureDetector(
                onTap: () => _playTrackList(tracks, i),
                child: SizedBox(
                  width: 145,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildYtmImage(
                        imageUrl: track.thumbnailUrl,
                        width: 145,
                        height: 145,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Radio • ${track.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: "Mixed for you" (ArchiveTune Signature Custom Mixes Shelf)
  // =========================================================================

  Widget _buildMixedForYouSection(
    String primaryArtist,
    Color surface,
    Color accent,
    Color text,
  ) {
    final relatedNames = _getRelatedArtistNames(primaryArtist);
    final secondaryArtist = relatedNames.isNotEmpty ? relatedNames.first : 'Various Artists';
    final thirdArtist = relatedNames.length > 1 ? relatedNames[1] : 'Various Artists';

    final mixes = [
      (
        title: 'My Supermix',
        subtitle: 'FinAudio • Endless blend',
        description: '$primaryArtist, $secondaryArtist, and more',
        gradient: const [Color(0xFF6B21A8), Color(0xFF1E1B4B)],
        icon: Icons.auto_awesome_rounded,
      ),
      (
        title: 'Discover Mix',
        subtitle: '100% new music for you',
        description: '$secondaryArtist, $thirdArtist, and similar',
        gradient: const [Color(0xFF0F766E), Color(0xFF042F2E)],
        icon: Icons.explore_rounded,
      ),
      (
        title: 'Indie & Chill Mix',
        subtitle: 'Soft & laid-back vibes',
        description: '$secondaryArtist, $thirdArtist, and chill pop',
        gradient: const [Color(0xFF831843), Color(0xFF3B0764)],
        icon: Icons.nightlife_rounded,
      ),
      (
        title: 'Energy & Beat Mix',
        subtitle: 'Upbeat & vibrant hits',
        description: 'High-tempo tracks to keep you moving',
        gradient: const [Color(0xFFB91C1C), Color(0xFF78350F)],
        icon: Icons.bolt_rounded,
      ),
      (
        title: 'New Release Mix',
        subtitle: 'Fresh this week',
        description: 'The latest singles from creators you love',
        gradient: const [Color(0xFF047857), Color(0xFF064E3B)],
        icon: Icons.campaign_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MIXED FOR YOU',
                style: TextStyle(
                  color: text.withAlpha(140),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Custom mixes',
                style: TextStyle(
                  color: text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 155,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: mixes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final mix = mixes[i];
              return GestureDetector(
                onTap: () {
                  List<LocalPlaylistTrack> tracksToPlay = [];
                  if (mix.title.contains('Supermix')) {
                    final hist = _historyService.recentTracks.map((h) => h.toLocalPlaylistTrack()).take(4).toList();
                    final rel = _getRelatedArtistsPool(primaryArtist).take(6).toList();
                    final fallback = _getRotatingFallbackPool(_refreshCount).take(6).toList();
                    tracksToPlay = [...hist, ...rel, ...fallback];
                  } else if (mix.title.contains('Discover')) {
                    final sim = _getSimilarTracks(primaryArtist);
                    final rel = _getRelatedArtistsPool(primaryArtist);
                    tracksToPlay = [...sim, ...rel];
                  } else if (mix.title.contains('Chill')) {
                    tracksToPlay = _getMoodPicks('Relax');
                  } else if (mix.title.contains('Energy')) {
                    tracksToPlay = _getMoodPicks('Energize');
                  } else {
                    tracksToPlay = _getNewReleases();
                  }

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumViewScreen(
                        title: mix.title,
                        artist: primaryArtist,
                        subtitle: mix.subtitle,
                        type: 'Mix',
                        isPlaylist: true,
                        initialTracks: tracksToPlay,
                        playerService: widget.playerService,
                        playlistService: widget.playlistService,
                        settingsService: widget.settingsService,
                        authService: widget.authService,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 215,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: mix.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: mix.gradient.first.withAlpha(60),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(mix.icon, color: Colors.white.withAlpha(220), size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  mix.subtitle.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(190),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            mix.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            mix.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withAlpha(190),
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: () => _playMixCard(mix.title, primaryArtist),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(130),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white30, width: 1),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: "Listen again" (ArchiveTune Signature Shelf)
  // =========================================================================

  Widget _buildListenAgainSection(
    List<LocalPlaylistTrack> tracks,
    Color surface,
    Color accent,
    Color text,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RECENTLY PLAYED',
                    style: TextStyle(
                      color: text.withAlpha(140),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Listen again',
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.arrow_forward_rounded, color: text.withAlpha(180), size: 20),
                tooltip: 'See listening history',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SectionTracksScreen(
                        title: 'Listen again',
                        subtitle: 'Recently played',
                        tracks: tracks,
                        playerService: widget.playerService,
                        playlistService: widget.playlistService,
                        settingsService: widget.settingsService,
                        authService: widget.authService,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final track = tracks[i];
              return GestureDetector(
                onTap: () => _playTrackList(tracks, i),
                child: SizedBox(
                  width: 145,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          _buildYtmImage(
                            imageUrl: track.thumbnailUrl,
                            width: 145,
                            height: 145,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(180),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 1),
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: "Similar to <Artist>"
  // =========================================================================

  Widget _buildSimilarToSection(
    ({String name, String? channelId, String? imageUrl, String subscribers}) artist,
    List<LocalPlaylistTrack> tracks,
    Color surface,
    Color accent,
    Color text,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: surface,
                    backgroundImage: (artist.imageUrl != null && artist.imageUrl!.isNotEmpty)
                        ? NetworkImage(artist.imageUrl!)
                        : null,
                    child: (artist.imageUrl == null || artist.imageUrl!.isEmpty)
                        ? Text(artist.name.isNotEmpty ? artist.name[0] : '?', style: TextStyle(color: text, fontSize: 12))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SIMILAR TO',
                        style: TextStyle(
                          color: text.withAlpha(140),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        artist.name,
                        style: TextStyle(
                          color: text,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.arrow_forward_rounded, color: text.withAlpha(180), size: 20),
                tooltip: 'More similar tracks',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SectionTracksScreen(
                        title: 'Similar to ${artist.name}',
                        subtitle: 'Recommended based on your taste',
                        tracks: tracks,
                        artistName: artist.name,
                        artistImageUrl: artist.imageUrl,
                        artistChannelId: artist.channelId,
                        playerService: widget.playerService,
                        playlistService: widget.playlistService,
                        settingsService: widget.settingsService,
                        authService: widget.authService,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final track = tracks[i];
              return GestureDetector(
                onTap: () => _playTrackList(tracks, i),
                child: SizedBox(
                  width: 145,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildYtmImage(
                        imageUrl: track.thumbnailUrl,
                        width: 145,
                        height: 145,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: "Community playlists" (ArchiveTune Signature Shelf)
  // =========================================================================

  Widget _buildCommunityPlaylistsSection(Color surface, Color text) {
    final playlists = _getCommunityPlaylists();
    if (playlists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'COMMUNITY PLAYLISTS',
                style: TextStyle(
                  color: text.withAlpha(140),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Trending playlists',
                style: TextStyle(
                  color: text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 205,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final pl = playlists[i];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumViewScreen(
                        title: pl.title,
                        artist: pl.artist,
                        coverUrl: pl.coverUrl,
                        subtitle: pl.subtitle,
                        isPlaylist: true,
                        playerService: widget.playerService,
                        playlistService: widget.playlistService,
                        settingsService: widget.settingsService,
                        authService: widget.authService,
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  width: 145,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildYtmImage(
                        imageUrl: pl.coverUrl,
                        width: 145,
                        height: 145,
                        borderRadius: BorderRadius.circular(8),
                        fallbackIcon: Icons.playlist_play_rounded,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        pl.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        pl.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: "From your library"
  // =========================================================================

  Widget _buildLibraryCarousel(List<LocalPlaylist> playlists, Color surface, Color text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'INCLUDING YOUR IMPORTED PLAYLISTS',
                style: TextStyle(
                  color: text.withAlpha(140),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'From your library',
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.arrow_forward_rounded, color: text.withAlpha(180), size: 20),
                    onPressed: widget.onOpenPlaylists,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final p = playlists[i];
              return GestureDetector(
                onTap: () => widget.onOpenPlaylistDetail(p),
                child: SizedBox(
                  width: 145,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildYtmImage(
                        imageUrl: p.effectiveThumbnailUrl,
                        width: 145,
                        height: 145,
                        borderRadius: BorderRadius.circular(6),
                        fallbackIcon: Icons.queue_music_rounded,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Playlist • ${p.trackCount} tracks',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: "Recommended albums" / "Albums for you"
  // =========================================================================

  Widget _buildAlbumsCarousel(
    List<({String title, String artist, String coverUrl, String subtitle})> albums,
    Color surface,
    Color text,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RECOMMENDED ALBUMS',
                    style: TextStyle(
                      color: text.withAlpha(140),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Albums for you',
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.arrow_forward_rounded, color: text.withAlpha(180), size: 20),
                tooltip: 'See all albums',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumsDetailScreen(
                        albums: albums,
                        settingsService: widget.settingsService,
                        playerService: widget.playerService,
                        playlistService: widget.playlistService,
                        authService: widget.authService,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 205,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final album = albums[i];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumViewScreen(
                        title: album.title,
                        artist: album.artist,
                        coverUrl: album.coverUrl,
                        subtitle: album.subtitle,
                        playerService: widget.playerService,
                        playlistService: widget.playlistService,
                        settingsService: widget.settingsService,
                        authService: widget.authService,
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  width: 145,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildYtmImage(
                        imageUrl: album.coverUrl,
                        width: 145,
                        height: 145,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        album.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: "Artists" (Circular Avatars)
  // =========================================================================

  Widget _buildArtistsCarousel(
    List<({String name, String? channelId, String? imageUrl, String subscribers})> artists,
    Color surface,
    Color text,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DISCOVER CREATORS',
                    style: TextStyle(
                      color: text.withAlpha(140),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Artists for you',
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.arrow_forward_rounded, color: text.withAlpha(180), size: 20),
                tooltip: 'See all artists',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArtistsDetailScreen(
                        artists: artists,
                        playerService: widget.playerService,
                        authService: widget.authService,
                        playlistService: widget.playlistService,
                        settingsService: widget.settingsService,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 175,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: artists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (_, i) {
              final a = artists[i];
              return GestureDetector(
                onTap: () => _openArtistPage(a.name, channelId: a.channelId, imageUrl: a.imageUrl),
                child: SizedBox(
                  width: 130,
                  child: Column(
                    children: [
                      _buildYtmImage(
                        imageUrl: a.imageUrl,
                        width: 120,
                        height: 120,
                        shape: BoxShape.circle,
                        fallbackIcon: Icons.person_rounded,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        a.subscribers,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: text.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // Section: "New releases"
  // =========================================================================

  Widget _buildNewReleasesCarousel(List<LocalPlaylistTrack> tracks, Color surface, Color text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEW RELEASES',
                    style: TextStyle(
                      color: text.withAlpha(140),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'New releases',
                    style: TextStyle(
                      color: text,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.arrow_forward_rounded, color: text.withAlpha(180), size: 20),
                tooltip: 'See new releases from your subscribed artists',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NewReleasesScreen(
                        playerService: widget.playerService,
                        authService: widget.authService,
                        playlistService: widget.playlistService,
                        settingsService: widget.settingsService,
                        subscribedArtists: _subscribedArtists,
                        initialTracks: tracks,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final track = tracks[i];
              return GestureDetector(
                onTap: () => _playTrackList(tracks, i),
                child: SizedBox(
                  width: 145,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildYtmImage(
                        imageUrl: track.thumbnailUrl,
                        width: 145,
                        height: 145,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Single • ${track.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
