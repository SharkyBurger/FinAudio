import 'package:flutter/material.dart';
import '../models/local_playlist.dart';
import '../services/playlist_service.dart';

/// Displays a modal bottom sheet allowing the user to like a track
/// or select one or more playlists to add/remove the track from.
Future<void> showAddToPlaylistSheet({
  required BuildContext context,
  required LocalPlaylistTrack track,
  required PlaylistService playlistService,
  required Color accentColor,
  Color? surfaceColor,
  Color? textColor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddToPlaylistModal(
      track: track,
      playlistService: playlistService,
      accentColor: accentColor,
      surfaceColor: surfaceColor,
      textColor: textColor,
    ),
  );
}

class _AddToPlaylistModal extends StatefulWidget {
  final LocalPlaylistTrack track;
  final PlaylistService playlistService;
  final Color accentColor;
  final Color? surfaceColor;
  final Color? textColor;

  const _AddToPlaylistModal({
    required this.track,
    required this.playlistService,
    required this.accentColor,
    this.surfaceColor,
    this.textColor,
  });

  @override
  State<_AddToPlaylistModal> createState() => _AddToPlaylistModalState();
}

class _AddToPlaylistModalState extends State<_AddToPlaylistModal> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = widget.surfaceColor ?? theme.colorScheme.surface;
    final text = widget.textColor ?? theme.colorScheme.onSurface;
    final playlists = widget.playlistService.playlists;
    final isLiked = widget.playlistService.isTrackLiked(
      widget.track.youtubeVideoId,
      widget.track.title,
      widget.track.artist,
    );
    final otherPlaylists = playlists.where((p) => !p.isLikedSongs).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: text.withAlpha(25)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: text.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Track Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: (widget.track.thumbnailUrl != null &&
                            widget.track.thumbnailUrl!.isNotEmpty)
                        ? Image.network(
                            widget.track.thumbnailUrl!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 52,
                              height: 52,
                              color: text.withAlpha(20),
                              child: Icon(Icons.music_note, color: widget.accentColor),
                            ),
                          )
                        : Container(
                            width: 52,
                            height: 52,
                            color: text.withAlpha(20),
                            child: Icon(Icons.music_note, color: widget.accentColor),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.track.artist,
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
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Content List
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // 1. Liked Songs Tile (Spotify-Style)
                  ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                    title: const Text(
                      'Liked Songs',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${widget.playlistService.likedSongsPlaylist.trackCount} tracks • Permanent',
                      style: TextStyle(fontSize: 11, color: text.withAlpha(130)),
                    ),
                    trailing: Icon(
                      isLiked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: isLiked ? const Color(0xFF1DB954) : text.withAlpha(80),
                      size: 24,
                    ),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final errorColor = Theme.of(context).colorScheme.error;
                      final likedNow = await widget.playlistService.toggleLikeTrack(widget.track);
                      if (!mounted) return;
                      setState(() {});
                      messenger.showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          content: Text(
                            likedNow
                                ? 'Added to Liked Songs'
                                : 'Removed from Liked Songs',
                          ),
                          backgroundColor: likedNow
                              ? const Color(0xFF1DB954)
                              : errorColor,
                        ),
                      );
                    },
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'YOUR PLAYLISTS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: text.withAlpha(140),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _showNewPlaylistDialog,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('New Playlist', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),

                  if (otherPlaylists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
                      child: Column(
                        children: [
                          Icon(Icons.queue_music_rounded, size: 36, color: text.withAlpha(60)),
                          const SizedBox(height: 8),
                          Text(
                            'No custom playlists yet',
                            style: TextStyle(fontSize: 13, color: text.withAlpha(140)),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: _showNewPlaylistDialog,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Create a Playlist'),
                          ),
                        ],
                      ),
                    )
                  else
                    ...otherPlaylists.map((playlist) {
                      final inPlaylist = widget.playlistService.isTrackInPlaylist(
                        playlist.id,
                        widget.track.youtubeVideoId,
                        widget.track.title,
                        widget.track.artist,
                      );

                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: (playlist.effectiveThumbnailUrl.isNotEmpty)
                              ? Image.network(
                                  playlist.effectiveThumbnailUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 44,
                                    height: 44,
                                    color: text.withAlpha(20),
                                    child: Icon(Icons.queue_music, color: widget.accentColor),
                                  ),
                                )
                              : Container(
                                  width: 44,
                                  height: 44,
                                  color: text.withAlpha(20),
                                  child: Icon(Icons.queue_music, color: widget.accentColor),
                                ),
                        ),
                        title: Text(
                          playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          '${playlist.trackCount} songs',
                          style: TextStyle(fontSize: 11, color: text.withAlpha(130)),
                        ),
                        trailing: Icon(
                          inPlaylist ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: inPlaylist ? const Color(0xFF1DB954) : text.withAlpha(80),
                          size: 24,
                        ),
                        onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          if (inPlaylist) {
                            await widget.playlistService.removeTrackFromPlaylist(
                              playlist.id,
                              widget.track,
                            );
                            if (!mounted) return;
                            setState(() {});
                            messenger.showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 2),
                                content: Text('Removed from "${playlist.title}"'),
                              ),
                            );
                          } else {
                            await widget.playlistService.addTrackToPlaylist(
                              playlist.id,
                              widget.track,
                            );
                            if (!mounted) return;
                            setState(() {});
                            messenger.showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 2),
                                content: Text('Added to "${playlist.title}"'),
                                backgroundColor: const Color(0xFF1DB954),
                              ),
                            );
                          }
                        },
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNewPlaylistDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            prefixIcon: Icon(Icons.playlist_add),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create & Add'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final newPlaylist = await widget.playlistService.createPlaylist(
        title: name,
        thumbnailUrl: widget.track.thumbnailUrl ?? '',
      );
      await widget.playlistService.addTrackToPlaylist(newPlaylist.id, widget.track);
      if (mounted) {
        setState(() {});
        messenger.showSnackBar(
          SnackBar(
            content: Text('Created "$name" and added track!'),
            backgroundColor: const Color(0xFF1DB954),
          ),
        );
      }
    }
  }
}
