import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/player_service.dart';

/// Full-screen "Now Playing" view, similar to YouTube Music.
/// Opened by tapping the NowPlayingBar or the album art in the PlayerTab.
class NowPlayingScreen extends StatefulWidget {
  final PlayerService playerService;
  final Color accentColor;

  const NowPlayingScreen({
    super.key,
    required this.playerService,
    required this.accentColor,
  });

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _artController;
  bool _showQueue = false;

  @override
  void initState() {
    super.initState();
    _artController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _artController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.playerService.currentTrack;
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    // Use a dark gradient background that subtly shifts
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0A0A0A),
                widget.accentColor.withAlpha(15),
                const Color(0xFF0A0A0A),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: track == null
              ? _buildEmpty(theme)
              : _buildContent(track, theme, screenHeight),
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Text(
        'Nothing playing',
        style: theme.textTheme.titleMedium?.copyWith(
          color: const Color(0xFF707070),
        ),
      ),
    );
  }

  Widget _buildContent(Track track, ThemeData theme, double screenHeight) {
    return SafeArea(
      child: Column(
        children: [
          // ---- Top bar ----
          _TopBar(accentColor: widget.accentColor, onClose: () => Navigator.pop(context)),

          // ---- Main content ----
          Expanded(
            child: _showQueue
                ? _QueuePanel(
                    playerService: widget.playerService,
                    accentColor: widget.accentColor,
                  )
                : _PlayerContent(
                    track: track,
                    accentColor: widget.accentColor,
                    playerService: widget.playerService,
                    screenHeight: screenHeight,
                  ),
          ),

          // ---- Bottom transport ----
          _BottomTransport(
            playerService: widget.playerService,
            accentColor: widget.accentColor,
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Top bar with close and queue toggle
// ======================================================================

class _TopBar extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onClose;

  const _TopBar({required this.accentColor, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.keyboard_arrow_down, size: 30),
            tooltip: 'Close',
          ),
          const Spacer(),
          Text(
            'Now Playing',
            style: TextStyle(
              color: accentColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48), // balance
        ],
      ),
    );
  }
}

// ======================================================================
// Player content — album art + title + seek
// ======================================================================

class _PlayerContent extends StatefulWidget {
  final Track track;
  final Color accentColor;
  final PlayerService playerService;
  final double screenHeight;

  const _PlayerContent({
    required this.track,
    required this.accentColor,
    required this.playerService,
    required this.screenHeight,
  });

  @override
  State<_PlayerContent> createState() => _PlayerContentState();
}

class _PlayerContentState extends State<_PlayerContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _vinylController;
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    _vinylController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _playingSub = widget.playerService.playingStream.listen((playing) {
      if (!mounted) return;
      if (playing && !_vinylController.isAnimating) {
        _vinylController.repeat();
      } else if (!playing && _vinylController.isAnimating) {
        _vinylController.stop();
      }
    });
    if (widget.playerService.isPlaying) {
      _vinylController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _PlayerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _vinylController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final theme = Theme.of(context);

    // Dynamic album art size based on screen height
    final artSize = min(widget.screenHeight * 0.38, 340.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          SizedBox(height: widget.screenHeight * 0.04),

          // ---- Album art with subtle rotation animation ----
          RotationTransition(
            turns: _vinylController,
            child: Container(
              width: artSize,
              height: artSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor.withAlpha(40),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                  BoxShadow(
                    color: Colors.black.withAlpha(100),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: track.id.isNotEmpty
                  ? Image.network(
                      'https://img.youtube.com/vi/${track.id}/hqdefault.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _artPlaceholder(artSize),
                    )
                  : _artPlaceholder(artSize),
            ),
          ),

          SizedBox(height: widget.screenHeight * 0.04),

          // ---- Title ----
          Text(
            track.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),

          // ---- Artist ----
          Text(
            track.author,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 24),

          // ---- Seek bar ----
          _FullSeekBar(
            playerService: widget.playerService,
            accentColor: widget.accentColor,
          ),

          const SizedBox(height: 8),

          // ---- Like / dislike / share row ----
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.thumb_up_outlined, size: 20),
                tooltip: 'Like',
              ),
              const SizedBox(width: 24),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.share_outlined, size: 20),
                tooltip: 'Share',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _artPlaceholder(double size) {
    return Container(
      color: widget.accentColor.withAlpha(15),
      child: Icon(
        Icons.music_note,
        size: size * 0.3,
        color: widget.accentColor.withAlpha(80),
      ),
    );
  }
}

// ======================================================================
// Full seek bar (bigger than the compact one)
// ======================================================================

class _FullSeekBar extends StatelessWidget {
  final PlayerService playerService;
  final Color accentColor;

  const _FullSeekBar({required this.playerService, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    activeTrackColor: accentColor,
                    inactiveTrackColor: const Color(0xFF3A3A3A),
                    thumbColor: accentColor,
                    overlayColor: accentColor.withAlpha(50),
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(position),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _fmt(duration),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$min:$sec';
    return '$min:$sec';
  }
}

// ======================================================================
// Bottom transport — the main controls
// ======================================================================

class _BottomTransport extends StatelessWidget {
  final PlayerService playerService;
  final Color accentColor;

  const _BottomTransport({
    required this.playerService,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Shuffle
          StreamBuilder<bool>(
            stream: playerService.shuffleStream,
            initialData: playerService.shuffleEnabled,
            builder: (context, snap) {
              final enabled = snap.data ?? false;
              return IconButton(
                onPressed: () => playerService.toggleShuffle(),
                icon: Icon(
                  Icons.shuffle,
                  size: 22,
                  color: enabled ? accentColor : const Color(0xFF888888),
                ),
              );
            },
          ),

          const SizedBox(width: 16),

          // Previous
          IconButton(
            onPressed: () => playerService.previousTrack(),
            icon: const Icon(Icons.skip_previous_rounded, size: 34),
          ),

          const SizedBox(width: 12),

          // Play / Pause (big)
          StreamBuilder<bool>(
            stream: playerService.playingStream,
            initialData: playerService.isPlaying,
            builder: (context, snap) {
              final isPlaying = snap.data ?? false;
              return GestureDetector(
                onTap: () => playerService.togglePlayPause(),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withAlpha(80),
                        blurRadius: 20,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),

          const SizedBox(width: 12),

          // Next
          IconButton(
            onPressed: () => playerService.nextTrack(),
            icon: const Icon(Icons.skip_next_rounded, size: 34),
          ),

          const SizedBox(width: 16),

          // Loop
          StreamBuilder<LoopMode>(
            stream: playerService.loopModeStream,
            initialData: playerService.loopMode,
            builder: (context, snap) {
              final mode = snap.data ?? LoopMode.off;
              return IconButton(
                onPressed: () => playerService.cycleLoopMode(),
                icon: Icon(
                  _loopIcon(mode),
                  size: 22,
                  color: mode != LoopMode.off ? accentColor : const Color(0xFF888888),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _loopIcon(LoopMode mode) => switch (mode) {
    LoopMode.off => Icons.repeat,
    LoopMode.one => Icons.repeat_one,
    LoopMode.all => Icons.repeat,
  };
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
    final theme = Theme.of(context);
    final queue = playerService.queue;
    final current = playerService.currentTrack;

    if (queue.isEmpty) {
      return Center(
        child: Text(
          'Queue is empty',
          style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF707070)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Text(
            'Queue (${queue.length})',
            style: theme.textTheme.labelLarge?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w600,
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
                  color: isCurrent ? accentColor.withAlpha(20) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      'https://img.youtube.com/vi/${track.id}/hqdefault.jpg',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 44,
                        height: 44,
                        color: accentColor.withAlpha(15),
                        child: Icon(Icons.music_note, size: 18, color: accentColor.withAlpha(100)),
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
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isCurrent
                      ? Icon(Icons.equalizer, color: accentColor, size: 20)
                      : null,
                  onTap: () {
                    // Play this track from the queue
                    final index = queue.indexOf(track);
                    playerService.playList(queue, startIndex: index);
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
