import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/local_playlist.dart';
import '../services/google_auth_service.dart';
import '../services/lyrics_service.dart';
import '../services/player_service.dart';
import '../services/playlist_service.dart';
import '../services/settings_service.dart';
import '../services/download_service.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/artist_picker_sheet.dart';
import 'artist_screen.dart';
import 'lyrics_settings_screen.dart';

/// Helper to render artwork from either network HTTP(S) URLs, local file:// URIs, or direct file paths.
Widget _buildCoverArt(
  String url, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
  Widget? placeholder,
}) {
  if (url.isEmpty) {
    return placeholder ?? const SizedBox.shrink();
  }

  // Handle file:// URIs (from offline downloads)
  if (url.startsWith('file://')) {
    try {
      final path = Uri.parse(url).toFilePath();
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => placeholder ?? const SizedBox.shrink(),
        );
      }
    } catch (_) {}
  }

  // Handle raw local filesystem path
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    try {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (_, _, _) => placeholder ?? const SizedBox.shrink(),
        );
      }
    } catch (_) {}
  }

  // Default network image loader
  return Image.network(
    url,
    fit: fit,
    width: width,
    height: height,
    errorBuilder: (_, _, _) => placeholder ?? const SizedBox.shrink(),
  );
}

/// Full-screen "Now Playing" view inspired by Spotify Canvas and ArchiveTune.
/// Features full cover canvas ambient background, sleek ArchiveTune controls,
/// lag-free volume slider, and synchronized Romanized Lyrics view.
class NowPlayingScreen extends StatefulWidget {
  final PlayerService playerService;
  final Color accentColor;
  final GoogleAuthService? authService;
  final PlaylistService? playlistService;
  final SettingsService? settingsService;

  const NowPlayingScreen({
    super.key,
    required this.playerService,
    required this.accentColor,
    this.authService,
    this.playlistService,
    this.settingsService,
  });

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<Track?>? _trackSub;
  StreamSubscription<bool>? _shuffleSub;
  bool _showQueue = false;
  bool _showLyrics = false;
  Timer? _sleepTimer;
  int? _sleepTimerMinutes;

  late final AnimationController _dragResetController;
  Animation<double>? _dragResetAnimation;
  double _dragOffsetY = 0.0;

  @override
  void initState() {
    super.initState();
    _dragResetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _trackSub = widget.playerService.nowPlayingStream.listen((_) {
      if (mounted) setState(() {});
    });
    _shuffleSub = widget.playerService.shuffleStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _dragResetController.dispose();
    _trackSub?.cancel();
    _shuffleSub?.cancel();
    _sleepTimer?.cancel();
    super.dispose();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (details.primaryDelta == null) return;
    if (_showLyrics || _showQueue) return;
    if (_dragOffsetY > 0 || details.primaryDelta! > 0) {
      setState(() {
        _dragOffsetY = (_dragOffsetY + details.primaryDelta!).clamp(0.0, 600.0);
      });
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_showLyrics || _showQueue) return;
    if (_dragOffsetY > 90 || (details.primaryVelocity ?? 0) > 280) {
      Navigator.pop(context);
    } else if (_dragOffsetY > 0) {
      _dragResetAnimation = Tween<double>(begin: _dragOffsetY, end: 0.0).animate(
        CurvedAnimation(parent: _dragResetController, curve: Curves.easeOutCubic),
      )..addListener(() {
          setState(() {
            _dragOffsetY = _dragResetAnimation!.value;
          });
        });
      _dragResetController.forward(from: 0.0);
    }
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    setState(() {
      _sleepTimerMinutes = minutes;
    });
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      widget.playerService.pause();
      if (mounted) {
        setState(() {
          _sleepTimerMinutes = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sleep timer elapsed. Playback paused.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sleep timer set for $minutes minutes'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    setState(() {
      _sleepTimerMinutes = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sleep timer cancelled'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showSleepTimerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Stop audio in',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              for (final mins in [15, 30, 45, 60])
                ListTile(
                  leading: const Icon(Icons.timer_outlined, color: Colors.white70),
                  title: Text(
                    '$mins minutes',
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: _sleepTimerMinutes == mins
                      ? Icon(Icons.check, color: widget.accentColor)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _setSleepTimer(mins);
                  },
                ),
              if (_sleepTimerMinutes != null)
                ListTile(
                  leading: const Icon(Icons.timer_off_outlined, color: Colors.redAccent),
                  title: const Text(
                    'Turn off sleep timer',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _cancelSleepTimer();
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.playerService.currentTrack;
    final theme = Theme.of(context);

    if (track == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0D0E),
        body: _buildEmpty(theme),
      );
    }

    final coverUrl = (track.localThumbnailPath != null && track.localThumbnailPath!.isNotEmpty)
        ? track.localThumbnailPath!
        : (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
            ? track.thumbnailUrl!
            : (track.id.isNotEmpty && !track.id.startsWith('spotify:'))
                ? 'https://img.youtube.com/vi/${track.id}/hqdefault.jpg'
                : '';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
        child: Transform.translate(
          offset: Offset(0, _dragOffsetY),
          child: Opacity(
            opacity: (1.0 - (_dragOffsetY / 500.0)).clamp(0.0, 1.0),
            child: Stack(
              children: [
                // 1. Spotify Canvas Background with dark vignette
                Positioned.fill(
                  child: _SpotifyCanvasBackground(
                    coverUrl: coverUrl,
                    accentColor: widget.accentColor,
                  ),
                ),

                // 2. Active Screen Content
                SafeArea(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _showLyrics
                        ? _LyricsView(
                            key: const ValueKey('lyrics'),
                            track: track,
                            playerService: widget.playerService,
                            accentColor: widget.accentColor,
                            settingsService: widget.settingsService,
                            onClose: () => setState(() => _showLyrics = false),
                          )
                        : _showQueue
                            ? Column(
                                key: const ValueKey('queue'),
                                children: [
                                  _TopBar(
                                    accentColor: widget.accentColor,
                                    onClose: () => Navigator.pop(context),
                                    showQueue: true,
                                    onToggleQueue: () =>
                                        setState(() => _showQueue = false),
                                    onVerticalDragUpdate:
                                        _handleVerticalDragUpdate,
                                    onVerticalDragEnd: _handleVerticalDragEnd,
                                  ),
                                  Expanded(
                                    child: _QueuePanel(
                                      playerService: widget.playerService,
                                      accentColor: widget.accentColor,
                                    ),
                                  ),
                                ],
                              )
                            : _ArchiveTunePlayerView(
                                key: const ValueKey('player'),
                                track: track,
                                coverUrl: coverUrl,
                                playerService: widget.playerService,
                                accentColor: widget.accentColor,
                                authService: widget.authService,
                                playlistService: widget.playlistService,
                                settingsService: widget.settingsService,
                                sleepTimerMinutes: _sleepTimerMinutes,
                                onDismiss: () => Navigator.pop(context),
                                onToggleLyrics: () =>
                                    setState(() => _showLyrics = true),
                                onToggleQueue: () =>
                                    setState(() => _showQueue = true),
                                onSleepTimerTap: _showSleepTimerSheet,
                                onVerticalDragUpdate:
                                    _handleVerticalDragUpdate,
                                onVerticalDragEnd: _handleVerticalDragEnd,
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off, size: 64, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'Nothing playing',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Spotify Canvas Background (Artwork with ambient gradient & blur)
// ======================================================================

class _SpotifyCanvasBackground extends StatelessWidget {
  final String coverUrl;
  final Color accentColor;

  const _SpotifyCanvasBackground({
    required this.coverUrl,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base dark background
        Container(color: const Color(0xFF080808)),

        // High resolution cover art canvas
        if (coverUrl.isNotEmpty)
          Opacity(
            opacity: 0.40,
            child: _buildCoverArt(
              coverUrl,
              fit: BoxFit.cover,
              placeholder: const SizedBox.shrink(),
            ),
          ),

        // Backdrop filter for subtle ambient blur
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.transparent),
          ),
        ),

        // Spotify style dark gradient vignette
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x33000000),
                Color(0x77000000),
                Color(0xDD0A0A0A),
                Color(0xFF080808),
              ],
              stops: [0.0, 0.40, 0.75, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

// ======================================================================
// ArchiveTune Now Playing Layout (Matching User Screenshot 3)
// ======================================================================

class _ArchiveTunePlayerView extends StatelessWidget {
  final Track track;
  final String coverUrl;
  final PlayerService playerService;
  final Color accentColor;
  final GoogleAuthService? authService;
  final PlaylistService? playlistService;
  final SettingsService? settingsService;
  final int? sleepTimerMinutes;
  final VoidCallback onDismiss;
  final VoidCallback onToggleLyrics;
  final VoidCallback onToggleQueue;
  final VoidCallback onSleepTimerTap;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;

  const _ArchiveTunePlayerView({
    super.key,
    required this.track,
    required this.coverUrl,
    required this.playerService,
    required this.accentColor,
    this.authService,
    this.playlistService,
    this.settingsService,
    this.sleepTimerMinutes,
    required this.onDismiss,
    required this.onToggleLyrics,
    required this.onToggleQueue,
    required this.onSleepTimerTap,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Album cover size tuned to fit comfortably without overflow
    final artSize = min(screenHeight * 0.38, screenWidth - 56).clamp(180.0, 360.0);

    return Column(
      children: [
        // Top app bar with dismiss chevron & swipe down handle
        _TopBar(
          accentColor: accentColor,
          onClose: onDismiss,
          showQueue: false,
          onToggleQueue: onToggleQueue,
          onVerticalDragUpdate: onVerticalDragUpdate,
          onVerticalDragEnd: onVerticalDragEnd,
        ),

        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: max(screenHeight * 0.015, 8.0)),

                // 1. Center Artwork Card (Screenshot 3 & swipe down enabled)
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: onVerticalDragUpdate,
                    onVerticalDragEnd: onVerticalDragEnd,
                    child: Container(
                      width: artSize,
                      height: artSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 30,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _buildCoverArt(
                        coverUrl,
                        width: artSize,
                        height: artSize,
                        fit: BoxFit.cover,
                        placeholder: _artPlaceholder(artSize),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: max(screenHeight * 0.025, 14.0)),

                // 2. Track Info Row with Favorite & More menu on right (Screenshot 3)
                _TrackInfoRow(
                  track: track,
                  playerService: playerService,
                  playlistService: playlistService,
                  authService: authService,
                  settingsService: settingsService,
                  accentColor: accentColor,
                ),

                const SizedBox(height: 16),

                // 3. Seek bar with timestamps & AAC/OPUS badge (Screenshot 3)
                _ArchiveTuneSeekBar(
                  playerService: playerService,
                  accentColor: accentColor,
                  settingsService: settingsService,
                ),

                const SizedBox(height: 12),

                // 4. Transport controls: Prev, Play/Pause, Next (Screenshot 3)
                _ArchiveTuneTransport(
                  playerService: playerService,
                  accentColor: accentColor,
                ),

                const SizedBox(height: 14),

                // 5. Smooth lag-free volume slider (Screenshot 3)
                _ArchiveTuneVolumeBar(
                  playerService: playerService,
                  accentColor: accentColor,
                ),

                const SizedBox(height: 16),

                // 6. Bottom action bar: Queue, Lyrics, Timer, Speaker pill (Screenshot 3)
                _ArchiveTuneBottomBar(
                  onToggleQueue: onToggleQueue,
                  onToggleLyrics: onToggleLyrics,
                  onSleepTimerTap: onSleepTimerTap,
                  sleepTimerActive: sleepTimerMinutes != null,
                  accentColor: accentColor,
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    ),
      ],
    );
  }

  Widget _artPlaceholder(double size) {
    return Container(
      color: Colors.white10,
      child: Center(
        child: Icon(Icons.music_note_rounded, size: size * 0.3, color: Colors.white30),
      ),
    );
  }
}

// ======================================================================
// Track Info Row: Title & Artist on Left, 3-dots & Heart on Right
// ======================================================================

class _TrackInfoRow extends StatelessWidget {
  final Track track;
  final PlayerService playerService;
  final PlaylistService? playlistService;
  final GoogleAuthService? authService;
  final SettingsService? settingsService;
  final Color accentColor;

  const _TrackInfoRow({
    required this.track,
    required this.playerService,
    this.playlistService,
    this.authService,
    this.settingsService,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isLiked = playlistService?.isTrackLiked(
          track.id,
          track.title,
          track.author,
        ) ??
        false;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left column: Title & Artist
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: (authService != null &&
                        playlistService != null &&
                        settingsService != null &&
                        track.author.trim().isNotEmpty)
                    ? () {
                        navigateToArtistOrShowPicker(
                          context: context,
                          artists: track.individualArtists,
                          playerService: playerService,
                          authService: authService!,
                          playlistService: playlistService!,
                          settingsService: settingsService!,
                          trackTitle: track.title,
                          initialImageUrl: track.thumbnailUrl,
                        );
                      }
                    : null,
                child: Text(
                  track.formattedArtist.isNotEmpty ? track.formattedArtist : 'Unknown Artist',
                  style: const TextStyle(
                    color: Color(0xFFB3B3B3),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        // 3-dots more menu button in circular translucent chip (Screenshot 3)
        _CircularButton(
          icon: Icons.more_vert_rounded,
          onTap: () => _showTrackOptions(context),
        ),

        const SizedBox(width: 8),

        // Favorite heart button in circular translucent chip (Screenshot 3)
        _CircularButton(
          icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          iconColor: isLiked ? const Color(0xFFFF5252) : Colors.white,
          onTap: () {
            if (playlistService != null) {
              playlistService!.toggleLikeTrack(
                LocalPlaylistTrack(
                  title: track.title,
                  artist: track.author,
                  youtubeVideoId: track.id,
                  thumbnailUrl: track.thumbnailUrl,
                  duration: track.duration,
                ),
              );
            }
          },
        ),
      ],
    );
  }

  void _showTrackOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.playlist_add, color: Colors.white),
                title: const Text('Add to playlist',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  if (playlistService != null) {
                    showAddToPlaylistSheet(
                      context: context,
                      track: LocalPlaylistTrack(
                        title: track.title,
                        artist: track.author,
                        youtubeVideoId: track.id,
                        thumbnailUrl: track.thumbnailUrl,
                        duration: track.duration,
                      ),
                      playlistService: playlistService!,
                      accentColor: accentColor,
                    );
                  }
                },
              ),
              if (authService != null &&
                  playlistService != null &&
                  settingsService != null) ...[
                if (track.individualArtists.length > 1) ...[
                  for (final artist in track.individualArtists)
                    ListTile(
                      leading: const Icon(Icons.person_outline, color: Colors.white),
                      title: Text('Go to $artist',
                          style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ArtistScreen(
                              artistName: artist,
                              initialImageUrl: track.thumbnailUrl,
                              playerService: playerService,
                              authService: authService!,
                              playlistService: playlistService!,
                              settingsService: settingsService!,
                            ),
                          ),
                        );
                      },
                    ),
                ] else
                  ListTile(
                    leading: const Icon(Icons.person_outline, color: Colors.white),
                    title: Text(
                        'Go to ${track.individualArtists.firstOrNull ?? (track.author.isNotEmpty ? track.author : "artist")}',
                        style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      final aName = track.individualArtists.firstOrNull ?? track.author;
                      if (aName.trim().isEmpty) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArtistScreen(
                            artistName: aName,
                            initialImageUrl: track.thumbnailUrl,
                            playerService: playerService,
                            authService: authService!,
                            playlistService: playlistService!,
                            settingsService: settingsService!,
                          ),
                        ),
                      );
                    },
                  ),
              ],
              ListTile(
                leading: Icon(
                  DownloadService.instance.isDownloaded(track.id)
                      ? Icons.delete_outline_rounded
                      : Icons.download_rounded,
                  color: DownloadService.instance.isDownloaded(track.id)
                      ? Colors.redAccent
                      : accentColor,
                ),
                title: Text(
                  DownloadService.instance.isDownloaded(track.id)
                      ? 'Delete offline download'
                      : 'Download (Space Saver Opus)',
                  style: TextStyle(
                    color: DownloadService.instance.isDownloaded(track.id)
                        ? Colors.redAccent
                        : Colors.white,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (DownloadService.instance.isDownloaded(track.id)) {
                    await DownloadService.instance.deleteDownload(track.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Removed "${track.title}" from offline downloads')),
                      );
                    }
                  } else {
                    DownloadService.instance.downloadTrack(track);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Downloading "${track.title}" in Space-Saver Opus…')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _CircularButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _CircularButton({
    required this.icon,
    this.iconColor = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }
}

// ======================================================================
// Seek Bar with AAC Quality Badge (Matching Screenshot 3)
// ======================================================================

class _ArchiveTuneSeekBar extends StatelessWidget {
  final PlayerService playerService;
  final Color accentColor;
  final SettingsService? settingsService;

  const _ArchiveTuneSeekBar({
    required this.playerService,
    required this.accentColor,
    this.settingsService,
  });

  void _showCodecInfoSheet(BuildContext context, String codec) {
    final effectiveSettings = settingsService ?? SettingsService.instance;
    final currentQuality = effectiveSettings?.audioQuality ?? 'auto';
    final bitrate = playerService.currentBitrate;
    final bitrateText = (bitrate != null && bitrate > 0)
        ? '${(bitrate / 1000).round()} kbps'
        : (codec == 'OPUS' ? '~160 kbps' : '~128 kbps');

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.auto_awesome, color: accentColor, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$codec Audio Stream',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                codec == 'OPUS'
                                    ? 'High-efficiency Opus Audio • $bitrateText'
                                    : 'Advanced Audio Coding (AAC) • $bitrateText',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 16),
                    const Text(
                      'Streaming Audio Quality',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildQualityTile(
                      context: sheetCtx,
                      title: 'Automatic',
                      subtitle: 'Wi-Fi: High Quality • Mobile Data: Medium (Saves Data)',
                      value: 'auto',
                      selected: currentQuality == 'auto',
                      onSelect: () {
                        effectiveSettings?.setAudioQuality('auto');
                        Navigator.pop(sheetCtx);
                      },
                    ),
                    _buildQualityTile(
                      context: sheetCtx,
                      title: 'High',
                      subtitle: 'Best audio fidelity (OPUS 160k / AAC ~140k)',
                      value: 'high',
                      selected: currentQuality == 'high',
                      onSelect: () {
                        effectiveSettings?.setAudioQuality('high');
                        Navigator.pop(sheetCtx);
                      },
                    ),
                    _buildQualityTile(
                      context: sheetCtx,
                      title: 'Medium',
                      subtitle: 'Balanced sound with reduced data usage (~128k)',
                      value: 'medium',
                      selected: currentQuality == 'medium',
                      onSelect: () {
                        effectiveSettings?.setAudioQuality('medium');
                        Navigator.pop(sheetCtx);
                      },
                    ),
                    _buildQualityTile(
                      context: sheetCtx,
                      title: 'Low (Data Saver)',
                      subtitle: 'Minimum mobile cellular data usage (~48–70k)',
                      value: 'low',
                      selected: currentQuality == 'low',
                      onSelect: () {
                        effectiveSettings?.setAudioQuality('low');
                        Navigator.pop(sheetCtx);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQualityTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String value,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? accentColor : Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: selected ? Colors.white70 : Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: playerService.positionStream,
      initialData: playerService.position,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: playerService.durationStream,
          initialData: playerService.duration,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds > 0
                ? duration.inMilliseconds.toDouble()
                : 1.0;
            final posMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);

            return Column(
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withValues(alpha: 0.15),
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: posMs,
                    max: maxMs,
                    onChanged: (v) {
                      playerService.seek(Duration(milliseconds: v.toInt()));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Current timestamp (e.g. 0:01)
                      Text(
                        _fmt(position),
                        style: const TextStyle(
                          color: Color(0xFFB3B3B3),
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      // Sleek AAC / OPUS dynamic audio badge + Paused status indicator
                      StreamBuilder<bool>(
                        stream: playerService.playingStream,
                        initialData: playerService.isPlaying,
                        builder: (context, playSnap) {
                          final isPlaying = playSnap.data ?? false;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isPlaying) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.28),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.pause_rounded,
                                        size: 11,
                                        color: Colors.white70,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'PAUSED',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              StreamBuilder<String>(
                                stream: playerService.audioCodecStream,
                                initialData: playerService.currentAudioCodec,
                                builder: (context, codecSnap) {
                                  final codec = (codecSnap.data ?? playerService.currentAudioCodec).toUpperCase();
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => _showCodecInfoSheet(context, codec),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.18),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.auto_awesome,
                                              size: 11,
                                              color: Colors.white70,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              codec,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),

                      // Duration timestamp (e.g. 1:19)
                      Text(
                        _fmt(duration),
                        style: const TextStyle(
                          color: Color(0xFFB3B3B3),
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _fmt(Duration d) {
    final min = d.inMinutes.remainder(60).toString();
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$min:$sec';
    return '$min:$sec';
  }
}

// ======================================================================
// Transport Controls: Prev, Play/Pause, Next (Matching Screenshot 3)
// ======================================================================

class _ArchiveTuneTransport extends StatelessWidget {
  final PlayerService playerService;
  final Color accentColor;

  const _ArchiveTuneTransport({
    required this.playerService,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Shuffle button
        StreamBuilder<bool>(
          stream: playerService.shuffleStream,
          initialData: playerService.shuffleEnabled,
          builder: (context, snap) {
            final isShuffled = snap.data ?? playerService.shuffleEnabled;
            return IconButton(
              onPressed: () => playerService.toggleShuffle(),
              icon: Icon(
                Icons.shuffle_rounded,
                size: 24,
                color: isShuffled ? accentColor : Colors.white60,
              ),
              tooltip: isShuffled ? 'Shuffle On' : 'Shuffle Off',
            );
          },
        ),

        // Previous track
        IconButton(
          onPressed: () => playerService.previousTrack(),
          icon: const Icon(Icons.fast_rewind_rounded, size: 36, color: Colors.white),
          tooltip: 'Previous',
        ),

        // Play / Pause button
        StreamBuilder<bool>(
          stream: playerService.playingStream,
          initialData: playerService.isPlaying,
          builder: (context, snap) {
            final isPlaying = snap.data ?? false;
            return GestureDetector(
              onTap: () => playerService.togglePlayPause(),
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),

        // Next track
        IconButton(
          onPressed: () => playerService.nextTrack(),
          icon: const Icon(Icons.fast_forward_rounded, size: 36, color: Colors.white),
          tooltip: 'Next',
        ),

        // Loop / Repeat button
        StreamBuilder<LoopMode>(
          stream: playerService.loopModeStream,
          initialData: playerService.loopMode,
          builder: (context, snap) {
            final mode = snap.data ?? playerService.loopMode;
            final isLoopOne = mode == LoopMode.one;
            final isLoopAll = mode == LoopMode.all;
            final active = mode != LoopMode.off;
            return IconButton(
              onPressed: () => playerService.cycleLoopMode(),
              icon: Icon(
                isLoopOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                size: 24,
                color: active ? accentColor : Colors.white60,
              ),
              tooltip: isLoopOne ? 'Repeat One' : (isLoopAll ? 'Repeat All' : 'Repeat Off'),
            );
          },
        ),
      ],
    );
  }
}

// ======================================================================
// Smooth Volume Control Bar (Matching Screenshot 3, Zero Lag)
// ======================================================================

class _ArchiveTuneVolumeBar extends StatefulWidget {
  final PlayerService playerService;
  final Color accentColor;

  const _ArchiveTuneVolumeBar({
    required this.playerService,
    required this.accentColor,
  });

  @override
  State<_ArchiveTuneVolumeBar> createState() => _ArchiveTuneVolumeBarState();
}

class _ArchiveTuneVolumeBarState extends State<_ArchiveTuneVolumeBar> {
  double? _dragVolume;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: widget.playerService.volumeStream,
      initialData: widget.playerService.volume,
      builder: (context, snap) {
        final currentVol =
            (snap.data ?? widget.playerService.volume).clamp(0.0, 1.0);
        final volume = _dragVolume ?? currentVol;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              // Mute button
              IconButton(
                onPressed: () => widget.playerService.toggleMute(),
                icon: Icon(
                  volume <= 0.01
                      ? Icons.volume_off_rounded
                      : Icons.volume_mute_rounded,
                  size: 22,
                  color: Colors.white70,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: volume <= 0.01 ? 'Unmute' : 'Mute',
              ),

              // Smooth zero-lag slider
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.20),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withValues(alpha: 0.15),
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                  ),
                  child: Slider(
                    value: volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) {
                      setState(() => _dragVolume = val);
                      widget.playerService.setVolume(val, persist: false);
                    },
                    onChangeEnd: (val) {
                      setState(() => _dragVolume = null);
                      widget.playerService.setVolume(val, persist: true);
                    },
                  ),
                ),
              ),

              // Max volume icon
              IconButton(
                onPressed: () => widget.playerService.setVolume(1.0, persist: true),
                icon: const Icon(
                  Icons.volume_up_rounded,
                  size: 22,
                  color: Colors.white70,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Maximum Volume',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ======================================================================
// Bottom Action Bar: Queue, Lyrics, Timer, Speaker Pill (Screenshot 3)
// ======================================================================

class _ArchiveTuneBottomBar extends StatelessWidget {
  final VoidCallback onToggleQueue;
  final VoidCallback onToggleLyrics;
  final VoidCallback onSleepTimerTap;
  final bool sleepTimerActive;
  final Color accentColor;

  const _ArchiveTuneBottomBar({
    required this.onToggleQueue,
    required this.onToggleLyrics,
    required this.onSleepTimerTap,
    required this.sleepTimerActive,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left icons: Queue, Lyrics, Sleep Timer
          Row(
            children: [
              // 1. Queue list icon
              _BottomIconChip(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: 'Queue',
                onTap: onToggleQueue,
              ),
              const SizedBox(width: 8),

              // 2. Lyrics button (Screenshot 3 & User Request)
              _BottomIconChip(
                icon: Icons.chat_bubble_outline_rounded,
                tooltip: 'Synchronized Lyrics',
                onTap: onToggleLyrics,
              ),
              const SizedBox(width: 8),

              // 3. Sleep timer moon icon
              _BottomIconChip(
                icon: sleepTimerActive
                    ? Icons.bedtime_rounded
                    : Icons.bedtime_outlined,
                iconColor: sleepTimerActive ? accentColor : Colors.white70,
                tooltip: 'Sleep Timer',
                onTap: onSleepTimerTap,
              ),
            ],
          ),

          // Right: Speaker output badge (Screenshot 3)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.speaker_phone_rounded,
                    size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Speaker',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomIconChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String tooltip;
  final VoidCallback onTap;

  const _BottomIconChip({
    required this.icon,
    this.iconColor = Colors.white70,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: iconColor, size: 20),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// Synchronized Lyrics Screen with Romanization (Matching Screenshot 4)
// ======================================================================

class _LyricsView extends StatefulWidget {
  final Track track;
  final PlayerService playerService;
  final Color accentColor;
  final SettingsService? settingsService;
  final VoidCallback onClose;

  const _LyricsView({
    super.key,
    required this.track,
    required this.playerService,
    required this.accentColor,
    this.settingsService,
    required this.onClose,
  });

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  StreamSubscription<Duration>? _posSub;
  LyricsData? _lyrics;
  bool _loading = true;
  int _activeLineIndex = -1;
  int _lyricsOffsetMs = 0;
  bool _romanizeEnabled = true;
  bool _translationEnabled = true;
  bool _userIsScrolling = false;
  Timer? _resumeAutoScrollTimer;

  @override
  void initState() {
    super.initState();
    widget.settingsService?.addListener(_onSettingsUpdated);
    _lyricsOffsetMs = widget.settingsService?.getLyricsOffsetMs(widget.track.id) ?? 0;
    _romanizeEnabled = widget.settingsService?.showRomanizedLyrics ?? true;
    _translationEnabled = widget.settingsService?.showTranslatedLyrics ?? true;
    _fetchLyrics();
    _posSub = widget.playerService.positionStream.listen(_onPositionUpdated);
  }

  void _onSettingsUpdated() {
    if (!mounted) return;
    setState(() {
      _romanizeEnabled = widget.settingsService?.showRomanizedLyrics ?? true;
      _translationEnabled = widget.settingsService?.showTranslatedLyrics ?? true;
    });
  }

  @override
  void didUpdateWidget(covariant _LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _lyricsOffsetMs = widget.settingsService?.getLyricsOffsetMs(widget.track.id) ?? 0;
      _fetchLyrics();
    }
  }

  @override
  void dispose() {
    widget.settingsService?.removeListener(_onSettingsUpdated);
    _resumeAutoScrollTimer?.cancel();
    _posSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchLyrics({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _lineKeys.clear();
    });
    final data = await LyricsService.instance.fetchLyrics(
      widget.track,
      settingsService: widget.settingsService,
      forceRefresh: forceRefresh,
    );
    if (mounted) {
      setState(() {
        _lyrics = data;
        _loading = false;
      });
      _onPositionUpdated(widget.playerService.position);
    }
  }

  void _showLyricsTimingSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141318),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final offsetSeconds = (_lyricsOffsetMs / 1000.0);
            final sign = offsetSeconds > 0 ? '+' : '';
            final offsetLabel = '$sign${offsetSeconds.toStringAsFixed(1)}s';

            void adjust(int deltaMs) {
              final newOffset = _lyricsOffsetMs + deltaMs;
              setState(() {
                _lyricsOffsetMs = newOffset;
              });
              setSheetState(() {});
              widget.settingsService?.setLyricsOffsetMs(widget.track.id, newOffset);
              _onPositionUpdated(widget.playerService.position);
            }

            void setExplicit(int newOffset) {
              setState(() {
                _lyricsOffsetMs = newOffset;
              });
              setSheetState(() {});
              widget.settingsService?.setLyricsOffsetMs(widget.track.id, newOffset);
              _onPositionUpdated(widget.playerService.position);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Adjust Lyrics Timing',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Shift lyrics earlier or later to match vocals (saved for this track)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    // Current Offset Display Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _lyricsOffsetMs != 0
                              ? widget.accentColor.withValues(alpha: 0.6)
                              : Colors.white12,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 22,
                            color: _lyricsOffsetMs != 0 ? widget.accentColor : Colors.white70,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            offsetLabel,
                            style: TextStyle(
                              color: _lyricsOffsetMs != 0 ? widget.accentColor : Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              fontFeatures: const [ui.FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Quick Adjustment Row: Earlier
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _timingButton('-5s', () => adjust(-5000)),
                        _timingButton('-1s', () => adjust(-1000)),
                        _timingButton('-0.5s', () => adjust(-500)),
                        _timingButton('-0.1s', () => adjust(-100)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Quick Adjustment Row: Later
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _timingButton('+0.1s', () => adjust(100)),
                        _timingButton('+0.5s', () => adjust(500)),
                        _timingButton('+1s', () => adjust(1000)),
                        _timingButton('+5s', () => adjust(5000)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Reset Button
                    if (_lyricsOffsetMs != 0)
                      TextButton.icon(
                        onPressed: () => setExplicit(0),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18, color: Colors.white70),
                        label: const Text(
                          'Reset Timing (0.0s)',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _timingButton(String label, VoidCallback onPressed) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _showProviderPickerSheet(BuildContext context) {
    final variants = _lyrics?.providerVariants ?? {};
    final currentSource = _lyrics?.source ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141318),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Switch Lyrics Provider',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (variants.isEmpty)
                  ListTile(
                    title: Text(currentSource, style: const TextStyle(color: Colors.white)),
                    subtitle: const Text('Current active provider', style: TextStyle(color: Colors.white54)),
                    trailing: Icon(Icons.check, color: widget.accentColor),
                  )
                else
                  ...variants.entries.map((entry) {
                    final isSelected = entry.key == currentSource;
                    final isSynced = entry.value.isSynced;
                    return ListTile(
                      leading: Icon(
                        isSynced ? Icons.sync_rounded : Icons.notes_rounded,
                        color: isSelected ? widget.accentColor : Colors.white70,
                      ),
                      title: Text(
                        entry.key,
                        style: TextStyle(
                          color: isSelected ? widget.accentColor : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        isSynced ? 'Synchronized (${entry.value.lines.length} lines)' : 'Plain text',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      trailing: isSelected ? Icon(Icons.check, color: widget.accentColor) : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        if (!isSelected) {
                          setState(() {
                            _lyrics = entry.value.copyWith(providerVariants: variants);
                          });
                          _onPositionUpdated(widget.playerService.position);
                        }
                      },
                    );
                  }),
                const Divider(color: Colors.white12),
                ListTile(
                  leading: const Icon(Icons.search_rounded, color: Colors.white70),
                  title: const Text('Fetch NetEase Lyrics', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _loading = true);
                    final fresh = await LyricsService.instance.fetchLyricsWithProvider(
                      widget.track,
                      'NetEase',
                      settingsService: widget.settingsService,
                    );
                    if (mounted) {
                      setState(() {
                        if (fresh != null) _lyrics = fresh;
                        _loading = false;
                      });
                      _onPositionUpdated(widget.playerService.position);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.search_rounded, color: Colors.white70),
                  title: const Text('Fetch SimpMusic Lyrics', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _loading = true);
                    final fresh = await LyricsService.instance.fetchLyricsWithProvider(
                      widget.track,
                      'SimpMusic',
                      settingsService: widget.settingsService,
                    );
                    if (mounted) {
                      setState(() {
                        if (fresh != null) _lyrics = fresh;
                        _loading = false;
                      });
                      _onPositionUpdated(widget.playerService.position);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.search_rounded, color: Colors.white70),
                  title: const Text('Fetch KuGou Lyrics', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _loading = true);
                    final fresh = await LyricsService.instance.fetchLyricsWithProvider(
                      widget.track,
                      'KuGou',
                      settingsService: widget.settingsService,
                    );
                    if (mounted) {
                      setState(() {
                        if (fresh != null) _lyrics = fresh;
                        _loading = false;
                      });
                      _onPositionUpdated(widget.playerService.position);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.search_rounded, color: Colors.white70),
                  title: const Text('Fetch LRCLIB Lyrics', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    setState(() => _loading = true);
                    final fresh = await LyricsService.instance.fetchLyricsWithProvider(
                      widget.track,
                      'LRCLIB',
                      settingsService: widget.settingsService,
                    );
                    if (mounted) {
                      setState(() {
                        if (fresh != null) _lyrics = fresh;
                        _loading = false;
                      });
                      _onPositionUpdated(widget.playerService.position);
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
    );
  }

  void _showLyricsOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141318),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final autoScroll = widget.settingsService?.autoScrollLyrics ?? true;
            final offsetSeconds = (_lyricsOffsetMs / 1000.0);
            final sign = offsetSeconds > 0 ? '+' : '';
            final offsetLabel = _lyricsOffsetMs != 0 ? '$sign${offsetSeconds.toStringAsFixed(1)}s' : '0.0s';
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Lyrics Options',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined, color: Colors.white70),
                        title: const Text('Adjust Lyrics Timing',
                            style: TextStyle(color: Colors.white, fontSize: 15)),
                        subtitle: Text('Current offset: $offsetLabel',
                            style: TextStyle(
                              color: _lyricsOffsetMs != 0 ? widget.accentColor : Colors.white54,
                              fontSize: 12,
                            )),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _lyricsOffsetMs != 0
                                ? widget.accentColor.withValues(alpha: 0.2)
                                : Colors.white12,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            offsetLabel,
                            style: TextStyle(
                              color: _lyricsOffsetMs != 0 ? widget.accentColor : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showLyricsTimingSheet(context);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.dns_rounded, color: Colors.white70),
                        title: const Text('Switch Lyrics Provider',
                            style: TextStyle(color: Colors.white, fontSize: 15)),
                        subtitle: Text('Source: ${_lyrics?.source ?? "Auto"}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showProviderPickerSheet(context);
                        },
                      ),
                      const Divider(color: Colors.white12),
                      SwitchListTile(
                        activeThumbColor: widget.accentColor,
                        secondary: const Icon(Icons.translate_rounded, color: Colors.white70),
                        title: const Text('Show Romanization (Romaji)',
                            style: TextStyle(color: Colors.white, fontSize: 15)),
                        subtitle: const Text('Displays pronunciation above original lyrics',
                            style: TextStyle(color: Colors.white54, fontSize: 12)),
                        value: _romanizeEnabled,
                        onChanged: (val) {
                          setSheetState(() => _romanizeEnabled = val);
                          setState(() => _romanizeEnabled = val);
                          widget.settingsService?.setShowRomanizedLyrics(val);
                        },
                      ),
                      SwitchListTile(
                        activeThumbColor: widget.accentColor,
                        secondary: const Icon(Icons.g_translate_rounded, color: Colors.white70),
                        title: const Text('Show English Translation',
                            style: TextStyle(color: Colors.white, fontSize: 15)),
                        subtitle: const Text('Displays translated lyrics below original text',
                            style: TextStyle(color: Colors.white54, fontSize: 12)),
                        value: _translationEnabled,
                        onChanged: (val) {
                          setSheetState(() => _translationEnabled = val);
                          setState(() => _translationEnabled = val);
                          widget.settingsService?.setShowTranslatedLyrics(val);
                        },
                      ),
                      SwitchListTile(
                        activeThumbColor: widget.accentColor,
                        secondary: const Icon(Icons.vertical_align_center_rounded, color: Colors.white70),
                        title: const Text('Auto-scroll with music',
                            style: TextStyle(color: Colors.white, fontSize: 15)),
                        subtitle: const Text('Keeps the active lyric line centered',
                            style: TextStyle(color: Colors.white54, fontSize: 12)),
                        value: autoScroll,
                        onChanged: (val) {
                          widget.settingsService?.setAutoScrollLyrics(val);
                          setSheetState(() {});
                          setState(() {});
                        },
                      ),
                      const Divider(color: Colors.white12),
                      ListTile(
                        leading: const Icon(Icons.tune_rounded, color: Colors.white70),
                        title: const Text('Lyrics Settings',
                            style: TextStyle(color: Colors.white, fontSize: 15)),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (widget.settingsService != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LyricsSettingsScreen(
                                  settingsService: widget.settingsService!,
                                ),
                              ),
                            ).then((_) {
                              if (mounted) setState(() {});
                            });
                          }
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.refresh_rounded, color: Colors.white70),
                        title: const Text('Refresh Lyrics',
                            style: TextStyle(color: Colors.white, fontSize: 15)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _fetchLyrics(forceRefresh: true);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.copy_rounded, color: Colors.white70),
                        title: const Text('Copy Lyrics',
                            style: TextStyle(color: Colors.white, fontSize: 15)),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (_lyrics != null && _lyrics!.lines.isNotEmpty) {
                            final text = _lyrics!.lines.map((l) => l.text).join('\n');
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Lyrics copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _onPositionUpdated(Duration position) {
    if (_lyrics == null || _lyrics!.lines.isEmpty) return;
    if (!_lyrics!.isSynced) {
      if (_activeLineIndex != -1) {
        setState(() => _activeLineIndex = -1);
      }
      return;
    }

    final lines = _lyrics!.lines;
    final effectiveMs = position.inMilliseconds - _lyricsOffsetMs;
    final effectivePosition = Duration(milliseconds: effectiveMs < 0 ? 0 : effectiveMs);

    // Find latest line matching effective position
    int newIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (effectivePosition >= lines[i].timestamp) {
        newIndex = i;
      } else {
        break;
      }
    }

    if (newIndex != _activeLineIndex) {
      setState(() {
        _activeLineIndex = newIndex;
      });
      _scrollToActiveLine();
    }
  }

  void _scrollToActiveLine({bool force = false}) {
    if (!_scrollController.hasClients || _activeLineIndex < 0) return;
    if (_lyrics == null || _lyrics!.lines.isEmpty) return;
    if (!force && _userIsScrolling) return;

    final autoScroll = widget.settingsService?.autoScrollLyrics ?? true;
    if (!force && !autoScroll) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final key = _lineKeys[_activeLineIndex];
      final targetContext = key?.currentContext;

      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.35, // Places the highlighted lyric line 35% from the top
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      } else if (_lyrics!.lines.isNotEmpty) {
        final targetFraction = (_activeLineIndex / _lyrics!.lines.length).clamp(0.0, 1.0);
        final targetOffset = targetFraction * _scrollController.position.maxScrollExtent;
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ).then((_) {
          if (mounted) {
            final ctx = _lineKeys[_activeLineIndex]?.currentContext;
            if (ctx != null && ctx.mounted) {
              Scrollable.ensureVisible(
                ctx,
                alignment: 0.35,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
              );
            }
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final coverUrl = (track.localThumbnailPath != null && track.localThumbnailPath!.isNotEmpty)
        ? track.localThumbnailPath!
        : (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
            ? track.thumbnailUrl!
            : 'https://img.youtube.com/vi/${track.id}/hqdefault.jpg';

    final textSize = widget.settingsService?.lyricsTextSize ?? 26.0;
    final lineSpacing = widget.settingsService?.lyricsLineSpacing ?? 1.3;
    final blurEnabled = widget.settingsService?.blurLyricsLines ?? true;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          children: [
            // Top pull handle for intuitive gesture
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // 1. Top Header: Mini thumb, Title/Artist, Romanize toggle, Close button, Lyrics Settings
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  // Mini thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _buildCoverArt(
                      coverUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        width: 44,
                        height: 44,
                        color: Colors.white12,
                        child: const Icon(Icons.music_note, color: Colors.white54),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title and artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.author,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Timing adjust quick button
                  _CircularButton(
                    icon: Icons.timer_outlined,
                    iconColor: _lyricsOffsetMs != 0 ? widget.accentColor : Colors.white70,
                    onTap: () => _showLyricsTimingSheet(context),
                  ),

                  const SizedBox(width: 8),

                  // Close lyrics button in circular chip (Screenshot 1: (X))
                  _CircularButton(
                    icon: Icons.close_rounded,
                    onTap: widget.onClose,
                  ),

                  const SizedBox(width: 8),

                  // Lyrics Options menu button in circular chip (Screenshot 1: (...))
                  _CircularButton(
                    icon: Icons.more_horiz_rounded,
                    onTap: () => _showLyricsOptionsMenu(context),
                  ),
                ],
              ),
            ),

            // Provider & Timing offset indicator pill row
            if (_lyrics != null && _lyrics!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showProviderPickerSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _lyrics!.isSynced ? Icons.sync_rounded : Icons.notes_rounded,
                              size: 13,
                              color: widget.accentColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _lyrics!.source ?? 'Synced',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white54),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showLyricsTimingSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _lyricsOffsetMs != 0
                              ? widget.accentColor.withValues(alpha: 0.16)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: _lyricsOffsetMs != 0
                              ? Border.all(color: widget.accentColor.withValues(alpha: 0.45), width: 1)
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 13,
                              color: _lyricsOffsetMs != 0 ? widget.accentColor : Colors.white54,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _lyricsOffsetMs != 0
                                  ? '${_lyricsOffsetMs > 0 ? '+' : ''}${(_lyricsOffsetMs / 1000).toStringAsFixed(1)}s'
                                  : 'Adjust Timing',
                              style: TextStyle(
                                color: _lyricsOffsetMs != 0 ? widget.accentColor : Colors.white60,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 2. Synced Lyrics List with Accurate EnsureVisible & Animations
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white70),
                          SizedBox(height: 16),
                          Text(
                            'Fetching synchronized lyrics…',
                            style: TextStyle(color: Colors.white60, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : (_lyrics == null || _lyrics!.isEmpty)
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lyrics_outlined,
                                  size: 48, color: Colors.white38),
                              const SizedBox(height: 12),
                              const Text(
                                'No synchronized lyrics available',
                                style: TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _fetchLyrics,
                                icon: const Icon(Icons.refresh, color: Colors.white70),
                                label: const Text('Retry',
                                    style: TextStyle(color: Colors.white70)),
                              ),
                            ],
                          ),
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is UserScrollNotification &&
                                notification.direction != ScrollDirection.idle) {
                              if (!_userIsScrolling) {
                                setState(() => _userIsScrolling = true);
                              }
                              _resumeAutoScrollTimer?.cancel();
                              _resumeAutoScrollTimer = Timer(const Duration(seconds: 4), () {
                                if (mounted) {
                                  setState(() => _userIsScrolling = false);
                                  _scrollToActiveLine();
                                }
                              });
                            }
                            return false;
                          },
                          child: Stack(
                            children: [
                              ListView.builder(
                                controller: _scrollController,
                                // ignore: deprecated_member_use
                                cacheExtent: 3000.0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 36,
                                ),
                                itemCount: _lyrics!.lines.length,
                                itemBuilder: (context, index) {
                                  final line = _lyrics!.lines[index];
                                  final isSynced = _lyrics?.isSynced ?? true;
                                  final isActive = isSynced && (index == _activeLineIndex);

                                  // Dynamic User Theme & Lyrics Colors
                                  final activeColor = widget.settingsService?.lyricsActiveColor ?? Colors.white;
                                  final inactiveColor = widget.settingsService?.lyricsInactiveColor ?? Colors.white.withValues(alpha: 0.35);
                                  final glowColor = widget.settingsService?.lyricsGlowColor ?? widget.accentColor;

                                  // Animation Style & Mode parameters
                                  final lyricsMode = widget.settingsService?.lyricsMode ?? 'V2';
                                  final animStyle = widget.settingsService?.lyricsAnimationStyle ?? 'Fluid Apple Music';

                                  final Duration animDuration;
                                  final Curve animCurve;
                                  final Offset slideOffset;
                                  final double scaleFactor;
                                  final List<Shadow>? textShadows;

                                  if (lyricsMode == 'Standard' || animStyle == 'Classic') {
                                    animDuration = const Duration(milliseconds: 220);
                                    animCurve = Curves.easeInOut;
                                    slideOffset = Offset.zero;
                                    scaleFactor = 1.0;
                                    textShadows = isActive
                                        ? [
                                            Shadow(
                                              color: glowColor.withValues(alpha: 0.35),
                                              blurRadius: 10,
                                            ),
                                          ]
                                        : null;
                                  } else if (animStyle == 'Fade & Slide') {
                                    animDuration = const Duration(milliseconds: 400);
                                    animCurve = Curves.easeOutCubic;
                                    slideOffset = isActive ? Offset.zero : const Offset(-0.065, 0.0);
                                    scaleFactor = isActive ? 1.05 : 0.94;
                                    textShadows = isActive
                                        ? [
                                            Shadow(
                                              color: glowColor.withValues(alpha: 0.65),
                                              blurRadius: 18,
                                            ),
                                            Shadow(
                                              color: activeColor.withValues(alpha: 0.40),
                                              blurRadius: 8,
                                            ),
                                          ]
                                        : null;
                                  } else if (animStyle == 'Karaoke Glow') {
                                    animDuration = const Duration(milliseconds: 320);
                                    animCurve = Curves.easeOutQuad;
                                    slideOffset = isActive ? Offset.zero : const Offset(-0.02, 0.0);
                                    scaleFactor = isActive ? 1.06 : 0.95;
                                    textShadows = isActive
                                        ? [
                                            Shadow(
                                              color: glowColor.withValues(alpha: 0.92),
                                              blurRadius: 28,
                                            ),
                                            Shadow(
                                              color: glowColor.withValues(alpha: 0.70),
                                              blurRadius: 14,
                                            ),
                                            Shadow(
                                              color: activeColor.withValues(alpha: 0.65),
                                              blurRadius: 6,
                                            ),
                                          ]
                                        : null;
                                  } else {
                                    // Fluid Apple Music: Signature spring expansion and dynamic glow
                                    animDuration = const Duration(milliseconds: 360);
                                    animCurve = Curves.easeOutCubic;
                                    slideOffset = isActive ? Offset.zero : const Offset(-0.025, 0.0);
                                    scaleFactor = isActive ? 1.07 : 0.93;
                                    textShadows = isActive
                                        ? [
                                            Shadow(
                                              color: glowColor.withValues(alpha: 0.68),
                                              blurRadius: 22,
                                            ),
                                            Shadow(
                                              color: activeColor.withValues(alpha: 0.45),
                                              blurRadius: 10,
                                            ),
                                          ]
                                        : null;
                                  }

                                  // Dynamic Romanization with robust Korean & Chinese fallback
                                  final jap = widget.settingsService?.romanizeJapanese ?? true;
                                  final kor = widget.settingsService?.romanizeKorean ?? true;
                                  final chn = widget.settingsService?.romanizeChinese ?? true;
                                  final hin = widget.settingsService?.romanizeHindi ?? true;
                                  final showRomazi = widget.settingsService?.showRomanizedLyrics ?? true;

                                  String? romanized = line.romanizedText;
                                  if (romanized == null ||
                                      romanized.trim().isEmpty ||
                                      romanized.trim().toLowerCase() == line.text.trim().toLowerCase()) {
                                    if (LyricsRomanizer.hasForeign(line.text, japanese: jap, korean: kor, chinese: chn, hindi: hin)) {
                                      romanized = LyricsRomanizer.romanize(line.text, japanese: jap, korean: kor, chinese: chn, hindi: hin);
                                    }
                                  }

                                  bool langAllowed = true;
                                  final isKorean = RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]').hasMatch(line.text);
                                  final isJapanese = RegExp(r'[\u3040-\u30FF]').hasMatch(line.text);
                                  final isChinese = !isJapanese && RegExp(r'[\u4E00-\u9FFF]').hasMatch(line.text);
                                  final isHindi = RegExp(r'[\u0900-\u097F]').hasMatch(line.text);
                                  if (isKorean && !kor) langAllowed = false;
                                  if (isJapanese && !jap) langAllowed = false;
                                  if (isChinese && !chn) langAllowed = false;
                                  if (isHindi && !hin) langAllowed = false;

                                  final hasRomanized = showRomazi &&
                                      langAllowed &&
                                      romanized != null &&
                                      romanized.trim().isNotEmpty &&
                                      romanized.trim().toLowerCase() != line.text.trim().toLowerCase();

                                  final hasTranslation = _translationEnabled &&
                                      line.translationText != null &&
                                      line.translationText!.trim().isNotEmpty &&
                                      line.translationText!.trim().toLowerCase() != line.text.trim().toLowerCase();

                                  Widget lineContent = Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 1. Romaji pronunciation line ABOVE original text (ArchiveTune style!)
                                      if (hasRomanized)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 3),
                                          child: AnimatedDefaultTextStyle(
                                            duration: animDuration,
                                            curve: animCurve,
                                            style: TextStyle(
                                              color: (isActive || !isSynced)
                                                  ? activeColor.withValues(alpha: 0.75)
                                                  : inactiveColor.withValues(alpha: 0.70),
                                              fontSize: isActive ? 12.5 : 11.5,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: 0.3,
                                            ),
                                            child: Text(romanized),
                                          ),
                                        ),

                                      // 2. Main original lyric line
                                      AnimatedDefaultTextStyle(
                                        duration: animDuration,
                                        curve: animCurve,
                                        style: TextStyle(
                                          color: (isActive || !isSynced)
                                              ? activeColor
                                              : inactiveColor,
                                          fontSize: isActive ? textSize : (isSynced ? textSize * 0.78 : textSize * 0.9),
                                          fontWeight: (isActive || !isSynced)
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          height: lineSpacing,
                                          shadows: textShadows,
                                        ),
                                        child: Text(line.text),
                                      ),

                                      // 3. Translated lyric line BELOW original text (ArchiveTune style!)
                                      if (hasTranslation)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 3),
                                          child: AnimatedDefaultTextStyle(
                                            duration: animDuration,
                                            curve: animCurve,
                                            style: TextStyle(
                                              color: (isActive || !isSynced)
                                                  ? activeColor.withValues(alpha: 0.75)
                                                  : inactiveColor.withValues(alpha: 0.70),
                                              fontSize: isActive ? 14.5 : 12.5,
                                              fontWeight: FontWeight.w400,
                                              height: 1.25,
                                            ),
                                            child: Text(line.translationText!),
                                          ),
                                        ),
                                    ],
                                  );

                                  if (blurEnabled && !isActive && isSynced) {
                                    lineContent = ImageFiltered(
                                      imageFilter: ui.ImageFilter.blur(sigmaX: 0.85, sigmaY: 0.85),
                                      child: lineContent,
                                    );
                                  }

                                  return GestureDetector(
                                    key: _lineKeys.putIfAbsent(index, () => GlobalKey()),
                                    onTap: () {
                                      final allowClick =
                                          widget.settingsService?.changeLyricsOnClick ?? true;
                                      if (allowClick && isSynced) {
                                        final targetMs = line.timestamp.inMilliseconds + _lyricsOffsetMs;
                                        widget.playerService.seek(Duration(milliseconds: targetMs < 0 ? 0 : targetMs));
                                      }
                                    },
                                    child: AnimatedSlide(
                                      duration: animDuration,
                                      curve: animCurve,
                                      offset: slideOffset,
                                      child: AnimatedScale(
                                        scale: scaleFactor,
                                        alignment: Alignment.centerLeft,
                                        duration: animDuration,
                                        curve: animCurve,
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(vertical: 8),
                                          child: lineContent,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),

                              // Floating "Resume Sync" chip when user manually scrolled
                              if (_userIsScrolling &&
                                  (widget.settingsService?.autoScrollLyrics ?? true))
                                Positioned(
                                  bottom: 12,
                                  right: 20,
                                  child: GestureDetector(
                                    onTap: () {
                                      _resumeAutoScrollTimer?.cancel();
                                      setState(() => _userIsScrolling = false);
                                      _scrollToActiveLine(force: true);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: widget.accentColor,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.5),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.sync_rounded,
                                            size: 16,
                                            color: Colors.black,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Resume Sync',
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),

            // 3. Bottom controls in Lyrics Screen (Screenshot 4)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress bar
                  _LyricsSeekBar(playerService: widget.playerService),

                  // Transport row
                  _ArchiveTuneTransport(
                    playerService: widget.playerService,
                    accentColor: widget.accentColor,
                  ),

                  // Volume slider
                  _ArchiveTuneVolumeBar(
                    playerService: widget.playerService,
                    accentColor: widget.accentColor,
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Lyrics Screen Progress Bar with remaining time (-1:18)
// ======================================================================

class _LyricsSeekBar extends StatelessWidget {
  final PlayerService playerService;

  const _LyricsSeekBar({required this.playerService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: playerService.positionStream,
      initialData: playerService.position,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: playerService.durationStream,
          initialData: playerService.duration,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds > 0
                ? duration.inMilliseconds.toDouble()
                : 1.0;
            final posMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);
            final remaining = duration > position
                ? duration - position
                : Duration.zero;

            return Column(
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withValues(alpha: 0.15),
                    trackHeight: 3.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  ),
                  child: Slider(
                    value: posMs,
                    max: maxMs,
                    onChanged: (v) {
                      playerService.seek(Duration(milliseconds: v.toInt()));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(position),
                        style: const TextStyle(
                          color: Color(0xFFB3B3B3),
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '-${_fmt(remaining)}',
                        style: const TextStyle(
                          color: Color(0xFFB3B3B3),
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _fmt(Duration d) {
    final min = d.inMinutes.remainder(60).toString();
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$min:$sec';
    return '$min:$sec';
  }
}

// ======================================================================
// Top bar with close chevron and queue toggle
// ======================================================================

class _TopBar extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onClose;
  final bool showQueue;
  final VoidCallback onToggleQueue;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;

  const _TopBar({
    required this.accentColor,
    required this.onClose,
    required this.showQueue,
    required this.onToggleQueue,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle pill for intuitive swipe down
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 32, color: Colors.white),
                  tooltip: 'Swipe down or tap to dismiss',
                ),
                const Spacer(),
                const Text(
                  'Now Playing',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onToggleQueue,
                  icon: Icon(
                    showQueue ? Icons.music_note_rounded : Icons.queue_music_rounded,
                    color: showQueue ? accentColor : Colors.white70,
                  ),
                  tooltip: showQueue ? 'Show player' : 'Show queue',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Queue panel — list of upcoming tracks
// ======================================================================

class _QueuePanel extends StatelessWidget {
  final PlayerService playerService;
  final Color accentColor;

  const _QueuePanel({required this.playerService, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final queue = playerService.queue;
    final current = playerService.currentTrack;

    if (queue.isEmpty) {
      return const Center(
        child: Text(
          'Queue is empty',
          style: TextStyle(color: Color(0xFF707070), fontSize: 16),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            'Playing next (${queue.length})',
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: queue.length,
            itemBuilder: (context, index) {
              final track = queue[index];
              final isCurrent = track.id == current?.id;

              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: isCurrent ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _buildCoverArt(
                      (track.localThumbnailPath != null && track.localThumbnailPath!.isNotEmpty)
                          ? track.localThumbnailPath!
                          : (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
                              ? track.thumbnailUrl!
                              : 'https://img.youtube.com/vi/${track.id}/hqdefault.jpg',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        width: 44,
                        height: 44,
                        color: Colors.white12,
                        child: const Icon(Icons.music_note,
                            size: 18, color: Colors.white54),
                      ),
                    ),
                  ),
                  title: Text(
                    track.title,
                    style: TextStyle(
                      color: isCurrent ? accentColor : const Color(0xFFE6E6E6),
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.author,
                    style: const TextStyle(
                      color: Color(0xFF999999),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isCurrent
                      ? Icon(Icons.equalizer, color: accentColor, size: 20)
                      : null,
                  onTap: () {
                    playerService.playTrackAt(index);
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
