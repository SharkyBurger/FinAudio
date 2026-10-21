import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/playlist_service.dart';
import 'package:finaudio/widgets/now_playing_bar.dart';

/// Spotify-style expandable Right-Hand Panel showing "Now Playing View"
/// (artwork, track info, audio format badge, and upcoming queue preview).
class DesktopRightPanel extends StatelessWidget {
  final Track? track;
  final PlayerService playerService;
  final PlaylistService? playlistService;
  final Color accentColor;
  final VoidCallback onClose;
  final VoidCallback? onOpenQueue;

  const DesktopRightPanel({
    super.key,
    required this.track,
    required this.playerService,
    this.playlistService,
    required this.accentColor,
    required this.onClose,
    this.onOpenQueue,
  });

  Widget _buildBigArtwork(BuildContext context, Track? t) {
    if (t == null) {
      return _buildPlaceholder();
    }

    final localFile = t.resolvedLocalThumbnailFile;
    if (localFile != null && localFile.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          localFile,
          height: 240,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildPlaceholder(),
        ),
      );
    }

    final url = (t.thumbnailUrl != null && t.thumbnailUrl!.isNotEmpty)
        ? t.thumbnailUrl!
        : (t.id.length == 11 && !t.id.contains(' ')
            ? 'https://img.youtube.com/vi/${t.id}/hqdefault.jpg'
            : '');

    if (url.startsWith('file://')) {
      try {
        final f = File(Uri.parse(url).toFilePath());
        if (f.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              f,
              height: 240,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _buildPlaceholder(),
            ),
          );
        }
      } catch (_) {}
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          height: 240,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (_, _) => _buildPlaceholder(),
          errorWidget: (_, _, _) => _buildPlaceholder(),
        ),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: const Color(0xFF282828),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 64,
          color: Colors.white.withAlpha(80),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = track ?? playerService.currentTrack;
    final isLiked = current != null &&
        (playlistService?.isTrackLiked(current.id, current.title, current.author) ?? false);

    // Look for next track in queue
    final queue = playerService.queue;
    Track? nextTrack;
    if (queue.isNotEmpty && current != null) {
      final currentIdx = queue.indexWhere((it) => it.id == current.id);
      if (currentIdx >= 0 && currentIdx + 1 < queue.length) {
        nextTrack = queue[currentIdx + 1];
      } else if (currentIdx == -1 && queue.isNotEmpty) {
        nextTrack = queue.first;
      }
    }

    return Container(
      color: const Color(0xFF121212),
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
            child: Row(
              children: [
                Text(
                  'Now Playing',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close view',
                  icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFFB3B3B3)),
                  splashRadius: 18,
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF242424)),

          // Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Big Cover Art
                _buildBigArtwork(context, current),
                const SizedBox(height: 16),

                // Title, Artist, & Like Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            current?.title ?? 'No Track Playing',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            current?.author ?? 'Choose a song to begin',
                            style: const TextStyle(
                              color: Color(0xFFB3B3B3),
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (current != null)
                      IconButton(
                        tooltip: isLiked ? 'Unlike' : 'Like',
                        icon: Icon(
                          isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isLiked ? accentColor : const Color(0xFFB3B3B3),
                          size: 22,
                        ),
                        splashRadius: 20,
                        onPressed: () async {
                          await playlistService?.toggleLikeTrack(current.toLocalPlaylistTrack());
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                // Audio Info & Streaming Badge Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withAlpha(15)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          color: accentColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Audio Stream',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              current != null ? 'High Quality • InnerTube' : 'Idle',
                              style: const TextStyle(
                                color: Color(0xFFB3B3B3),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StreamBuilder<bool>(
                        stream: playerService.playingStream,
                        initialData: playerService.isPlaying,
                        builder: (context, snap) {
                          final isPlaying = snap.data ?? false;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isPlaying ? accentColor.withAlpha(40) : Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isPlaying ? 'PLAYING' : 'PAUSED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isPlaying ? accentColor : Colors.white70,
                                letterSpacing: 0.5,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Next In Queue Card
                if (nextTrack != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F1F1F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withAlpha(15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Next in queue',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (onOpenQueue != null)
                              InkWell(
                                onTap: onOpenQueue,
                                child: Text(
                                  'Open queue',
                                  style: TextStyle(
                                    color: accentColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SizedBox(
                                width: 42,
                                height: 42,
                                child: buildTrackThumbnail(nextTrack, accentColor, size: 42),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nextTrack.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    nextTrack.author,
                                    style: const TextStyle(
                                      color: Color(0xFFB3B3B3),
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
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
}

