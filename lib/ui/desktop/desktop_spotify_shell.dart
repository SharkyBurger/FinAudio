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
/// and optional right-hand Now Playing view. Styled seamlessly with the user's
/// applied FinAudio theme.
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
  State<DesktopSpotifyShell> createState() => DesktopSpotifyShellState();
}

class DesktopSpotifyShellState extends State<DesktopSpotifyShell> {
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
    widget.settingsService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    widget.playlistService.removeListener(_onServiceUpdate);
    widget.authService.removeListener(_onServiceUpdate);
    widget.settingsService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void navigateTo({int? tabIndex, LocalPlaylist? playlist}) {
    _navigateTo(tabIndex: tabIndex, playlist: playlist);
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
    final surface = widget.settingsService.surfaceColor;
    final text = widget.settingsService.textColor;
    final textMuted = text.withAlpha(170);
    final textDim = text.withAlpha(110);
    final border = text.withAlpha(20);
    final accent = widget.settingsService.accentColor;

    final queue = widget.playerService.queue;
    final current = widget.playerService.currentTrack;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: surface,
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
                    Icon(Icons.queue_music_rounded, color: accent),
                    const SizedBox(width: 10),
                    Text(
                      'Playback Queue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: text,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Divider(color: border),
                if (queue.isEmpty && current == null)
                  Expanded(
                    child: Center(
                      child: Text('Queue is empty', style: TextStyle(color: textDim)),
                    ),
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
                          selectedTileColor: accent.withAlpha(30),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: buildTrackThumbnail(item, accent, size: 40),
                            ),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              color: isCurrent ? accent : text,
                            ),
                          ),
                          subtitle: Text(
                            item.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: textDim),
                          ),
                          trailing: isCurrent
                              ? Icon(Icons.volume_up_rounded, color: accent, size: 18)
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
    final surface = widget.settingsService.surfaceColor;
    final text = widget.settingsService.textColor;
    final textMuted = text.withAlpha(170);
    final textDim = text.withAlpha(110);
    final accent = widget.settingsService.accentColor;
    final onAccent = accent.computeLuminance() > 0.5 ? const Color(0xFF101010) : const Color(0xFFFFFFFF);

    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Create New Playlist', style: TextStyle(color: text, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: text),
          decoration: InputDecoration(
            hintText: 'My Playlist #1',
            hintStyle: TextStyle(color: textDim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: onAccent,
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
    required Color accent,
    required Color text,
    required Color textMuted,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? accent.withAlpha(22) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? accent : textMuted,
                size: 24,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? text : textMuted,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopNavCard(Color surface, Color cardBorder, Color accent, Color text, Color textMuted) {
    return Material(
      color: surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cardBorder, width: 1),
      ),
      child: Padding(
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
                    color: accent.withAlpha(35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withAlpha(90)),
                  ),
                  child: Center(
                    child: Icon(Icons.graphic_eq_rounded, color: accent, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'FinAudio',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: text,
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
            accent: accent,
            text: text,
            textMuted: textMuted,
            onTap: () => _navigateTo(tabIndex: 0),
          ),
          _buildSidebarItem(
            icon: Icons.search_rounded,
            activeIcon: Icons.search_rounded,
            label: 'Search',
            isSelected: _currentIndex == 1 && _activePlaylist == null,
            accent: accent,
            text: text,
            textMuted: textMuted,
            onTap: () => _navigateTo(tabIndex: 1),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildLibraryCard(
    Color surface,
    Color cardBorder,
    Color bg,
    Color accent,
    Color text,
    Color textMuted,
    Color textDim,
    Color inputBg,
    Color onAccent,
  ) {
    final likedSongs = widget.playlistService.likedSongsPlaylist;
    var playlists = widget.playlistService.playlists
        .where((p) => p.id != PlaylistService.likedSongsId)
        .toList();

    if (_libraryFilter.isNotEmpty) {
      playlists = playlists
          .where((p) => p.title.toLowerCase().contains(_libraryFilter.toLowerCase()))
          .toList();
    }

    return Material(
      color: surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cardBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Library Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                Icon(Icons.library_music_rounded, color: textMuted, size: 22),
                const SizedBox(width: 12),
                Text(
                  'Your Library',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textMuted,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Create playlist',
                  icon: Icon(Icons.add_rounded, size: 20, color: textMuted),
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
                color: inputBg,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 16, color: textDim),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _libraryFilter = val),
                      style: TextStyle(fontSize: 12, color: text),
                      decoration: InputDecoration(
                        hintText: 'Search in Your Library',
                        hintStyle: TextStyle(fontSize: 11, color: textDim),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_libraryFilter.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _libraryFilter = ''),
                      child: Icon(Icons.close_rounded, size: 14, color: textDim),
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
                      ? accent.withAlpha(25)
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
                              gradient: LinearGradient(
                                colors: [
                                  accent.withAlpha(220),
                                  Color.lerp(accent, surface, 0.55) ?? accent,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Icon(Icons.favorite_rounded, color: onAccent, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Liked Songs',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: text,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.push_pin_rounded, size: 11, color: accent),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Playlist • ${likedSongs.tracks.length} songs',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: textDim,
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
                        ? accent.withAlpha(25)
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
                                color: inputBg,
                                child: (p.thumbnailUrl.isNotEmpty)
                                    ? CachedNetworkImage(
                                        imageUrl: p.thumbnailUrl,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, _, _) => Icon(
                                          Icons.music_note_rounded,
                                          color: textDim,
                                        ),
                                      )
                                    : Icon(
                                        Icons.queue_music_rounded,
                                        color: textDim,
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
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: text,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Playlist • ${p.tracks.length} songs',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: textDim,
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

  Widget _buildCenterTopBar(
    Color surface,
    Color bg,
    Color border,
    Color accent,
    Color text,
    Color textMuted,
    Color textDim,
    Color onAccent,
  ) {
    final canGoBack = _historyIndex > 0;
    final canGoForward = _historyIndex < _history.length - 1;
    final isSignedIn = widget.authService.isSignedIn;
    final user = widget.authService.currentUser;
    final headerBg = Color.lerp(surface, bg, 0.25) ?? surface;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          bottom: BorderSide(color: border, width: 1),
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
              color: canGoBack ? bg.withAlpha(220) : bg.withAlpha(100),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.chevron_left_rounded,
                size: 24,
                color: canGoBack ? text : textDim,
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
              color: canGoForward ? bg.withAlpha(220) : bg.withAlpha(100),
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: canGoForward ? text : textDim,
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
                  ? accent
                  : textMuted,
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
                color: bg.withAlpha(220),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundImage: (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                        ? NetworkImage(user.photoUrl!)
                        : null,
                    backgroundColor: accent.withAlpha(40),
                    child: (user.photoUrl == null || user.photoUrl!.isEmpty)
                        ? Icon(Icons.person, color: accent, size: 14)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    user.displayName ?? 'Account',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: text,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.arrow_drop_down_rounded, color: textMuted, size: 20),
                    padding: EdgeInsets.zero,
                    color: surface,
                    onSelected: (val) async {
                      if (val == 'settings') {
                        _navigateTo(tabIndex: 3);
                      } else if (val == 'signout') {
                        await widget.authService.signOut();
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'settings',
                        child: Text('Settings', style: TextStyle(color: text)),
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
                backgroundColor: accent,
                foregroundColor: onAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () {
                showGoogleSignInDialog(
                  context: context,
                  authService: widget.authService,
                  accentColor: accent,
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
    final bg = widget.settingsService.backgroundColor;
    final surface = widget.settingsService.surfaceColor;
    final accent = widget.settingsService.accentColor;
    final text = widget.settingsService.textColor;
    final textMuted = text.withAlpha(170);
    final textDim = text.withAlpha(110);
    final border = text.withAlpha(20);
    final cardBorder = text.withAlpha(18);
    final inputBg = Color.lerp(surface, bg, 0.45) ?? surface;
    final onAccent = accent.computeLuminance() > 0.5 ? const Color(0xFF101010) : const Color(0xFFFFFFFF);

    return Scaffold(
      backgroundColor: bg,
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
                        _buildTopNavCard(surface, cardBorder, accent, text, textMuted),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _buildLibraryCard(
                            surface,
                            cardBorder,
                            bg,
                            accent,
                            text,
                            textMuted,
                            textDim,
                            inputBg,
                            onAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Main Center Stage Card
                  Expanded(
                    child: Material(
                      color: surface,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: cardBorder, width: 1),
                      ),
                      child: Column(
                        children: [
                          _buildCenterTopBar(
                            surface,
                            bg,
                            border,
                            accent,
                            text,
                            textMuted,
                            textDim,
                            onAccent,
                          ),
                          Expanded(
                            child: _activePlaylist != null
                                ? DesktopPlaylistView(
                                    key: ValueKey(_activePlaylist!.id),
                                    playlist: _activePlaylist!,
                                    playerService: widget.playerService,
                                    playlistService: widget.playlistService,
                                    settingsService: widget.settingsService,
                                    authService: widget.authService,
                                    accentColor: accent,
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
                      child: Material(
                        color: surface,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: cardBorder, width: 1),
                        ),
                        child: DesktopRightPanel(
                          track: _nowPlaying,
                          playerService: widget.playerService,
                          playlistService: widget.playlistService,
                          settingsService: widget.settingsService,
                          accentColor: accent,
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
              accentColor: accent,
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
