import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:finaudio/services/google_auth_service.dart';
import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/playlist_service.dart';
import 'package:finaudio/services/settings_service.dart';
import 'package:finaudio/ui/now_playing_screen.dart';
import 'package:finaudio/widgets/add_to_playlist_sheet.dart';

/// A compact, persistent now-playing bar shown at the bottom of the app when
/// a track is loaded. Shows thumbnail, title, artist, progress, play/pause, next.
class NowPlayingBar extends StatelessWidget {
  final Track track;
  final Color accentColor;
  final PlayerService playerService;
  final GoogleAuthService? authService;
  final PlaylistService? playlistService;
  final SettingsService? settingsService;

  const NowPlayingBar({
    super.key,
    required this.track,
    required this.accentColor,
    required this.playerService,
    this.authService,
    this.playlistService,
    this.settingsService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onAccent = accentColor.computeLuminance() > 0.5
        ? const Color(0xFF101010)
        : Colors.white;

    final hasWallpaper = settingsService != null &&
        settingsService!.hasWallpaper &&
        settingsService!.wallpaperPath != null &&
        File(settingsService!.wallpaperPath!).existsSync();
    final cardOpacity = hasWallpaper ? settingsService!.wallpaperCardOpacity : 1.0;
    final barColor = settingsService?.playerBarColor ?? theme.colorScheme.surfaceContainerHighest;
    final effectiveBarColor = barColor.withValues(alpha: cardOpacity);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: effectiveBarColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main row
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (_, _, _) => NowPlayingScreen(
                      playerService: playerService,
                      accentColor: accentColor,
                      authService: authService,
                      playlistService: playlistService,
                      settingsService: settingsService,
                    ),
                    transitionsBuilder: (_, anim, _, child) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOut,
                          ),
                        ),
                        child: child,
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 300),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    // Cover art
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: _buildBarThumbnail(track, accentColor, size: 44),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Title + artist
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          StreamBuilder<bool>(
                            stream: playerService.playingStream,
                            initialData: playerService.isPlaying,
                            builder: (context, playSnap) {
                              final isPlaying = playSnap.data ?? false;
                              return Row(
                                children: [
                                  if (!isPlaying) ...[
                                    Container(
                                      margin: const EdgeInsets.only(right: 5),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.onSurfaceVariant.withAlpha(35),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'PAUSED',
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurfaceVariant,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                  Expanded(
                                    child: Text(
                                      track.author,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Play/pause
                    GestureDetector(
                      onTap: () => playerService.togglePlayPause(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: StreamBuilder<bool>(
                          stream: playerService.playingStream,
                          initialData: playerService.isPlaying,
                          builder: (context, playSnap) {
                            final isPlaying = playSnap.data ?? false;
                            return Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 22,
                              color: onAccent,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Next
                    IconButton(
                      onPressed: () => playerService.nextTrack(),
                      icon: Icon(
                        Icons.skip_next_rounded,
                        size: 22,
                        color: theme.colorScheme.onSurface,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Progress bar
          StreamBuilder<Duration>(
            stream: playerService.positionStream,
            initialData: playerService.position,
            builder: (context, posSnap) {
              final pos = posSnap.data ?? Duration.zero;
              final dur = playerService.duration;
              final maxMs =
                  dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
              final posMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs);
              final fraction = posMs / maxMs;

              return ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                child: LinearProgressIndicator(
                  value: fraction,
                  backgroundColor:
                      theme.colorScheme.surface.withAlpha(120),
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  minHeight: 2,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A full-featured, persistent player bar designed for desktop screens (Windows / Linux / macOS).
/// Spans the bottom of the window (height: 88px) with 3 sections:
/// - Left: Track info (thumbnail, title, artist, favorite toggle, add to playlist)
/// - Center: Playback controls (shuffle, prev, play/pause, next, loop) + scrubbing seekbar with timestamps
/// - Right: Queue, lyrics / now-playing expand, mute toggle, and volume slider.
class DesktopPlayerBar extends StatefulWidget {
  final Track? track;
  final Color accentColor;
  final PlayerService playerService;
  final GoogleAuthService? authService;
  final PlaylistService? playlistService;
  final SettingsService? settingsService;

  const DesktopPlayerBar({
    super.key,
    required this.track,
    required this.accentColor,
    required this.playerService,
    this.authService,
    this.playlistService,
    this.settingsService,
  });

  @override
  State<DesktopPlayerBar> createState() => _DesktopPlayerBarState();
}

class _DesktopPlayerBarState extends State<DesktopPlayerBar> {
  double? _dragValue;
  double? _dragVolume;

  @override
  void initState() {
    super.initState();
    widget.playlistService?.addListener(_onPlaylistChanged);
    widget.settingsService?.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.playlistService?.removeListener(_onPlaylistChanged);
    widget.settingsService?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onPlaylistChanged() {
    if (mounted) setState(() {});
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = d.inMinutes;
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showQueueModal(BuildContext context) {
    final theme = Theme.of(context);
    final queue = widget.playerService.queue;
    final current = widget.playerService.currentTrack;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: theme.colorScheme.surface,
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
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                if (queue.isEmpty && current == null)
                  const Expanded(
                    child: Center(child: Text('Queue is empty')),
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
                              child: _buildBarThumbnail(item, widget.accentColor, size: 40),
                            ),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              color: isCurrent ? widget.accentColor : theme.colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            item.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = widget.track;
    final onAccent = widget.accentColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    final isLiked = track != null &&
        (widget.playlistService?.isTrackLiked(track.id, track.title, track.author) ?? false);

    final hasWallpaper = widget.settingsService != null &&
        widget.settingsService!.hasWallpaper &&
        widget.settingsService!.wallpaperPath != null &&
        File(widget.settingsService!.wallpaperPath!).existsSync();
    final cardOpacity = hasWallpaper ? widget.settingsService!.wallpaperCardOpacity : 1.0;
    final barColor = widget.settingsService?.playerBarColor ?? theme.colorScheme.surface;
    final effectiveBarColor = barColor.withValues(alpha: cardOpacity);

    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: effectiveBarColor,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(50),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // -----------------------------------------------------------------
          // Left: Current Track Info
          // -----------------------------------------------------------------
          Expanded(
            flex: 3,
            child: track == null
                ? Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.music_note_rounded,
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nothing playing',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface.withAlpha(180),
                              ),
                            ),
                            Text(
                              'Select a track to start listening',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => NowPlayingScreen(
                                  playerService: widget.playerService,
                                  accentColor: widget.accentColor,
                                  authService: widget.authService,
                                  playlistService: widget.playlistService,
                                  settingsService: widget.settingsService,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 52,
                                    height: 52,
                                    child: _buildBarThumbnail(track, widget.accentColor, size: 52),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        track.author,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.onSurfaceVariant,
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
                      IconButton(
                        tooltip: isLiked ? 'Unlike' : 'Like',
                        icon: Icon(
                          isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isLiked ? widget.accentColor : theme.colorScheme.onSurface.withAlpha(160),
                          size: 20,
                        ),
                        onPressed: () async {
                          await widget.playlistService?.toggleLikeTrack(track.toLocalPlaylistTrack());
                          setState(() {});
                        },
                      ),
                      if (widget.playlistService != null)
                        IconButton(
                          tooltip: 'Add to playlist',
                          icon: Icon(
                            Icons.playlist_add_rounded,
                            color: theme.colorScheme.onSurface.withAlpha(160),
                            size: 22,
                          ),
                          onPressed: () {
                            showAddToPlaylistSheet(
                              context: context,
                              track: track.toLocalPlaylistTrack(),
                              playlistService: widget.playlistService!,
                              accentColor: widget.accentColor,
                            );
                          },
                        ),
                    ],
                  ),
          ),

          // -----------------------------------------------------------------
          // Center: Playback Controls & Progress Bar
          // -----------------------------------------------------------------
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Control Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Shuffle
                    StreamBuilder<bool>(
                      stream: widget.playerService.shuffleStream,
                      initialData: widget.playerService.shuffleEnabled,
                      builder: (context, snap) {
                        final isShuffle = snap.data ?? false;
                        return IconButton(
                          tooltip: 'Shuffle',
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: isShuffle ? widget.accentColor : theme.colorScheme.onSurface.withAlpha(160),
                            size: 19,
                          ),
                          onPressed: () => widget.playerService.toggleShuffle(),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // Previous
                    IconButton(
                      tooltip: 'Previous',
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        color: theme.colorScheme.onSurface,
                        size: 26,
                      ),
                      onPressed: () => widget.playerService.previousTrack(),
                    ),
                    const SizedBox(width: 8),
                    // Play / Pause
                    StreamBuilder<bool>(
                      stream: widget.playerService.playingStream,
                      initialData: widget.playerService.isPlaying,
                      builder: (context, snap) {
                        final isPlaying = snap.data ?? false;
                        return Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: widget.accentColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: widget.accentColor.withAlpha(70),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: isPlaying ? 'Pause' : 'Play',
                            icon: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: onAccent,
                              size: 24,
                            ),
                            onPressed: () => widget.playerService.togglePlayPause(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // Next
                    IconButton(
                      tooltip: 'Next',
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: theme.colorScheme.onSurface,
                        size: 26,
                      ),
                      onPressed: () => widget.playerService.nextTrack(),
                    ),
                    const SizedBox(width: 8),
                    // Loop Mode
                    StreamBuilder<LoopMode>(
                      stream: widget.playerService.loopModeStream,
                      initialData: widget.playerService.loopMode,
                      builder: (context, snap) {
                        final loopMode = snap.data ?? LoopMode.off;
                        final isLoopActive = loopMode != LoopMode.off;
                        final icon = loopMode == LoopMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded;
                        return IconButton(
                          tooltip: 'Loop: ${loopMode.name}',
                          icon: Icon(
                            icon,
                            color: isLoopActive ? widget.accentColor : theme.colorScheme.onSurface.withAlpha(160),
                            size: 19,
                          ),
                          onPressed: () => widget.playerService.cycleLoopMode(),
                        );
                      },
                    ),
                  ],
                ),

                // Interactive Seekbar
                StreamBuilder<Duration>(
                  stream: widget.playerService.positionStream,
                  initialData: widget.playerService.position,
                  builder: (context, posSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = widget.playerService.duration;
                    final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                    final currentMs = (_dragValue ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);

                    return SizedBox(
                      height: 22,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              _formatDuration(_dragValue != null
                                  ? Duration(milliseconds: _dragValue!.round())
                                  : pos),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3.5,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                activeTrackColor: widget.accentColor,
                                inactiveTrackColor: theme.colorScheme.onSurface.withAlpha(35),
                                thumbColor: widget.accentColor,
                              ),
                              child: Slider(
                                value: currentMs,
                                min: 0.0,
                                max: maxMs,
                                onChanged: (val) {
                                  setState(() => _dragValue = val);
                                },
                                onChangeEnd: (val) {
                                  widget.playerService.seek(Duration(milliseconds: val.round()));
                                  setState(() => _dragValue = null);
                                },
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text(
                              _formatDuration(dur),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // -----------------------------------------------------------------
          // Right: Queue, Fullscreen, Volume
          // -----------------------------------------------------------------
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Queue',
                  icon: Icon(
                    Icons.queue_music_rounded,
                    color: theme.colorScheme.onSurface.withAlpha(180),
                    size: 20,
                  ),
                  onPressed: () => _showQueueModal(context),
                ),
                IconButton(
                  tooltip: 'Now Playing Screen',
                  icon: Icon(
                    Icons.open_in_full_rounded,
                    color: theme.colorScheme.onSurface.withAlpha(180),
                    size: 18,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => NowPlayingScreen(
                          playerService: widget.playerService,
                          accentColor: widget.accentColor,
                          authService: widget.authService,
                          playlistService: widget.playlistService,
                          settingsService: widget.settingsService,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                // Volume Controls
                StreamBuilder<double>(
                  stream: widget.playerService.volumeStream,
                  initialData: widget.playerService.volume,
                  builder: (context, snap) {
                    final vol = snap.data ?? widget.playerService.volume;
                    final isMuted = vol <= 0.01;
                    final volIcon = isMuted
                        ? Icons.volume_off_rounded
                        : vol < 0.5
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded;

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: isMuted ? 'Unmute' : 'Mute',
                          icon: Icon(
                            volIcon,
                            color: theme.colorScheme.onSurface.withAlpha(180),
                            size: 20,
                          ),
                          onPressed: () => widget.playerService.toggleMute(),
                        ),
                        SizedBox(
                          width: 88,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                              activeTrackColor: widget.accentColor,
                              inactiveTrackColor: theme.colorScheme.onSurface.withAlpha(35),
                              thumbColor: widget.accentColor,
                            ),
                            child: Slider(
                              value: (_dragVolume ?? vol).clamp(0.0, 1.0),
                              min: 0.0,
                              max: 1.0,
                              onChanged: (val) {
                                setState(() => _dragVolume = val);
                                widget.playerService.setVolume(val, persist: false);
                              },
                              onChangeEnd: (val) {
                                widget.playerService.setVolume(val, persist: true);
                                setState(() => _dragVolume = null);
                              },
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${((_dragVolume ?? vol) * 100).round()}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildBarThumbnail(Track track, Color accentColor, {double size = 44}) {
  final localFile = track.resolvedLocalThumbnailFile;
  if (localFile != null) {
    return Image.file(
      localFile,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _buildThumbnailPlaceholder(accentColor, size: size),
    );
  }

  final url = (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
      ? track.thumbnailUrl!
      : (track.id.length == 11 && !track.id.contains(' ')
          ? 'https://img.youtube.com/vi/${track.id}/hqdefault.jpg'
          : '');

  if (url.startsWith('file://')) {
    try {
      final f = File(Uri.parse(url).toFilePath());
      if (f.existsSync()) {
        return Image.file(
          f,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildThumbnailPlaceholder(accentColor, size: size),
        );
      }
    } catch (_) {}
  } else if (!url.startsWith('http://') && !url.startsWith('https://') && url.isNotEmpty) {
    try {
      final f = File(url);
      if (f.existsSync()) {
        return Image.file(
          f,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildThumbnailPlaceholder(accentColor, size: size),
        );
      }
    } catch (_) {}
  }

  if (url.startsWith('http://') || url.startsWith('https://')) {
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (_, _) => _buildThumbnailPlaceholder(accentColor, size: size),
      errorWidget: (_, _, _) => _buildThumbnailPlaceholder(accentColor, size: size),
    );
  }

  return _buildThumbnailPlaceholder(accentColor, size: size);
}

Widget _buildThumbnailPlaceholder(Color accentColor, {double size = 44}) {
  return Container(
    width: size,
    height: size,
    color: accentColor.withAlpha(24),
    child: Icon(
      Icons.music_note,
      size: size * 0.45,
      color: accentColor.withAlpha(140),
    ),
  );
}

