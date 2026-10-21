import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:finaudio/models/local_playlist.dart';
import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/playlist_service.dart';
import 'package:finaudio/services/settings_service.dart';
import 'package:finaudio/services/google_auth_service.dart';
import 'package:finaudio/widgets/now_playing_bar.dart';
import 'package:finaudio/widgets/google_sign_in_dialog.dart';
import 'package:finaudio/ui/desktop/desktop_playlist_view.dart';
import 'package:finaudio/ui/desktop/desktop_right_panel.dart';

class _DesktopNavHistory {
  final int tabIndex;
  final LocalPlaylist? playlist;
  _DesktopNavHistory({required this.tabIndex, this.playlist});
}

/// Spotify-style Desktop Shell with floating rounded Island cards,
/// collapsible/interactive sidebar, central stage with back/forward history,
/// and optional right-hand Now Playing view.
class DesktopSpotifyShell extends StatefulWidget {
  final Color accentColor;
  final PlayerService playerService;
  final GoogleAuthService authService;
  final PlaylistService playlistService;
  final SettingsService settingsService;
  final List<Widget> contentTabs;
  final VoidCallback onSettingsChanged;

  const DesktopSpotifyShell({
    super.key,
    required this.accentColor,
    required this.playerService,
    required this.authService,
    required this.playlistService,
    required this.settingsService,
    required this.contentTabs,
    required this.onSettingsChanged,
  });

  @override
  State<DesktopSpotifyShell> createState() => _DesktopSpotifyShellState();
}

class _DesktopSpotifyShellState extends State<DesktopSpotifyShell> {
  int _currentIndex = 0;
  LocalPlaylist? _activePlaylist;
  bool _showRightPanel = false;
  String _libraryFilter = '';
  Track? _nowPlaying;
  StreamSubscription<Track?>? _trackSub;

  final List<_DesktopNavHistory> _history = [];
  int _historyIndex = 0;

  @override
  void initState() {
    super.initState();
    _history.add(_DesktopNavHistory(tabIndex: 0));
    _nowPlaying = widget.playerService.currentTrack;
    _trackSub = widget.playerService.nowPlayingStream.listen((t) {
      if (mounted) setState(() => _nowPlaying = t);
    });
    widget.playlistService.addListener(_onServiceUpdate);
    widget.authService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    widget.playlistService.removeListener(_onServiceUpdate);
    widget.authService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _navigateTo({int? tabIndex, LocalPlaylist? playlist}) {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    final nextTab = tabIndex ?? _currentIndex;
    _history.add(_DesktopNavHistory(tabIndex: nextTab, playlist: playlist));
    _historyIndex = _history.length - 1;

    setState(() {
      _currentIndex = nextTab;
      _activePlaylist = playlist;
    });
  }

  void _goBack() {
    if (_historyIndex > 0) {
      _historyIndex--;
      final item = _history[_historyIndex];
      setState(() {
        _currentIndex = item.tabIndex;
        _activePlaylist = item.playlist;
      });
    }
  }

  void _goForward() {
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      final item = _history[_historyIndex];
      setState(() {
        _currentIndex = item.tabIndex;
        _activePlaylist = item.playlist;
      });
    }
  }

  void _showQueueDialog(BuildContext context) {
    final theme = Theme.of(context);
    final queue = widget.playerService.queue;
    final current = widget.playerService.currentTrack;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.queue_music_rounded, color: widget.accentColor),
                    const SizedBox(width: 10),
                    Text(
                      'Playback Queue',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24),
                if (queue.isEmpty && current == null)
                  const Expanded(
                    child: Center(child: Text('Queue is empty', style: TextStyle(color: Colors.white54))),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: queue.length,
                      itemBuilder: (context, i) {
                        final item = queue[i];
                        final isCurrent = item.id == current?.id;
                        return ListTile(
                          selected: isCurrent,
                          selectedTileColor: widget.accentColor.withAlpha(30),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: buildTrackThumbnail(item, widget.accentColor, size: 40),
                            ),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              color: isCurrent ? widget.accentColor : Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            item.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: isCurrent
                              ? Icon(Icons.volume_up_rounded, color: widget.accentColor, size: 18)
                              : null,
                          onTap: () {
                            widget.playerService.playTrackAt(i);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Create New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'My Playlist #1',
            hintStyle: TextStyle(color: Color(0xFF7A7A7A)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFFB3B3B3))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.accentColor,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                final pl = await widget.playlistService.createPlaylist(title: title);
                if (mounted) {
                  _navigateTo(playlist: pl);
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? Colors.white : const Color(0xFFB3B3B3),
                size: 24,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFFB3B3B3),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopNavCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          // FinAudio Brand Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.accentColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.accentColor.withAlpha(90)),
                  ),
                  child: Center(
                    child: Icon(Icons.graphic_eq_rounded, color: widget.accentColor, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'FinAudio',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          _buildSidebarItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: 'Home',
            isSelected: _currentIndex == 0 && _activePlaylist == null,
            onTap: () => _navigateTo(tabIndex: 0),
          ),
          _buildSidebarItem(
            icon: Icons.search_rounded,
            activeIcon: Icons.search_rounded,
            label: 'Search',
            isSelected: _currentIndex == 1 && _activePlaylist == null,
            onTap: () => _navigateTo(tabIndex: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryCard() {
    final likedSongs = widget.playlistService.likedSongsPlaylist;
    var playlists = widget.playlistService.playlists
        .where((p) => p.id != PlaylistService.likedSongsId)
        .toList();

    if (_libraryFilter.isNotEmpty) {
      playlists = playlists
          .where((p) => p.title.toLowerCase().contains(_libraryFilter.toLowerCase()))
          .toList();
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Library Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.library_music_rounded, color: Color(0xFFB3B3B3), size: 22),
                const SizedBox(width: 12),
                const Text(
                  'Your Library',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB3B3B3),
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Create playlist',
                  icon: const Icon(Icons.add_rounded, size: 20, color: Color(0xFFB3B3B3)),
                  splashRadius: 18,
                  onPressed: () => _showCreatePlaylistDialog(context),
                ),
              ],
            ),
          ),

          // Search / Filter Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 16, color: Color(0xFFB3B3B3)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _libraryFilter = val),
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Search in Your Library',
                        hintStyle: TextStyle(fontSize: 11, color: Color(0xFF7A7A7A)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_libraryFilter.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _libraryFilter = ''),
                      child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFB3B3B3)),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Scrollable Playlists
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: [
                // Liked Songs Item (Featured top)
                Material(
                  color: (_activePlaylist?.id == PlaylistService.likedSongsId)
                      ? Colors.white.withAlpha(25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _navigateTo(playlist: likedSongs),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Icon(Icons.favorite_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Liked Songs',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.push_pin_rounded, size: 11, color: Color(0xFF1DB954)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Playlist • ${likedSongs.tracks.length} songs',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFB3B3B3),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Other Playlists
                for (final p in playlists) ...[
                  const SizedBox(height: 2),
                  Material(
                    color: (_activePlaylist?.id == p.id)
                        ? Colors.white.withAlpha(25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _navigateTo(playlist: p),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                width: 44,
                                height: 44,
                                color: const Color(0xFF282828),
                                child: (p.thumbnailUrl.isNotEmpty)
                                    ? CachedNetworkImage(
                                        imageUrl: p.thumbnailUrl,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, _, _) => const Icon(
                                          Icons.music_note_rounded,
                                          color: Colors.white38,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.queue_music_rounded,
                                        color: Colors.white38,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.title,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Playlist • ${p.tracks.length} songs',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFB3B3B3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterTopBar() {
    final canGoBack = _historyIndex > 0;
    final canGoForward = _historyIndex < _history.length - 1;
    final isSignedIn = widget.authService.isSignedIn;
    final user = widget.authService.currentUser;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF101010),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1F1F1F), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back & Forward Navigation Arrows
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: canGoBack ? Colors.black : Colors.black38,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.chevron_left_rounded,
                size: 24,
                color: canGoBack ? Colors.white : Colors.white24,
              ),
              onPressed: canGoBack ? _goBack : null,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: canGoForward ? Colors.black : Colors.black38,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: canGoForward ? Colors.white : Colors.white24,
              ),
              onPressed: canGoForward ? _goForward : null,
            ),
          ),

          const Spacer(),

          // Settings Shortcut
          IconButton(
            tooltip: 'Settings',
            icon: Icon(
              _currentIndex == 3 && _activePlaylist == null
                  ? Icons.settings_rounded
                  : Icons.settings_outlined,
              color: _currentIndex == 3 && _activePlaylist == null
                  ? widget.accentColor
                  : const Color(0xFFB3B3B3),
              size: 20,
            ),
            onPressed: () => _navigateTo(tabIndex: 3),
          ),
          const SizedBox(width: 8),

          // User Profile Pill / Sign In Button
          if (isSignedIn && user != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundImage: (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                        ? NetworkImage(user.photoUrl!)
                        : null,
                    backgroundColor: widget.accentColor.withAlpha(40),
                    child: (user.photoUrl == null || user.photoUrl!.isEmpty)
                        ? Icon(Icons.person, color: widget.accentColor, size: 14)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    user.displayName ?? 'Account',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 20),
                    padding: EdgeInsets.zero,
                    color: const Color(0xFF282828),
                    onSelected: (val) async {
                      if (val == 'settings') {
                        _navigateTo(tabIndex: 3);
                      } else if (val == 'signout') {
                        await widget.authService.signOut();
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'settings',
                        child: Text('Settings', style: TextStyle(color: Colors.white)),
                      ),
                      const PopupMenuItem(
                        value: 'signout',
                        child: Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () {
                showGoogleSignInDialog(
                  context: context,
                  authService: widget.authService,
                  accentColor: widget.accentColor,
                );
              },
              child: const Text('Log in'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // Top Workspace Row: [Sidebar, Center Stage, Optional Right Panel]
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Left Sidebar (Cards 1 & 2)
                  SizedBox(
                    width: 280,
                    child: Column(
                      children: [
                        _buildTopNavCard(),
                        const SizedBox(height: 8),
                        Expanded(child: _buildLibraryCard()),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Main Center Stage Card
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildCenterTopBar(),
                          Expanded(
                            child: _activePlaylist != null
                                ? DesktopPlaylistView(
                                    key: ValueKey(_activePlaylist!.id),
                                    playlist: _activePlaylist!,
                                    playerService: widget.playerService,
                                    playlistService: widget.playlistService,
                                    settingsService: widget.settingsService,
                                    authService: widget.authService,
                                    accentColor: widget.accentColor,
                                    onBack: _goBack,
                                  )
                                : IndexedStack(
                                    index: _currentIndex.clamp(0, widget.contentTabs.length - 1),
                                    children: widget.contentTabs,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3. Optional Right Panel (Now Playing View)
                  if (_showRightPanel) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 300,
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DesktopRightPanel(
                          track: _nowPlaying,
                          playerService: widget.playerService,
                          playlistService: widget.playlistService,
                          accentColor: widget.accentColor,
                          onClose: () => setState(() => _showRightPanel = false),
                          onOpenQueue: () => _showQueueDialog(context),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),

            // 4. Bottom Player Bar
            DesktopPlayerBar(
              track: _nowPlaying,
              accentColor: widget.accentColor,
              playerService: widget.playerService,
              authService: widget.authService,
              playlistService: widget.playlistService,
              settingsService: widget.settingsService,
              isRightPanelOpen: _showRightPanel,
              onToggleRightPanel: () => setState(() => _showRightPanel = !_showRightPanel),
            ),
          ],
        ),
      ),
    );
  }
}
