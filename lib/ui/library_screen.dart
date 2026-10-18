import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finaudio/models/local_playlist.dart';
import 'package:finaudio/services/google_auth_service.dart';
import 'package:finaudio/services/history_service.dart';
import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/playlist_service.dart';
import 'package:finaudio/services/settings_service.dart';
import 'package:finaudio/services/spotify_service.dart';
import 'package:finaudio/services/download_service.dart';
import 'package:finaudio/ui/artist_screen.dart';
import 'package:finaudio/ui/cached_screen.dart';
import 'package:finaudio/ui/downloads_screen.dart';
import 'package:finaudio/widgets/add_to_playlist_sheet.dart';

/// Full-featured, modern Library Tab matching streaming app standards:
/// Top sorting/category pills:
/// 1. Library (Quick cards: Liked songs, Offline, Cached, Local Files, My top 50, + Recent Playlists)
/// 2. Playlists (User playlists, Spotify sync, New playlist, YouTube playlists)
/// 3. Songs (All consolidated library tracks with search, sort, Play All, Shuffle)
/// 4. Artists (Grouped by artist with artist avatars, discographies, tap-to-play)
/// 5. Albums (Album cards with vinyl sleeve disc peek effect and tap-to-play)
class LibraryTab extends StatefulWidget {
  final PlayerService playerService;
  final GoogleAuthService authService;
  final PlaylistService playlistService;
  final SettingsService settingsService;
  final VoidCallback onGoToSettings;
  final VoidCallback? onGoToPlayer;
  final void Function(LocalPlaylist playlist)? onOpenPlaylistDetail;
  final void Function(UserPlaylist playlist)? onOpenYtPlaylistDetail;

  const LibraryTab({
    super.key,
    required this.playerService,
    required this.authService,
    required this.playlistService,
    required this.settingsService,
    required this.onGoToSettings,
    this.onGoToPlayer,
    this.onOpenPlaylistDetail,
    this.onOpenYtPlaylistDetail,
  });

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> with SingleTickerProviderStateMixin {
  // Active pill index: 0: Library, 1: Playlists, 2: Songs, 3: Artists, 4: Albums
  int _selectedPill = 0;
  late final PageController _pageController;

  // Playlists sub-view state
  String? _syncingPlaylistId;
  String _playlistsSearchQuery = '';

  // YouTube account playlists
  List<UserPlaylist> _ytPlaylists = [];
  bool _loadingYtPlaylists = false;
  String? _ytPlaylistsError;

  // Subscribed YouTube artists
  List<SubscribedArtist> _subscribedArtists = [];
  bool _loadingArtists = false;
  String? _artistsError;

  // Songs sub-view state
  String _songsSearchQuery = '';
  String _songsSortBy = 'title_asc'; // title_asc, title_desc, artist_asc, duration_desc, duration_asc

  // Artists sub-view state
  String _artistsSearchQuery = '';

  // Albums sub-view state
  String _albumsSearchQuery = '';

  final ScrollController _pillScrollController = ScrollController();

  final List<({String label, IconData icon})> _pills = const [
    (label: 'Library', icon: Icons.graphic_eq_rounded),
    (label: 'Playlists', icon: Icons.format_list_bulleted_rounded),
    (label: 'Songs', icon: Icons.music_note_rounded),
    (label: 'Artists', icon: Icons.person_rounded),
    (label: 'Albums', icon: Icons.album_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedPill);
    widget.playlistService.addListener(_onStateUpdate);
    widget.authService.addListener(_onAuthChanged);
    HistoryService.instance.addListener(_onStateUpdate);
    DownloadService.instance.addListener(_onStateUpdate);
    if (widget.authService.isAuthenticated) {
      _loadYtPlaylists();
      _loadSubscribedArtists();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    widget.playlistService.removeListener(_onStateUpdate);
    widget.authService.removeListener(_onAuthChanged);
    HistoryService.instance.removeListener(_onStateUpdate);
    DownloadService.instance.removeListener(_onStateUpdate);
    _pillScrollController.dispose();
    super.dispose();
  }

  void _onStateUpdate() {
    if (mounted) setState(() {});
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
    if (widget.authService.isAuthenticated) {
      _loadYtPlaylists();
      _loadSubscribedArtists();
    } else {
      setState(() {
        _ytPlaylists = [];
        _loadingYtPlaylists = false;
        _ytPlaylistsError = null;
        _subscribedArtists = [];
        _loadingArtists = false;
        _artistsError = null;
      });
    }
  }

  Future<void> _loadYtPlaylists() async {
    if (!widget.authService.isAuthenticated) return;
    setState(() {
      _loadingYtPlaylists = true;
      _ytPlaylistsError = null;
    });
    try {
      final playlists = await widget.authService.fetchPlaylists();
      if (!mounted) return;
      setState(() {
        _ytPlaylists = playlists;
        _loadingYtPlaylists = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ytPlaylistsError = e.toString();
        _loadingYtPlaylists = false;
      });
    }
  }

  Future<void> _loadSubscribedArtists({bool forceRefresh = false}) async {
    if (!widget.authService.isAuthenticated) return;
    setState(() {
      _loadingArtists = true;
      _artistsError = null;
    });
    try {
      final artists = await widget.authService.fetchSubscribedArtists(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _subscribedArtists = artists;
        _loadingArtists = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _artistsError = e.toString();
        _loadingArtists = false;
      });
    }
  }

  void _scrollToPill(int index) {
    if (!_pillScrollController.hasClients) return;
    const itemWidth = 110.0;
    final targetOffset = (index * itemWidth) - 40;
    _pillScrollController.animateTo(
      targetOffset.clamp(0.0, _pillScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _syncLocalPlaylist(LocalPlaylist playlist) async {
    if (!playlist.isSpotify) return;
    setState(() => _syncingPlaylistId = playlist.id);
    try {
      final updated = await widget.playlistService.syncSpotifyPlaylist(
        playlist.id,
        clientId: widget.settingsService.spotifyClientId,
        clientSecret: widget.settingsService.spotifyClientSecret,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced "${updated.title}" (${updated.trackCount} songs)'),
          backgroundColor: const Color(0xFF1DB954),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _syncingPlaylistId = null);
      }
    }
  }

  /// Extracts all unique songs across all playlists and history.
  List<LocalPlaylistTrack> _getAllUniqueSongs() {
    final Map<String, LocalPlaylistTrack> songMap = {};

    // 1. Local and imported playlists
    for (final p in widget.playlistService.playlists) {
      for (final t in p.tracks) {
        final key = '${t.title.trim().toLowerCase()}|${t.artist.trim().toLowerCase()}';
        if (!songMap.containsKey(key)) {
          songMap[key] = t;
        }
      }
    }

    // 2. Playback history
    for (final h in HistoryService.instance.items) {
      final key = '${h.title.trim().toLowerCase()}|${h.artist.trim().toLowerCase()}';
      if (!songMap.containsKey(key)) {
        songMap[key] = h.toLocalPlaylistTrack();
      }
    }

    return songMap.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.settingsService.accentColor;
    final bg = widget.settingsService.backgroundColor;
    final surface = widget.settingsService.surfaceColor;
    final text = widget.settingsService.textColor;
    final isDark = theme.brightness == Brightness.dark;
    final pillActiveTextColor = isDark ? const Color(0xFF14130A) : Colors.black;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Pill Bar
            _buildTopPillBar(accent, surface, text, pillActiveTextColor),

            // Main Content Area based on selected pill (Swipeable PageView)
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _selectedPill = index);
                  _scrollToPill(index);
                },
                children: [
                  _buildLibraryView(accent, surface, text),
                  _buildPlaylistsView(accent, surface, text),
                  _buildSongsView(accent, surface, text),
                  _buildArtistsView(accent, surface, text),
                  _buildAlbumsView(accent, surface, text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================================================================
  // Top Pill Bar
  // ======================================================================

  Widget _buildTopPillBar(
    Color accent,
    Color surface,
    Color text,
    Color pillActiveTextColor,
  ) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        controller: _pillScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _pills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final pill = _pills[index];
          final isSelected = _selectedPill == index;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                setState(() => _selectedPill = index);
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
                _scrollToPill(index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? accent : surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isSelected ? accent : text.withAlpha(20),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      pill.icon,
                      size: 16,
                      color: isSelected ? pillActiveTextColor : text.withAlpha(200),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      pill.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? pillActiveTextColor : text.withAlpha(220),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ======================================================================
  // View 0: Library Hub (Matches the User's Screenshot)
  // ======================================================================

  Widget _buildLibraryView(Color accent, Color surface, Color text) {
    final likedPlaylist = widget.playlistService.likedSongsPlaylist;
    final likedTrackCount = '${likedPlaylist.trackCount} tracks';
    final playlists = widget.playlistService.playlists;

    return CustomScrollView(
      slivers: [
        // Responsive Grid of rounded cards (Liked songs, Offline, Cached, Local Files, My top 50)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.crossAxisExtent >= 600;
              final crossAxisCount = isDesktop ? (constraints.crossAxisExtent / 220).floor().clamp(3, 6) : 2;
              final childAspectRatio = isDesktop ? 2.5 : 1.35;
              return SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: childAspectRatio,
                ),
                delegate: SliverChildListDelegate([
                  // 1. Liked songs
                  _buildLibraryGridCard(
                    icon: Icons.favorite_rounded,
                    iconColor: const Color(0xFFFF5252),
                    iconBgColor: const Color(0xFFFF5252).withAlpha(35),
                    title: 'Liked songs',
                    subtitle: likedTrackCount,
                    surface: surface,
                    text: text,
                    isDesktop: isDesktop,
                    onTap: () {
                      widget.onOpenPlaylistDetail?.call(likedPlaylist);
                    },
                  ),

                  // 2. Offline
                  _buildLibraryGridCard(
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: const Color(0xFF00E676),
                    iconBgColor: const Color(0xFF00E676).withAlpha(35),
                    title: 'Offline',
                    subtitle: DownloadService.instance.downloadedCount > 0
                        ? '${DownloadService.instance.downloadedCount} songs'
                        : 'Downloaded',
                    surface: surface,
                    text: text,
                    isDesktop: isDesktop,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DownloadsScreen(
                            playerService: widget.playerService,
                            settingsService: widget.settingsService,
                          ),
                        ),
                      );
                    },
                  ),

                  // 3. Cached
                  _buildLibraryGridCard(
                    icon: Icons.cached_rounded,
                    iconColor: const Color(0xFF00B0FF),
                    iconBgColor: const Color(0xFF00B0FF).withAlpha(35),
                    title: 'Cached',
                    subtitle: HistoryService.instance.items.isNotEmpty
                        ? '${HistoryService.instance.items.length} songs'
                        : 'Instant playback',
                    surface: surface,
                    text: text,
                    isDesktop: isDesktop,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CachedScreen(
                            playerService: widget.playerService,
                            playlistService: widget.playlistService,
                            settingsService: widget.settingsService,
                          ),
                        ),
                      );
                    },
                  ),

                  // 4. Local Files
                  _buildLibraryGridCard(
                    icon: Icons.folder_open_rounded,
                    iconColor: const Color(0xFFFF9800),
                    iconBgColor: const Color(0xFFFF9800).withAlpha(35),
                    title: 'Local Files',
                    subtitle: 'On device',
                    surface: surface,
                    text: text,
                    isDesktop: isDesktop,
                    onTap: () => _showLocalFilesSheet(accent, surface, text),
                  ),

                  // 5. My top 50
                  _buildLibraryGridCard(
                    icon: Icons.trending_up_rounded,
                    iconColor: const Color(0xFFAB47BC),
                    iconBgColor: const Color(0xFFAB47BC).withAlpha(35),
                    title: 'My top 50',
                    subtitle: 'All time',
                    surface: surface,
                    text: text,
                    isDesktop: isDesktop,
                    onTap: () => _showTop50Sheet(accent, surface, text),
                  ),
                ]),
              );
            },
          ),
        ),

        // Section: Playlists overview
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Playlists',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: text,
                      ),
                    ),
                    Text(
                      '${playlists.length} collections',
                      style: TextStyle(
                        fontSize: 12,
                        color: text.withAlpha(140),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() => _selectedPill = 1);
                    _pageController.animateToPage(
                      1,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                    _scrollToPill(1);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('See all', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, color: accent, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Playlists Horizontal List or Onboarding
        if (playlists.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: playlists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final p = playlists[index];
                  return GestureDetector(
                    onTap: () => widget.onOpenPlaylistDetail?.call(p),
                    onLongPress: () => _showPlaylistOptionsSheet(p),
                    child: SizedBox(
                      width: 135,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: 135,
                                height: 135,
                                decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: text.withAlpha(20)),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: (p.effectiveThumbnailUrl.isNotEmpty)
                                    ? Image.network(
                                        p.effectiveThumbnailUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Center(
                                          child: Icon(Icons.queue_music, color: accent, size: 36),
                                        ),
                                      )
                                    : Center(
                                        child: Icon(Icons.queue_music, color: accent, size: 36),
                                      ),
                              ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: GestureDetector(
                                  onTap: () {
                                    if (p.tracks.isNotEmpty) {
                                      widget.playerService.playLocalTracks(p.tracks);
                                    }
                                  },
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withAlpha(80),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.play_arrow_rounded, color: Colors.black, size: 22),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: text,
                            ),
                          ),
                          Text(
                            '${p.trackCount} tracks',
                            style: TextStyle(
                              fontSize: 11,
                              color: text.withAlpha(140),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: text.withAlpha(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(40),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add_rounded, color: accent, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Start your collection',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: text,
                            ),
                          ),
                          Text(
                            'Import a Spotify playlist or create your own',
                            style: TextStyle(
                              fontSize: 12,
                              color: text.withAlpha(140),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      onPressed: () => _showImportSpotifyDialog(context),
                      child: const Text('Import', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// Single Library Hub Card (rounded rectangle with circular icon badge).
  Widget _buildLibraryGridCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required Color surface,
    required Color text,
    required VoidCallback onTap,
    bool isDesktop = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 14, vertical: isDesktop ? 12 : 14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: text.withAlpha(20)),
          ),
          child: isDesktop
              ? Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(icon, color: iconColor, size: 22),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: text,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: text.withAlpha(140),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(icon, color: iconColor, size: 20),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: text,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: text.withAlpha(140),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ======================================================================
  // View 1: Playlists
  // ======================================================================

  Widget _buildPlaylistsView(Color accent, Color surface, Color text) {
    final localPlaylists = widget.playlistService.playlists;

    // Filter local user-generated playlists
    final filteredLocal = localPlaylists.where((p) {
      if (_playlistsSearchQuery.isEmpty) return true;
      return p.title.toLowerCase().contains(_playlistsSearchQuery.toLowerCase());
    }).toList();

    // Filter YouTube user-generated playlists
    final filteredYt = _ytPlaylists.where((p) {
      if (_playlistsSearchQuery.isEmpty) return true;
      return p.title.toLowerCase().contains(_playlistsSearchQuery.toLowerCase());
    }).toList();

    final hasAnyPlaylists = filteredLocal.isNotEmpty || filteredYt.isNotEmpty;

    return CustomScrollView(
      slivers: [
        // Action & Search Bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search playlists…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: text.withAlpha(20)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: text.withAlpha(20)),
                      ),
                    ),
                    onChanged: (val) => setState(() => _playlistsSearchQuery = val.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954).withAlpha(40),
                    foregroundColor: const Color(0xFF1DB954),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Import', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _showImportSpotifyDialog(context),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  tooltip: 'New Playlist',
                  onPressed: () => _showCreatePlaylistDialog(context),
                ),
              ],
            ),
          ),
        ),

        // If not authenticated with Google/YouTube, show YouTube account banner
        if (!widget.authService.isAuthenticated && _playlistsSearchQuery.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: text.withAlpha(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0000).withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFFF0000), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('YouTube Playlists', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: text)),
                          Text('Sign in to view your YouTube account playlists', style: TextStyle(fontSize: 11, color: text.withAlpha(140))),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        backgroundColor: const Color(0xFFFF0000).withAlpha(30),
                        foregroundColor: const Color(0xFFFF0000),
                      ),
                      onPressed: () => widget.authService.signIn(),
                      child: const Text('Sign in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Section 1: Your Playlists (Local & Liked Songs)
        if (filteredLocal.isNotEmpty) ...[
          if (widget.authService.isAuthenticated || filteredYt.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Row(
                  children: [
                    Text(
                      'Your Playlists',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${filteredLocal.length})',
                      style: TextStyle(fontSize: 12, color: text.withAlpha(140)),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final p = filteredLocal[index];
                  return _buildLocalPlaylistTile(p, accent, surface, text);
                },
                childCount: filteredLocal.length,
              ),
            ),
          ),
        ],

        // Section 2: YouTube Account Playlists (when signed in)
        if (widget.authService.isAuthenticated) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill_rounded, color: Color(0xFFFF0000), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'YouTube Account Playlists',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: text,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${filteredYt.length})',
                    style: TextStyle(fontSize: 12, color: text.withAlpha(140)),
                  ),
                  const Spacer(),
                  if (_loadingYtPlaylists)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: 'Refresh YouTube playlists',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _loadYtPlaylists,
                    ),
                ],
              ),
            ),
          ),
          if (filteredYt.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 210,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final p = filteredYt[index];
                    return _buildYtPlaylistTile(p, accent, surface, text);
                  },
                  childCount: filteredYt.length,
                ),
              ),
            )
          else if (_ytPlaylistsError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Could not load YouTube playlists: $_ytPlaylistsError',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                    TextButton(onPressed: _loadYtPlaylists, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          else if (!_loadingYtPlaylists)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  _playlistsSearchQuery.isNotEmpty
                      ? 'No YouTube playlists matching "$_playlistsSearchQuery"'
                      : 'No playlists found in your YouTube account.',
                  style: TextStyle(fontSize: 12, color: text.withAlpha(140)),
                ),
              ),
            ),
        ],

        // Empty state if nothing at all
        if (!hasAnyPlaylists)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.queue_music_rounded, size: 54, color: text.withAlpha(80)),
                    const SizedBox(height: 12),
                    Text(
                      _playlistsSearchQuery.isNotEmpty ? 'No playlists matching search' : 'No playlists yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: text),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create a playlist or import from Spotify to start adding music',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: text.withAlpha(140)),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () => _showCreatePlaylistDialog(context),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Create Playlist'),
                        ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954).withAlpha(40),
                            foregroundColor: const Color(0xFF1DB954),
                          ),
                          onPressed: () => _showImportSpotifyDialog(context),
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('Import Spotify'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  void _showPlaylistOptionsSheet(LocalPlaylist playlist) {
    final accent = widget.settingsService.accentColor;
    final surface = widget.settingsService.surfaceColor;
    final text = widget.settingsService.textColor;
    final isLiked = playlist.isLikedSongs;

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: text.withAlpha(50),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Header with artwork, title, count
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 52,
                          height: 52,
                          color: Colors.black26,
                          child: isLiked
                              ? Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.favorite_rounded, color: Colors.white, size: 28),
                                  ),
                                )
                              : (playlist.effectiveThumbnailUrl.isNotEmpty
                                  ? Image.network(
                                      playlist.effectiveThumbnailUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(Icons.queue_music, color: accent),
                                    )
                                  : Icon(Icons.queue_music, color: accent)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlist.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${playlist.trackCount} song${playlist.trackCount == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 13, color: text.withAlpha(140)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Divider(height: 1, color: text.withAlpha(20)),

                // 1. Play
                ListTile(
                  leading: Icon(Icons.play_arrow_rounded, color: accent, size: 26),
                  title: Text('Play', style: TextStyle(color: text, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    widget.playerService.playLocalTracks(playlist.tracks);
                  },
                ),

                // 2. Play Next
                ListTile(
                  leading: Icon(Icons.playlist_play_rounded, color: text, size: 26),
                  title: Text('Play next', style: TextStyle(color: text)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    final tracks = playlist.tracks.map(Track.fromLocalPlaylistTrack).toList();
                    widget.playerService.playNextTracks(tracks);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Playing "${playlist.title}" next')),
                    );
                  },
                ),

                // 3. Add to Queue
                ListTile(
                  leading: Icon(Icons.queue_music_rounded, color: text, size: 24),
                  title: Text('Add to queue', style: TextStyle(color: text)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    final tracks = playlist.tracks.map(Track.fromLocalPlaylistTrack).toList();
                    widget.playerService.addTracksToQueue(tracks);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added ${tracks.length} tracks to queue')),
                    );
                  },
                ),

                // 4. Download Playlist
                ListTile(
                  leading: Icon(Icons.download_rounded, color: accent, size: 24),
                  title: Text('Download playlist', style: TextStyle(color: text)),
                  subtitle: Text(
                    'Save in space-saving Opus for offline listening',
                    style: TextStyle(fontSize: 11, color: text.withAlpha(120)),
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    final tracks = playlist.tracks.map((t) => Track(
                      id: (t.youtubeVideoId != null && t.youtubeVideoId!.isNotEmpty) ? t.youtubeVideoId! : t.title,
                      title: t.title,
                      author: t.artist,
                      youtubeUrl: (t.youtubeVideoId != null && t.youtubeVideoId!.isNotEmpty) ? 'https://www.youtube.com/watch?v=${t.youtubeVideoId}' : '',
                      duration: t.duration,
                      thumbnailUrl: t.thumbnailUrl,
                    )).toList();
                    DownloadService.instance.downloadTracks(tracks);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Downloading ${tracks.length} songs for offline listening…')),
                    );
                  },
                ),

                // 5. Add all to Liked Songs (if not liked songs)
                if (!isLiked)
                  ListTile(
                    leading: const Icon(Icons.favorite_rounded, color: Color(0xFFFF5252), size: 24),
                    title: Text('Add all to Liked Songs', style: TextStyle(color: text)),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      final count = await widget.playlistService.addAllToLikedSongs(playlist.tracks);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(count > 0 ? 'Added $count songs to Liked Songs!' : 'All songs are already in Liked Songs!'),
                          backgroundColor: const Color(0xFF1DB954),
                        ),
                      );
                    },
                  ),

                // 6. Open Playlist Detail
                ListTile(
                  leading: Icon(Icons.open_in_new_rounded, color: text, size: 24),
                  title: Text('Open playlist', style: TextStyle(color: text)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    widget.onOpenPlaylistDetail?.call(playlist);
                  },
                ),

                // 7. Delete Playlist (if not liked songs)
                if (!isLiked)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
                    title: const Text('Delete playlist', style: TextStyle(color: Colors.redAccent)),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Playlist'),
                          content: Text('Delete "${playlist.title}"?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await widget.playlistService.deletePlaylist(playlist.id);
                      }
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocalPlaylistTile(
    LocalPlaylist playlist,
    Color accent,
    Color surface,
    Color text,
  ) {
    final isSyncing = _syncingPlaylistId == playlist.id;
    final isLiked = playlist.isLikedSongs;

    return GestureDetector(
      onTap: () => widget.onOpenPlaylistDetail?.call(playlist),
      onLongPress: () => _showPlaylistOptionsSheet(playlist),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: text.withAlpha(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isLiked)
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.favorite_rounded, color: Colors.white, size: 48),
                      ),
                    )
                  else if (playlist.effectiveThumbnailUrl.isNotEmpty)
                    Image.network(
                      playlist.effectiveThumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(
                        child: Icon(Icons.queue_music, color: accent, size: 40),
                      ),
                    )
                  else
                    Center(
                      child: Icon(Icons.queue_music, color: accent, size: 40),
                    ),
                  if (isLiked)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.push_pin_rounded, size: 10, color: Colors.white),
                            SizedBox(width: 2),
                            Text('PINNED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                          ],
                        ),
                      ),
                    )
                  else if (playlist.isSpotify)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded, size: 10, color: Colors.white),
                            SizedBox(width: 2),
                            Text('SPOTIFY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: GestureDetector(
                      onTap: () {
                        if (playlist.tracks.isNotEmpty) {
                          widget.playerService.playLocalTracks(playlist.tracks);
                        }
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 4),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.play_arrow_rounded, color: Colors.black, size: 22),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: text,
                          ),
                        ),
                        Text(
                          '${playlist.trackCount} songs',
                          style: TextStyle(fontSize: 11, color: text.withAlpha(140)),
                        ),
                      ],
                    ),
                  ),
                  if (playlist.isSpotify)
                    IconButton(
                      icon: isSyncing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded, size: 18),
                      tooltip: 'Sync Spotify',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _syncLocalPlaylist(playlist),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYtPlaylistTile(
    UserPlaylist playlist,
    Color accent,
    Color surface,
    Color text,
  ) {
    return GestureDetector(
      onTap: () => widget.onOpenYtPlaylistDetail?.call(playlist),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: text.withAlpha(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  playlist.thumbnailUrl.isNotEmpty
                      ? Image.network(
                          playlist.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Center(
                            child: Icon(Icons.video_library_rounded, color: accent, size: 40),
                          ),
                        )
                      : Center(
                          child: Icon(Icons.video_library_rounded, color: accent, size: 40),
                        ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 10, color: Colors.white),
                          SizedBox(width: 2),
                          Text('YOUTUBE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.itemCount} videos',
                    style: TextStyle(fontSize: 11, color: text.withAlpha(140)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================================================================
  // View 2: Songs (Consolidated All Songs)
  // ======================================================================

  Widget _buildSongsView(Color accent, Color surface, Color text) {
    final allSongs = _getAllUniqueSongs();

    // Filter by query
    final filtered = allSongs.where((s) {
      if (_songsSearchQuery.isEmpty) return true;
      final q = _songsSearchQuery.toLowerCase();
      return s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q);
    }).toList();

    // Sort
    switch (_songsSortBy) {
      case 'title_desc':
        filtered.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case 'artist_asc':
        filtered.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case 'duration_desc':
        filtered.sort((a, b) => b.duration.compareTo(a.duration));
        break;
      case 'duration_asc':
        filtered.sort((a, b) => a.duration.compareTo(b.duration));
        break;
      case 'title_asc':
      default:
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
    }

    return Column(
      children: [
        // Search & Controls bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search songs or artists…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: text.withAlpha(20)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: text.withAlpha(20)),
                  ),
                ),
                onChanged: (val) => setState(() => _songsSearchQuery = val.trim()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${filtered.length} songs',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: text.withAlpha(200),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Play All', style: TextStyle(fontSize: 12)),
                    onPressed: filtered.isNotEmpty
                        ? () => widget.playerService.playLocalTracks(filtered, startIndex: 0)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.shuffle_rounded, size: 16),
                    label: const Text('Shuffle', style: TextStyle(fontSize: 12)),
                    onPressed: filtered.isNotEmpty
                        ? () {
                            final shuffled = List<LocalPlaylistTrack>.from(filtered)..shuffle();
                            widget.playerService.playLocalTracks(shuffled, startIndex: 0);
                          }
                        : null,
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.sort_rounded, size: 20),
                    tooltip: 'Sort by',
                    onSelected: (val) => setState(() => _songsSortBy = val),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'title_asc', child: Text('Title (A to Z)')),
                      const PopupMenuItem(value: 'title_desc', child: Text('Title (Z to A)')),
                      const PopupMenuItem(value: 'artist_asc', child: Text('Artist (A to Z)')),
                      const PopupMenuItem(value: 'duration_desc', child: Text('Duration (Longest)')),
                      const PopupMenuItem(value: 'duration_asc', child: Text('Duration (Shortest)')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Songs ListView
        Expanded(
          child: filtered.isNotEmpty
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final song = filtered[index];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: (song.thumbnailUrl != null && song.thumbnailUrl!.isNotEmpty)
                              ? Image.network(
                                  song.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    color: accent.withAlpha(30),
                                    child: Icon(Icons.music_note, color: accent, size: 20),
                                  ),
                                )
                              : Container(
                                  color: accent.withAlpha(30),
                                  child: Icon(Icons.music_note, color: accent, size: 20),
                                ),
                        ),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, color: text, fontSize: 14),
                      ),
                      subtitle: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: text.withAlpha(140), fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatDuration(song.duration),
                            style: TextStyle(color: text.withAlpha(120), fontSize: 11),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              widget.playlistService.isTrackLiked(
                                song.youtubeVideoId,
                                song.title,
                                song.artist,
                              )
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: widget.playlistService.isTrackLiked(
                                song.youtubeVideoId,
                                song.title,
                                song.artist,
                              )
                                  ? const Color(0xFFFF5252)
                                  : text.withAlpha(140),
                              size: 20,
                            ),
                            tooltip: 'Save to playlist',
                            onPressed: () {
                              showAddToPlaylistSheet(
                                context: context,
                                track: song,
                                playlistService: widget.playlistService,
                                accentColor: accent,
                                surfaceColor: surface,
                                textColor: text,
                              );
                            },
                          ),
                        ],
                      ),
                      onTap: () => widget.playerService.playLocalTracks(filtered, startIndex: index),
                    );
                  },
                )
              : Center(
                  child: Text(
                    _songsSearchQuery.isNotEmpty ? 'No songs matching query' : 'No songs in library yet',
                    style: TextStyle(color: text.withAlpha(140)),
                  ),
                ),
        ),
      ],
    );
  }

  // ======================================================================
  // View 3: Artists (YouTube Subscriptions)
  // ======================================================================

  Widget _buildArtistsView(Color accent, Color surface, Color text) {
    final allSongs = _getAllUniqueSongs();

    // If not authenticated with Google, show YouTube connect prompt + followed artists
    if (!widget.authService.isAuthenticated) {
      final followed = widget.settingsService.favoriteArtists.toList()..sort();
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF0000).withAlpha(35),
                  surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFF0000).withAlpha(50)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF0000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.subscriptions_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YouTube Subscribed Artists',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Sync your subscribed channels',
                            style: TextStyle(fontSize: 12, color: text.withAlpha(140)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Sign in with your Google account to automatically display and explore all the music artists and channels you subscribe to on YouTube.',
                  style: TextStyle(fontSize: 13, color: text.withAlpha(180), height: 1.4),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF0000),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Sign In with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    await widget.authService.signIn();
                    if (widget.authService.isAuthenticated) {
                      _loadSubscribedArtists();
                    }
                  },
                ),
              ],
            ),
          ),
          if (followed.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Followed Artists',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: text),
            ),
            const SizedBox(height: 12),
            ...followed.map((name) {
              final tracks = allSongs.where((s) => s.individualArtists.any((a) => a.toLowerCase() == name.toLowerCase())).toList();
              final sampleTrack = tracks.firstWhere(
                (t) => t.thumbnailUrl != null && t.thumbnailUrl!.isNotEmpty,
                orElse: () => tracks.isNotEmpty ? tracks.first : const LocalPlaylistTrack(title: '', artist: ''),
              );
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: accent.withAlpha(40),
                  backgroundImage: (sampleTrack.thumbnailUrl != null && sampleTrack.thumbnailUrl!.isNotEmpty)
                      ? NetworkImage(sampleTrack.thumbnailUrl!)
                      : null,
                  child: (sampleTrack.thumbnailUrl == null || sampleTrack.thumbnailUrl!.isEmpty)
                      ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(fontWeight: FontWeight.bold, color: accent, fontSize: 18))
                      : null,
                ),
                title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: text, fontSize: 15)),
                subtitle: Text('Followed artist', style: TextStyle(color: text.withAlpha(140), fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openArtistPage(name, sampleTrack.thumbnailUrl, tracks),
              );
            }),
          ],
        ],
      );
    }

    // Filter subscribed artists by search query
    final filtered = _subscribedArtists.where((a) {
      if (_artistsSearchQuery.isEmpty) return true;
      return a.title.toLowerCase().contains(_artistsSearchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // Search bar & Sync button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search subscribed artists…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: text.withAlpha(20)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: text.withAlpha(20)),
                    ),
                  ),
                  onChanged: (val) => setState(() => _artistsSearchQuery = val.trim()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Sync subscriptions',
                icon: _loadingArtists
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                      )
                    : Icon(Icons.sync_rounded, color: accent, size: 22),
                onPressed: _loadingArtists ? null : () => _loadSubscribedArtists(forceRefresh: true),
              ),
              Text(
                '${filtered.length} artists',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: text.withAlpha(180),
                ),
              ),
            ],
          ),
        ),

        // Artists content
        Expanded(
          child: _loadingArtists && _subscribedArtists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: accent),
                      const SizedBox(height: 16),
                      Text(
                        'Syncing subscribed artists from YouTube…',
                        style: TextStyle(color: text.withAlpha(160), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : _artistsError != null && _subscribedArtists.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
                          const SizedBox(height: 12),
                          Text('Failed to load subscriptions', style: TextStyle(color: text, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(_artistsError!, style: TextStyle(color: text.withAlpha(140), fontSize: 12)),
                          const SizedBox(height: 16),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                            onPressed: () => _loadSubscribedArtists(forceRefresh: true),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : filtered.isNotEmpty
                      ? ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => Divider(color: text.withAlpha(15), height: 1),
                          itemBuilder: (context, index) {
                            final artist = filtered[index];
                            final localTracks = allSongs.where((s) => s.artist.toLowerCase() == artist.title.toLowerCase()).toList();

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: accent.withAlpha(40),
                                backgroundImage: artist.thumbnailUrl.isNotEmpty
                                    ? NetworkImage(artist.thumbnailUrl)
                                    : null,
                                child: artist.thumbnailUrl.isEmpty
                                    ? Text(
                                        artist.title.isNotEmpty ? artist.title[0].toUpperCase() : '?',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: accent, fontSize: 18),
                                      )
                                    : null,
                              ),
                              title: Text(
                                artist.title,
                                style: TextStyle(fontWeight: FontWeight.bold, color: text, fontSize: 15),
                              ),
                              subtitle: Row(
                                children: [
                                  const Icon(Icons.subscriptions_rounded, size: 12, color: Color(0xFFFF0000)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Subscribed on YouTube',
                                    style: TextStyle(color: text.withAlpha(140), fontSize: 12),
                                  ),
                                  if (localTracks.isNotEmpty) ...[
                                    Text(' • ', style: TextStyle(color: text.withAlpha(100))),
                                    Text(
                                      '${localTracks.length} saved',
                                      style: TextStyle(color: accent, fontSize: 12),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: Icon(Icons.chevron_right_rounded, color: text.withAlpha(120)),
                              onTap: () => _openArtistPage(
                                artist.title,
                                artist.thumbnailUrl,
                                localTracks,
                                channelId: artist.channelId,
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_outline_rounded, size: 48, color: text.withAlpha(80)),
                              const SizedBox(height: 12),
                              Text(
                                _artistsSearchQuery.isNotEmpty
                                    ? 'No subscribed artists matching "$_artistsSearchQuery"'
                                    : 'No YouTube subscribed artists found',
                                style: TextStyle(color: text.withAlpha(140)),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Sync Subscriptions'),
                                onPressed: () => _loadSubscribedArtists(forceRefresh: true),
                              ),
                            ],
                          ),
                        ),
        ),
      ],
    );
  }

  // ======================================================================
  // View 4: Albums
  // ======================================================================

  Widget _buildAlbumsView(Color accent, Color surface, Color text) {
    final playlists = widget.playlistService.playlists;

    // Albums from playlists and collections
    final albumList = <({String title, String artist, String coverUrl, List<LocalPlaylistTrack> tracks})>[];

    for (final p in playlists) {
      if (p.tracks.isNotEmpty) {
        final artist = p.tracks.first.artist;
        albumList.add((
          title: p.title,
          artist: artist.isNotEmpty ? artist : 'Various Artists',
          coverUrl: p.thumbnailUrl,
          tracks: p.tracks,
        ));
      }
    }

    // Filter
    final filtered = albumList.where((a) {
      if (_albumsSearchQuery.isEmpty) return true;
      final q = _albumsSearchQuery.toLowerCase();
      return a.title.toLowerCase().contains(q) || a.artist.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search albums…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: text.withAlpha(20)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: text.withAlpha(20)),
                    ),
                  ),
                  onChanged: (val) => setState(() => _albumsSearchQuery = val.trim()),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${filtered.length} albums',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: text.withAlpha(180),
                ),
              ),
            ],
          ),
        ),

        // Albums Grid with Vinyl Sleeve Effect
        Expanded(
          child: filtered.isNotEmpty
              ? GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final album = filtered[index];
                    return GestureDetector(
                      onTap: () => _showAlbumDetailSheet(album.title, album.artist, album.coverUrl, album.tracks, accent, surface, text),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Vinyl Sleeve
                          Expanded(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // Vinyl Record Peeking
                                Positioned(
                                  right: 0,
                                  top: 4,
                                  bottom: 4,
                                  child: Container(
                                    width: 100,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF111111),
                                      border: Border.all(color: const Color(0xFF333333), width: 1.5),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: accent,
                                        ),
                                        child: const Center(
                                          child: CircleAvatar(radius: 3, backgroundColor: Colors.black),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Sleeve Cover
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 125,
                                    decoration: BoxDecoration(
                                      color: surface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: text.withAlpha(25)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withAlpha(90),
                                          blurRadius: 6,
                                          offset: const Offset(2, 3),
                                        ),
                                      ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: (album.coverUrl.isNotEmpty)
                                        ? Image.network(
                                            album.coverUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => Center(
                                              child: Icon(Icons.album_rounded, color: accent, size: 36),
                                            ),
                                          )
                                        : Center(
                                            child: Icon(Icons.album_rounded, color: accent, size: 36),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            album.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: text),
                          ),
                          Text(
                            '${album.artist} • ${album.tracks.length} tracks',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: text.withAlpha(140)),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : Center(
                  child: Text(
                    _albumsSearchQuery.isNotEmpty ? 'No albums matching search' : 'No albums in library yet',
                    style: TextStyle(color: text.withAlpha(140)),
                  ),
                ),
        ),
      ],
    );
  }

  // ======================================================================
  // Sheets & Dialogs (Offline, Cached, Local Files, Top 50, Artist, Album)
  // ======================================================================


  void _showLocalFilesSheet(Color accent, Color surface, Color text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFFF9800).withAlpha(40), shape: BoxShape.circle),
                    child: const Icon(Icons.folder_open_rounded, color: Color(0xFFFF9800), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text('Local Audio & Files', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: text)),
                ],
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.text_snippet_outlined),
                title: const Text('Import from Text / Notes'),
                subtitle: const Text('Paste "Artist - Title" lines or track lists'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showImportTextDialog(context);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Import CSV (Exportify / Soundiiz)'),
                subtitle: const Text('Paste CSV exports with 1,000+ tracks'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showImportTextDialog(context);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('Create New Local Playlist'),
                subtitle: const Text('Create an empty playlist and add songs'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showCreatePlaylistDialog(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTop50Sheet(Color accent, Color surface, Color text) {
    final repeats = HistoryService.instance.getRepeatTracks(limit: 50);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: text.withAlpha(60), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFAB47BC).withAlpha(40), shape: BoxShape.circle),
                        child: const Icon(Icons.trending_up_rounded, color: Color(0xFFAB47BC), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('My Top 50', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: text)),
                          Text('Your most-played tracks of all time', style: TextStyle(fontSize: 12, color: text.withAlpha(140))),
                        ],
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Play'),
                        onPressed: repeats.isNotEmpty
                            ? () {
                                Navigator.of(ctx).pop();
                                final tracks = repeats.map((r) => r.toLocalPlaylistTrack()).toList();
                                widget.playerService.playLocalTracks(tracks);
                              }
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: repeats.isNotEmpty
                        ? ListView.builder(
                            controller: scrollCtrl,
                            itemCount: repeats.length,
                            itemBuilder: (context, i) {
                              final item = repeats[i];
                              return ListTile(
                                dense: true,
                                leading: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(color: accent.withAlpha(30), shape: BoxShape.circle),
                                  child: Center(
                                    child: Text('${i + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent)),
                                  ),
                                ),
                                title: Text(item.title, style: TextStyle(color: text, fontWeight: FontWeight.w600)),
                                subtitle: Text('${item.artist} • ${item.playCount} plays', style: TextStyle(color: text.withAlpha(140), fontSize: 12)),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  final tracks = repeats.map((r) => r.toLocalPlaylistTrack()).toList();
                                  widget.playerService.playLocalTracks(tracks, startIndex: i);
                                },
                              );
                            },
                          )
                        : Center(
                            child: Text(
                              'Play more songs to build your Top 50 mix!',
                              style: TextStyle(color: text.withAlpha(140), fontSize: 13),
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openArtistPage(
    String artistName,
    String? imageUrl,
    List<LocalPlaylistTrack> tracks, {
    String? channelId,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistScreen(
          artistName: artistName,
          channelId: channelId,
          initialImageUrl: imageUrl,
          initialTracks: tracks,
          playerService: widget.playerService,
          authService: widget.authService,
          playlistService: widget.playlistService,
          settingsService: widget.settingsService,
        ),
      ),
    );
  }

  void _showAlbumDetailSheet(
    String title,
    String artist,
    String coverUrl,
    List<LocalPlaylistTrack> tracks,
    Color accent,
    Color surface,
    Color text,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: text.withAlpha(60), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: (coverUrl.isNotEmpty)
                              ? Image.network(
                                  coverUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    color: accent.withAlpha(30),
                                    child: Icon(Icons.album_rounded, color: accent, size: 30),
                                  ),
                                )
                              : Container(
                                  color: accent.withAlpha(30),
                                  child: Icon(Icons.album_rounded, color: accent, size: 30),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: text)),
                            Text('$artist • ${tracks.length} tracks', style: TextStyle(fontSize: 12, color: text.withAlpha(140))),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Play'),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          widget.playerService.playLocalTracks(tracks);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: tracks.length,
                      itemBuilder: (context, i) {
                        final t = tracks[i];
                        return ListTile(
                          dense: true,
                          leading: Text('${i + 1}', style: TextStyle(color: text.withAlpha(140), fontSize: 12, fontWeight: FontWeight.bold)),
                          title: Text(t.title, style: TextStyle(color: text, fontWeight: FontWeight.w600)),
                          subtitle: Text(t.artist, style: TextStyle(color: text.withAlpha(140), fontSize: 11)),
                          trailing: Text(_formatDuration(t.duration), style: TextStyle(color: text.withAlpha(120), fontSize: 11)),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            widget.playerService.playLocalTracks(tracks, startIndex: i);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ======================================================================
  // Dialogs: Import Spotify, Create Playlist, Import Text
  // ======================================================================

  Future<void> _showImportSpotifyDialog(BuildContext context) async {
    final controller = TextEditingController();
    bool loading = false;
    String? statusMessage;
    String? error;
    SpotifyImportResult? preview;
    bool showApiSetup = false;
    final idController = TextEditingController(text: widget.settingsService.spotifyClientId);
    final secretController = TextEditingController(text: widget.settingsService.spotifyClientSecret);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setSheetState) {
            Future<void> fetchPreview() async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              setSheetState(() {
                loading = true;
                error = null;
                preview = null;
                statusMessage = widget.settingsService.hasSpotifyCredentials
                    ? 'Connecting to Spotify Web API…'
                    : 'Extracting playlist metadata…';
              });
              try {
                final spotify = SpotifyService();
                final res = await spotify.fetch(
                  text,
                  clientId: widget.settingsService.spotifyClientId,
                  clientSecret: widget.settingsService.spotifyClientSecret,
                  onProgress: (current, total) {
                    if (!dialogCtx.mounted) return;
                    setSheetState(() {
                      statusMessage = 'Fetched $current of $total tracks…';
                    });
                  },
                );
                if (!dialogCtx.mounted) return;
                setSheetState(() {
                  preview = res;
                  loading = false;
                });
              } catch (e) {
                if (!dialogCtx.mounted) return;
                setSheetState(() {
                  error = e.toString().replaceFirst('Exception: ', '');
                  loading = false;
                });
              }
            }

            Future<void> pasteFromClipboard() async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null && data!.text!.isNotEmpty) {
                controller.text = data.text!.trim();
                fetchPreview();
              }
            }

            final hasApi = widget.settingsService.hasSpotifyCredentials;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(dialogCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1DB954).withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.queue_music_rounded, color: Color(0xFF1DB954), size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Import Spotify Playlist',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20, color: Colors.white70),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (hasApi ? const Color(0xFF1DB954) : Colors.grey).withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasApi ? Icons.bolt_rounded : Icons.info_outline,
                                size: 13,
                                color: hasApi ? const Color(0xFF1DB954) : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasApi ? 'Spotify API Active (1k+ tracks)' : 'Public Mode (100 tracks max)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: hasApi ? const Color(0xFF1DB954) : const Color(0xFFAAAAAA),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setSheetState(() => showApiSetup = !showApiSetup),
                          child: Text(
                            showApiSetup ? 'Hide setup' : (hasApi ? 'Edit keys' : 'Enable 1k+ tracks'),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF1DB954),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showApiSetup) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252525),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF383838)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Free Spotify API Credentials',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1DB954)),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Create a free app at developer.spotify.com/dashboard to fetch 1,000+ tracks:',
                              style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: idController,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Client ID',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: secretController,
                              obscureText: true,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Client Secret',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (hasApi)
                                  TextButton(
                                    onPressed: () async {
                                      await widget.settingsService.clearSpotifyCredentials();
                                      idController.clear();
                                      secretController.clear();
                                      setSheetState(() => showApiSetup = false);
                                    },
                                    child: const Text('Clear', style: TextStyle(color: Color(0xFFCF6679), fontSize: 12)),
                                  ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF1DB954),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  onPressed: () async {
                                    final id = idController.text.trim();
                                    final sec = secretController.text.trim();
                                    if (id.isNotEmpty && sec.isNotEmpty) {
                                      await widget.settingsService.setSpotifyCredentials(id, sec);
                                      setSheetState(() => showApiSetup = false);
                                    }
                                  },
                                  child: const Text('Save Keys', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              hintText: 'https://open.spotify.com/playlist/…',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        controller.clear();
                                        setSheetState(() {
                                          preview = null;
                                          error = null;
                                        });
                                      },
                                    )
                                  : null,
                            ),
                            onSubmitted: (_) => fetchPreview(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.paste, size: 18),
                          tooltip: 'Paste',
                          onPressed: pasteFromClipboard,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            children: [
                              const CircularProgressIndicator(strokeWidth: 2.5),
                              const SizedBox(height: 12),
                              Text(
                                statusMessage ?? 'Extracting playlist metadata from Spotify…',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Color(0xFFCF6679), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (preview != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF282828),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF383838)),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: (preview!.thumbnailUrl.isNotEmpty)
                                  ? Image.network(
                                      preview!.thumbnailUrl,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        width: 56,
                                        height: 56,
                                        color: const Color(0xFF1DB954).withAlpha(40),
                                        child: const Icon(Icons.music_note, color: Color(0xFF1DB954)),
                                      ),
                                    )
                                  : Container(
                                      width: 56,
                                      height: 56,
                                      color: const Color(0xFF1DB954).withAlpha(40),
                                      child: const Icon(Icons.music_note, color: Color(0xFF1DB954)),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preview!.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${preview!.tracks.length} songs · Spotify ${preview!.type.name}',
                                    style: const TextStyle(color: Color(0xFF1DB954), fontSize: 13),
                                  ),
                                  if (preview!.description.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      preview!.description,
                                      style: const TextStyle(color: Color(0xFF999999), fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!hasApi && preview!.tracks.length == 100) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF332B00),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF665500)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 14, color: Color(0xFFFFD54F)),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Capped at 100 songs (public limit). Enable Spotify API keys above to load all 1,000+ tracks.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFFFFD54F)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.save_alt_rounded, size: 18),
                              label: const Text('Import & Save'),
                              onPressed: () async {
                                final saved = await widget.playlistService.createFromSpotify(preview!);
                                if (!dialogCtx.mounted) return;
                                Navigator.of(dialogCtx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Imported "${saved.title}" (${saved.trackCount} songs)'),
                                    backgroundColor: const Color(0xFF1DB954),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1DB954)),
                              icon: const Icon(Icons.play_arrow_rounded, size: 20),
                              label: const Text('Play Now'),
                              onPressed: () async {
                                final saved = await widget.playlistService.createFromSpotify(preview!);
                                await widget.playerService.playLocalTracks(saved.tracks);
                                if (!dialogCtx.mounted) return;
                                Navigator.of(dialogCtx).pop();
                                widget.onGoToPlayer?.call();
                              },
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      FilledButton.icon(
                        onPressed: fetchPreview,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Fetch Playlist'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final coverController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Playlist Title', hintText: 'e.g. Chill Vibes'),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description (Optional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: coverController,
                decoration: const InputDecoration(labelText: 'Cover Image URL (Optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              final newPl = LocalPlaylist(
                id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
                title: title,
                description: descController.text.trim(),
                thumbnailUrl: coverController.text.trim(),
                source: 'local',
                createdAt: DateTime.now(),
                tracks: const [],
              );
              await widget.playlistService.savePlaylist(newPl);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              widget.onOpenPlaylistDetail?.call(newPl);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportTextDialog(BuildContext context) async {
    final nameController = TextEditingController(text: 'My Playlist');
    final textController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Song List'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter playlist name and paste song lines or a Spotify CSV file (from Exportify / Soundiiz with 1,000+ songs):',
                style: TextStyle(fontSize: 13, color: Color(0xFFAAAAAA)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Playlist Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 7,
                decoration: const InputDecoration(
                  hintText: 'Queen - Bohemian Rhapsody\nEagles - Hotel California\n-- OR paste CSV from Exportify --\nTrack Name,Artist Name(s)\nBohemian Rhapsody,Queen',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = textController.text.trim();
              if (raw.isEmpty) return;
              final saved = await widget.playlistService.createFromText(
                title: nameController.text.trim(),
                rawText: raw,
              );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Imported "${saved.title}" (${saved.trackCount} songs)'),
                  backgroundColor: const Color(0xFF1DB954),
                ),
              );
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    if (d == Duration.zero) return '--:--';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
