import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:finaudio/models/local_playlist.dart';
import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/playlist_service.dart';
import 'package:finaudio/services/settings_service.dart';
import 'package:finaudio/services/google_auth_service.dart';
import 'package:finaudio/services/youtube_service.dart';
import 'package:finaudio/services/download_service.dart';
import 'package:finaudio/widgets/add_to_playlist_sheet.dart';

enum _DesktopPlaylistSort {
  original,
  titleAsc,
  titleDesc,
  artistAsc,
  artistDesc,
  durationAsc,
  durationDesc,
}

class DesktopPlaylistView extends StatefulWidget {
  final LocalPlaylist playlist;
  final PlayerService playerService;
  final PlaylistService playlistService;
  final SettingsService? settingsService;
  final GoogleAuthService? authService;
  final Color accentColor;
  final VoidCallback? onBack;

  const DesktopPlaylistView({
    super.key,
    required this.playlist,
    required this.playerService,
    required this.playlistService,
    this.settingsService,
    this.authService,
    required this.accentColor,
    this.onBack,
  });

  @override
  State<DesktopPlaylistView> createState() => _DesktopPlaylistViewState();
}

class _DesktopPlaylistViewState extends State<DesktopPlaylistView> {
  late LocalPlaylist _playlist;
  String _searchQuery = '';
  _DesktopPlaylistSort _sortOption = _DesktopPlaylistSort.original;
  int? _hoveredIndex;
  bool _fetchingArtworks = false;
  String _fetchingArtworksProgress = '';
  StreamSubscription<Track?>? _nowPlayingSub;

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    _nowPlayingSub = widget.playerService.nowPlayingStream.listen((track) {
      if (track != null && mounted) {
        _onTrackNowPlaying(track);
      }
    });
  }

  @override
  void didUpdateWidget(covariant DesktopPlaylistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.id != widget.playlist.id) {
      _playlist = widget.playlist;
      _searchQuery = '';
    }
  }

  @override
  void dispose() {
    _nowPlayingSub?.cancel();
    super.dispose();
  }

  void _onTrackNowPlaying(Track track) {
    if (track.thumbnailUrl == null || track.thumbnailUrl!.isEmpty) return;
    final trackIndex = _playlist.tracks.indexWhere(
      (t) =>
          t.title.trim().toLowerCase() == track.title.trim().toLowerCase() &&
          (t.artist.trim().toLowerCase() == track.author.trim().toLowerCase() ||
           t.formattedArtist.trim().toLowerCase() == track.formattedArtist.trim().toLowerCase()),
    );
    if (trackIndex >= 0) {
      final current = _playlist.tracks[trackIndex];
      if (current.thumbnailUrl != track.thumbnailUrl ||
          current.youtubeVideoId != track.id) {
        final updatedTracks = List<LocalPlaylistTrack>.from(_playlist.tracks);
        updatedTracks[trackIndex] = current.copyWith(
          thumbnailUrl: track.thumbnailUrl,
          youtubeVideoId: track.id,
        );
        final updated = _playlist.copyWith(tracks: updatedTracks);
        if (mounted) setState(() => _playlist = updated);
      }
    }
  }

  List<LocalPlaylistTrack> _getFilteredAndSortedTracks() {
    var list = List<LocalPlaylistTrack>.from(_playlist.tracks);
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((t) {
        return t.title.toLowerCase().contains(q) ||
               t.artist.toLowerCase().contains(q);
      }).toList();
    }

    switch (_sortOption) {
      case _DesktopPlaylistSort.titleAsc:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case _DesktopPlaylistSort.titleDesc:
        list.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case _DesktopPlaylistSort.artistAsc:
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case _DesktopPlaylistSort.artistDesc:
        list.sort((a, b) => b.artist.toLowerCase().compareTo(a.artist.toLowerCase()));
        break;
      case _DesktopPlaylistSort.durationAsc:
        list.sort((a, b) => a.duration.compareTo(b.duration));
        break;
      case _DesktopPlaylistSort.durationDesc:
        list.sort((a, b) => b.duration.compareTo(a.duration));
        break;
      case _DesktopPlaylistSort.original:
        break;
    }
    return list;
  }

  Duration get _totalDuration {
    int totalMs = 0;
    for (final t in _playlist.tracks) {
      totalMs += t.duration.inMilliseconds;
    }
    return Duration(milliseconds: totalMs);
  }

  String _formatTotalDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours} hr ${d.inMinutes.remainder(60)} min';
    }
    return '${d.inMinutes} min';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _playAll({bool shuffle = false}) {
    final tracks = _getFilteredAndSortedTracks();
    if (tracks.isEmpty) return;
    final list = List<LocalPlaylistTrack>.from(tracks);
    if (shuffle) list.shuffle();

    widget.playerService.playLocalTracks(list).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback error: $e')),
        );
      }
    });
  }

  void _playTrackAt(int index) {
    final tracks = _getFilteredAndSortedTracks();
    if (index < 0 || index >= tracks.length) return;
    widget.playerService.playLocalTracks(tracks, startIndex: index).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback error: $e')),
        );
      }
    });
  }

  Future<void> _fetchTrackArtworks() async {
    if (_fetchingArtworks) return;

    final missingIndices = <int>[];
    for (int i = 0; i < _playlist.tracks.length; i++) {
      final t = _playlist.tracks[i];
      if (t.thumbnailUrl == null || t.thumbnailUrl!.trim().isEmpty) {
        missingIndices.add(i);
      }
    }

    if (missingIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All tracks already have artwork.')),
      );
      return;
    }

    setState(() {
      _fetchingArtworks = true;
      _fetchingArtworksProgress = '0 / ${missingIndices.length}';
    });

    int fetchedCount = 0;
    final totalMissing = missingIndices.length;

    try {
      final updatedTracks = List<LocalPlaylistTrack>.from(_playlist.tracks);
      final yt = YoutubeService();

      final remainingIndices = <int>[];
      for (final idx in missingIndices) {
        final t = updatedTracks[idx];
        if (DownloadService.isValidYouTubeVideoId(t.youtubeVideoId, title: t.title)) {
          final vid = t.youtubeVideoId!;
          updatedTracks[idx] = t.copyWith(
            thumbnailUrl: 'https://img.youtube.com/vi/$vid/hqdefault.jpg',
          );
          fetchedCount++;
          continue;
        }

        final cleanTitle = t.title.trim().toLowerCase();
        final cleanArtist = t.artist.trim().toLowerCase();
        String? cachedThumb;
        String? cachedVid;

        for (final pl in widget.playlistService.playlists) {
          for (final other in pl.tracks) {
            if (other.thumbnailUrl != null &&
                other.thumbnailUrl!.isNotEmpty &&
                other.title.trim().toLowerCase() == cleanTitle &&
                (other.artist.trim().toLowerCase() == cleanArtist || cleanArtist.isEmpty)) {
              cachedThumb = other.thumbnailUrl;
              cachedVid = other.youtubeVideoId;
              break;
            }
          }
          if (cachedThumb != null) break;
        }

        if (cachedThumb != null && cachedThumb.isNotEmpty) {
          updatedTracks[idx] = t.copyWith(
            thumbnailUrl: cachedThumb,
            youtubeVideoId: cachedVid ?? t.youtubeVideoId,
          );
          fetchedCount++;
          continue;
        }

        remainingIndices.add(idx);
      }

      if (fetchedCount > 0) {
        final updated = _playlist.copyWith(tracks: updatedTracks);
        await widget.playlistService.savePlaylist(updated);
        if (mounted) {
          setState(() {
            _playlist = updated;
            _fetchingArtworksProgress = '$fetchedCount / $totalMissing';
          });
        }
      }

      const batchSize = 4;
      for (int i = 0; i < remainingIndices.length; i += batchSize) {
        if (!mounted) break;
        final batch = remainingIndices.sublist(
          i,
          i + batchSize > remainingIndices.length ? remainingIndices.length : i + batchSize,
        );

        await Future.wait(batch.map((trackIdx) async {
          final t = updatedTracks[trackIdx];
          String? foundThumb;
          String? foundId;

          final queries = DownloadService.buildSearchQueries(Track.fromLocalPlaylistTrack(t));
          for (final q in queries) {
            try {
              final results = await yt.search(q);
              if (results.isNotEmpty) {
                final vid = results.first.id.value;
                foundId = vid;
                foundThumb = 'https://img.youtube.com/vi/$vid/hqdefault.jpg';
                break;
              }
            } catch (_) {}
          }

          if (foundId == null) {
            for (final q in queries.take(2)) {
              try {
                final musicResults = await yt.searchYTMusic(q);
                for (final item in musicResults) {
                  if (item is Map && item['videoId'] != null) {
                    final vid = item['videoId'].toString();
                    if (vid.isNotEmpty) {
                      foundId = vid;
                      if (item['thumbnails'] != null && (item['thumbnails'] as List).isNotEmpty) {
                        foundThumb = item['thumbnails'].last['url']?.toString();
                      }
                      foundThumb ??= 'https://img.youtube.com/vi/$vid/hqdefault.jpg';
                      break;
                    }
                  }
                }
                if (foundId != null) break;
              } catch (_) {}
            }
          }

          if (foundId != null) {
            foundThumb ??= 'https://img.youtube.com/vi/$foundId/hqdefault.jpg';
            updatedTracks[trackIdx] = t.copyWith(
              thumbnailUrl: foundThumb,
              youtubeVideoId: foundId,
            );
            fetchedCount++;
            unawaited(widget.playlistService.updateTrackResolvedVideoId(
              title: t.title,
              artist: t.artist,
              youtubeVideoId: foundId,
              thumbnailUrl: foundThumb,
            ));
          }
        }));

        final updated = _playlist.copyWith(tracks: updatedTracks);
        await widget.playlistService.savePlaylist(updated);
        if (mounted) {
          setState(() {
            _playlist = updated;
            _fetchingArtworksProgress = '$fetchedCount / $totalMissing';
          });
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (mounted) {
        final onAccent = widget.accentColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Artwork update complete: fetched $fetchedCount tracks.',
              style: TextStyle(color: onAccent, fontWeight: FontWeight.bold),
            ),
            backgroundColor: widget.accentColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _fetchingArtworks = false;
          _fetchingArtworksProgress = '';
        });
      }
    }
  }

  Widget _buildPlaylistCover(double size, Color surface, Color bg, Color text, Color accent, Color onAccent) {
    final isLikedSongs = _playlist.id == PlaylistService.likedSongsId;

    if (isLikedSongs) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            colors: [
              accent.withAlpha(220),
              Color.lerp(accent, surface, 0.55) ?? accent,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: bg.withAlpha(120),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            Icons.favorite_rounded,
            size: size * 0.4,
            color: onAccent,
          ),
        ),
      );
    }

    if (_playlist.thumbnailUrl.isNotEmpty) {
      final url = _playlist.thumbnailUrl;
      if (url.startsWith('file://')) {
        try {
          final f = File(Uri.parse(url).toFilePath());
          if (f.existsSync()) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                f,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            );
          }
        } catch (_) {}
      } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
        try {
          final f = File(url);
          if (f.existsSync()) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                f,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            );
          }
        } catch (_) {}
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, _) => _buildPlaceholderCover(size, surface, bg, text),
          errorWidget: (_, _, _) => _buildPlaceholderCover(size, surface, bg, text),
        ),
      );
    }

    return _buildPlaceholderCover(size, surface, bg, text);
  }

  Widget _buildPlaceholderCover(double size, Color surface, Color bg, Color text) {
    final cardBg = Color.lerp(surface, bg, 0.4) ?? surface;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: bg.withAlpha(100),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * 0.4,
          color: text.withAlpha(70),
        ),
      ),
    );
  }

  Widget _buildTrackCover(LocalPlaylistTrack track, double size, Color placeholderBg, Color iconColor) {
    final thumb = track.thumbnailUrl;
    if (thumb != null && thumb.isNotEmpty) {
      if (thumb.startsWith('http://') || thumb.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CachedNetworkImage(
            imageUrl: thumb,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Container(
              width: size,
              height: size,
              color: placeholderBg,
              child: Icon(Icons.music_note_rounded, size: size * 0.5, color: iconColor),
            ),
          ),
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: placeholderBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.music_note_rounded, size: size * 0.5, color: iconColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = widget.settingsService?.backgroundColor ?? theme.scaffoldBackgroundColor;
    final surface = widget.settingsService?.surfaceColor ?? theme.colorScheme.surface;
    final accent = widget.accentColor;
    final text = widget.settingsService?.textColor ?? theme.colorScheme.onSurface;
    final textMuted = text.withAlpha(170);
    final textDim = text.withAlpha(110);
    final border = text.withAlpha(22);
    final inputBg = Color.lerp(surface, bg, 0.45) ?? surface;
    final onAccent = accent.computeLuminance() > 0.5 ? const Color(0xFF101010) : const Color(0xFFFFFFFF);

    final currentTrack = widget.playerService.currentTrack;
    final isPlaying = widget.playerService.isPlaying;
    final tracks = _getFilteredAndSortedTracks();

    return Container(
      color: surface,
      child: CustomScrollView(
        slivers: [
          // Spotify Hero Header
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withAlpha(55),
                    surface,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildPlaylistCover(180, surface, bg, text, accent, onAccent),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'PUBLIC PLAYLIST',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: textDim,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _playlist.title,
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: text,
                            letterSpacing: -1.2,
                            height: 1.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _playlist.description.isNotEmpty ? _playlist.description : 'FinAudio',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: text,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(' • ', style: TextStyle(color: textMuted)),
                            Text(
                              '${_playlist.tracks.length} songs',
                              style: TextStyle(color: textMuted, fontSize: 13),
                            ),
                            if (_playlist.tracks.isNotEmpty) ...[
                              Text(' • ', style: TextStyle(color: textMuted)),
                              Text(
                                _formatTotalDuration(_totalDuration),
                                style: TextStyle(color: textDim, fontSize: 13),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Spotify Action Bar (Play button, Shuffle, Fetch artworks, Search)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Row(
                children: [
                  // Big Circular Play Button
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _playAll(),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accent.withAlpha(80),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 30,
                            color: onAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Shuffle Button
                  IconButton(
                    tooltip: 'Shuffle Play',
                    icon: Icon(Icons.shuffle_rounded, size: 24, color: textMuted),
                    onPressed: () => _playAll(shuffle: true),
                  ),

                  // Fetch Artworks Button
                  IconButton(
                    tooltip: _fetchingArtworks
                        ? 'Fetching Artworks ($_fetchingArtworksProgress)'
                        : 'Fetch Track Artworks',
                    icon: _fetchingArtworks
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          )
                        : Icon(Icons.image_search_rounded, size: 22, color: textMuted),
                    onPressed: _fetchingArtworks ? null : _fetchTrackArtworks,
                  ),

                  const Spacer(),

                  // Search inside playlist
                  Container(
                    width: 220,
                    height: 34,
                    decoration: BoxDecoration(
                      color: inputBg,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 16, color: textDim),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (val) => setState(() => _searchQuery = val),
                            style: TextStyle(fontSize: 12, color: text),
                            decoration: InputDecoration(
                              hintText: 'Search in playlist',
                              hintStyle: TextStyle(fontSize: 12, color: textDim),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _searchQuery = ''),
                            child: Icon(Icons.close_rounded, size: 14, color: textDim),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Sort Menu
                  PopupMenuButton<_DesktopPlaylistSort>(
                    icon: Icon(Icons.sort_rounded, color: textMuted, size: 20),
                    tooltip: 'Sort By',
                    color: surface,
                    onSelected: (val) => setState(() => _sortOption = val),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _DesktopPlaylistSort.original,
                        child: Text('Custom order', style: TextStyle(color: text)),
                      ),
                      PopupMenuItem(
                        value: _DesktopPlaylistSort.titleAsc,
                        child: Text('Title (A-Z)', style: TextStyle(color: text)),
                      ),
                      PopupMenuItem(
                        value: _DesktopPlaylistSort.artistAsc,
                        child: Text('Artist', style: TextStyle(color: text)),
                      ),
                      PopupMenuItem(
                        value: _DesktopPlaylistSort.durationAsc,
                        child: Text('Duration', style: TextStyle(color: text)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Table Header
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              margin: const EdgeInsets.only(bottom: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          '#',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textDim,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 6,
                        child: Text(
                          'Title',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textDim,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          'Artist',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textDim,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Icon(Icons.access_time_rounded, size: 16, color: textDim),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: border),
                ],
              ),
            ),
          ),

          // Table Rows
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No tracks found in playlist',
                  style: TextStyle(color: textDim),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final t = tracks[index];
                  final isHovered = _hoveredIndex == index;
                  final isCurrentlyPlaying = currentTrack != null &&
                      (currentTrack.id == t.youtubeVideoId ||
                       (currentTrack.title.trim().toLowerCase() == t.title.trim().toLowerCase() &&
                        currentTrack.author.trim().toLowerCase() == t.artist.trim().toLowerCase()));

                  final isLiked = widget.playlistService.isTrackLiked(
                    t.youtubeVideoId,
                    t.title,
                    t.artist,
                  );

                  return MouseRegion(
                    onEnter: (_) => setState(() => _hoveredIndex = index),
                    onExit: (_) => setState(() => _hoveredIndex = null),
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _playTrackAt(index),
                      onDoubleTap: () => _playTrackAt(index),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: isHovered
                              ? accent.withAlpha(22)
                              : (isCurrentlyPlaying ? accent.withAlpha(14) : Colors.transparent),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            // # / Play button / Playing indicator
                            SizedBox(
                              width: 40,
                              child: isHovered
                                  ? IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        Icons.play_arrow_rounded,
                                        size: 20,
                                        color: accent,
                                      ),
                                      onPressed: () => _playTrackAt(index),
                                    )
                                  : isCurrentlyPlaying
                                      ? Icon(
                                          Icons.volume_up_rounded,
                                          size: 16,
                                          color: accent,
                                        )
                                      : Text(
                                          '${index + 1}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: textDim,
                                          ),
                                        ),
                            ),
                            const SizedBox(width: 12),

                            // Artwork + Title + Artist
                            Expanded(
                              flex: 6,
                              child: Row(
                                children: [
                                  _buildTrackCover(t, 40, inputBg, textDim),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isCurrentlyPlaying ? accent : text,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          t.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Artist column
                            Expanded(
                              flex: 4,
                              child: Text(
                                t.artist.isNotEmpty ? t.artist : '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textMuted,
                                ),
                              ),
                            ),

                            // Heart button (hover only or if liked)
                            if (isHovered || isLiked)
                              IconButton(
                                icon: Icon(
                                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  size: 16,
                                  color: isLiked ? accent : textDim,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: () async {
                                  await widget.playlistService.toggleLikeTrack(t);
                                  setState(() {});
                                },
                              )
                            else
                              const SizedBox(width: 28),

                            // Duration
                            SizedBox(
                              width: 50,
                              child: Text(
                                _formatDuration(t.duration),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textDim,
                                ),
                              ),
                            ),

                            // Action Menu button
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_horiz_rounded, size: 16, color: textDim),
                              padding: EdgeInsets.zero,
                              color: surface,
                              onSelected: (val) async {
                                final trackObj = Track.fromLocalPlaylistTrack(t);
                                if (val == 'play_next') {
                                  widget.playerService.playNext(trackObj);
                                } else if (val == 'add_queue') {
                                  widget.playerService.addToQueue(trackObj);
                                } else if (val == 'add_playlist') {
                                  showAddToPlaylistSheet(
                                    context: context,
                                    track: t,
                                    playlistService: widget.playlistService,
                                    accentColor: accent,
                                  );
                                } else if (val == 'remove') {
                                  final updatedTracks = List<LocalPlaylistTrack>.from(_playlist.tracks)
                                    ..remove(t);
                                  final updated = _playlist.copyWith(tracks: updatedTracks);
                                  await widget.playlistService.savePlaylist(updated);
                                  setState(() => _playlist = updated);
                                }
                              },
                              itemBuilder: (ctx) => [
                                PopupMenuItem(value: 'play_next', child: Text('Play next', style: TextStyle(color: text))),
                                PopupMenuItem(value: 'add_queue', child: Text('Add to queue', style: TextStyle(color: text))),
                                PopupMenuItem(value: 'add_playlist', child: Text('Add to playlist', style: TextStyle(color: text))),
                                if (_playlist.id != PlaylistService.likedSongsId)
                                  const PopupMenuItem(value: 'remove', child: Text('Remove from playlist', style: TextStyle(color: Colors.redAccent))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: tracks.length,
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 40),
          ),
        ],
      ),
    );
  }
}
