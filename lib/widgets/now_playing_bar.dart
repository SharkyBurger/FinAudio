import 'package:flutter/material.dart';

import '../services/player_service.dart';
import '../ui/now_playing_screen.dart';

/// A compact, persistent now-playing bar shown at the bottom of the app when
/// a track is loaded. Shows thumbnail, title, artist, progress, play/pause, next.
class NowPlayingBar extends StatelessWidget {
  final Track track;
  final Color accentColor;
  final PlayerService playerService;

  const NowPlayingBar({
    super.key,
    required this.track,
    required this.accentColor,
    required this.playerService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
                    pageBuilder: (_, __, ___) => NowPlayingScreen(
                      playerService: playerService,
                      accentColor: accentColor,
                    ),
                    transitionsBuilder: (_, anim, __, child) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
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
                      child: Image.network(
                        'https://img.youtube.com/vi/${track.id}/hqdefault.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 44,
                          height: 44,
                          color: accentColor.withAlpha(24),
                          child: Icon(Icons.music_note, size: 20, color: accentColor.withAlpha(140)),
                        ),
                      ),
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
                            color: const Color(0xFFE6E6E6),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          track.author,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                      child: Icon(
                        playerService.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Next
                  IconButton(
                    onPressed: () => playerService.nextTrack(),
                    icon: const Icon(Icons.skip_next_rounded, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
              final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
              final posMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs);
              final fraction = posMs / maxMs;

              return ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                child: LinearProgressIndicator(
                  value: fraction,
                  backgroundColor: const Color(0xFF2A2A2A),
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
