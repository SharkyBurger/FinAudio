import 'package:flutter/material.dart';
import 'package:finaudio/services/download_service.dart';
import 'package:finaudio/services/history_service.dart';
import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/playlist_service.dart';
import 'package:finaudio/services/settings_service.dart';
import 'package:finaudio/widgets/add_to_playlist_sheet.dart';

/// Cached / Instant Playback screen matching ArchiveTune's Cached page styling.
/// Shows cover art hero header, Shuffle & Play buttons, sort filter, and cached track list.
class CachedScreen extends StatefulWidget {
  final PlayerService playerService;
  final PlaylistService playlistService;
  final SettingsService settingsService;

  const CachedScreen({
    super.key,
    required this.playerService,
    required this.playlistService,
    required this.settingsService,
  });

  @override
  State<CachedScreen> createState() => _CachedScreenState();
}

class _CachedScreenState extends State<CachedScreen> {
  final HistoryService _historyService = HistoryService.instance;
  final DownloadService _downloadService = DownloadService.instance;

  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  String _sortBy = 'date_added'; // 'date_added', 'title', 'artist'
  bool _sortAscending = false; // default descending (newest first)

  @override
  void initState() {
    super.initState();
    _historyService.addListener(_onUpdate);
    _downloadService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _historyService.removeListener(_onUpdate);
    _downloadService.removeListener(_onUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  List<HistoryItem> _getSortedAndFilteredItems() {
    var items = List<HistoryItem>.from(_historyService.items);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = items.where((item) {
        return item.title.toLowerCase().contains(q) ||
            item.artist.toLowerCase().contains(q);
      }).toList();
    }

    if (_sortBy == 'title') {
      items.sort((a, b) => _sortAscending
          ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
          : b.title.toLowerCase().compareTo(a.title.toLowerCase()));
    } else if (_sortBy == 'artist') {
      items.sort((a, b) => _sortAscending
          ? a.artist.toLowerCase().compareTo(b.artist.toLowerCase())
          : b.artist.toLowerCase().compareTo(a.artist.toLowerCase()));
    } else {
      // date_added
      items.sort((a, b) => _sortAscending
          ? a.lastPlayed.compareTo(b.lastPlayed)
          : b.lastPlayed.compareTo(a.lastPlayed));
    }

    return items;
  }

  void _playAll({bool shuffle = false}) {
    final items = _getSortedAndFilteredItems();
    if (items.isEmpty) return;

    final tracks = items.map((i) => i.toLocalPlaylistTrack()).toList();
    if (shuffle) {
      tracks.shuffle();
    }
    widget.playerService.playLocalTracks(tracks);
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.settingsService.backgroundColor;
    final surface = widget.settingsService.surfaceColor;
    final text = widget.settingsService.textColor;
    final accent = widget.settingsService.accentColor;

    final items = _getSortedAndFilteredItems();
    final topItem = items.isNotEmpty ? items.first : null;

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          // Hero Artwork Header matching ArchiveTune Screenshot 3
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Background Cover Art with dark gradient overlay
                if (topItem != null && topItem.thumbnailUrl.isNotEmpty)
                  Positioned.fill(
                    child: ShaderMask(
                      shaderCallback: (rect) {
                        return LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withAlpha(160),
                            bg.withAlpha(220),
                            bg,
                          ],
                          stops: const [0.0, 0.65, 1.0],
                        ).createShader(rect);
                      },
                      blendMode: BlendMode.darken,
                      child: Image.network(
                        topItem.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(),
                      ),
                    ),
                  )
                else
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accent.withAlpha(40),
                            bg,
                          ],
                        ),
                      ),
                    ),
                  ),

                // Top AppBar and Header Content
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Top Nav Icons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded, size: 26),
                              color: text,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.search_rounded, size: 24),
                                  color: text,
                                  onPressed: () {
                                    setState(() => _isSearching = !_isSearching);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.more_vert_rounded, size: 24),
                                  color: text,
                                  onPressed: _showMoreMenu,
                                ),
                              ],
                            ),
                          ],
                        ),

                        if (_isSearching)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              style: TextStyle(color: text, fontSize: 16),
                              decoration: InputDecoration(
                                hintText: 'Search cached songs…',
                                hintStyle: TextStyle(color: text.withAlpha(140)),
                                filled: true,
                                fillColor: surface.withAlpha(200),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                prefixIcon: Icon(Icons.search_rounded, color: text.withAlpha(160)),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  color: text.withAlpha(160),
                                  onPressed: () {
                                    setState(() {
                                      _isSearching = false;
                                      _searchQuery = '';
                                      _searchController.clear();
                                    });
                                  },
                                ),
                              ),
                              onChanged: (val) => setState(() => _searchQuery = val),
                            ),
                          ),

                        const SizedBox(height: 120),

                        // Title: "Cached"
                        Text(
                          'Cached',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: text,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Subtitle: "X songs"
                        Text(
                          '${items.length} songs',
                          style: TextStyle(
                            fontSize: 14,
                            color: text.withAlpha(160),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Action Buttons: Shuffle and Play (ArchiveTune style)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Shuffle Button (Dark circular/rounded pill)
                            Material(
                              color: Colors.white.withAlpha(25),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _playAll(shuffle: true),
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.shuffle_rounded,
                                    color: text,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Play Button (Large White Pill with Play icon and "Play" text)
                            Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _playAll(shuffle: false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.black,
                                        size: 26,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Play',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Filter / Sort Bar: Date added pill + down arrow (Screenshot 3)
                        Row(
                          children: [
                            // "Date added" Pill Chip
                            GestureDetector(
                              onTap: _toggleSortBy,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF665C23), // Olive/Gold tint from Screenshot 3
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: Text(
                                  _sortByLabel,
                                  style: const TextStyle(
                                    color: Color(0xFFFFF9C4),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Sort Order Button (Down/Up arrow in circle)
                            GestureDetector(
                              onTap: () {
                                setState(() => _sortAscending = !_sortAscending);
                              },
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF665C23),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _sortAscending
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  color: const Color(0xFFFFF9C4),
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Cached Song List
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cached_rounded, size: 48, color: text.withAlpha(100)),
                      const SizedBox(height: 16),
                      Text(
                        'No cached tracks',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Songs you stream are automatically kept in cache for buffer-free instant playback.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: text.withAlpha(140)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    return _buildSongItem(item, surface, text, accent);
                  },
                  childCount: items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String get _sortByLabel {
    switch (_sortBy) {
      case 'title':
        return 'Title';
      case 'artist':
        return 'Artist';
      default:
        return 'Date added';
    }
  }

  void _toggleSortBy() {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.settingsService.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              ListTile(
                title: const Text('Date added', style: TextStyle(color: Colors.white)),
                trailing: _sortBy == 'date_added' ? const Icon(Icons.check, color: Colors.amber) : null,
                onTap: () {
                  setState(() => _sortBy = 'date_added');
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                title: const Text('Title', style: TextStyle(color: Colors.white)),
                trailing: _sortBy == 'title' ? const Icon(Icons.check, color: Colors.amber) : null,
                onTap: () {
                  setState(() => _sortBy = 'title');
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                title: const Text('Artist', style: TextStyle(color: Colors.white)),
                trailing: _sortBy == 'artist' ? const Icon(Icons.check, color: Colors.amber) : null,
                onTap: () {
                  setState(() => _sortBy = 'artist');
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSongItem(
    HistoryItem item,
    Color surface,
    Color text,
    Color accent,
  ) {
    final track = item.toLocalPlaylistTrack();
    final isDownloaded = item.videoId != null && _downloadService.isDownloaded(item.videoId!);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        widget.playerService.playLocalTracks([track]);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // Artwork Thumbnail (Screenshot 3)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                color: Colors.black26,
                child: item.thumbnailUrl.isNotEmpty
                    ? Image.network(
                        item.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.music_note,
                          color: Colors.white54,
                        ),
                      )
                    : const Icon(
                        Icons.music_note,
                        color: Colors.white54,
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Title & Artist • Duration
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (isDownloaded) ...[
                        const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF00E676)),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          '${item.artist} • ${_formatDuration(item.duration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: text.withAlpha(150),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Three dots more menu (Screenshot 3)
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              color: text.withAlpha(160),
              onPressed: () => _showTrackBottomSheet(item),
            ),
          ],
        ),
      ),
    );
  }

  void _showTrackBottomSheet(HistoryItem item) {
    final track = item.toLocalPlaylistTrack();
    final playableTrack = Track(
      id: item.videoId ?? '',
      title: item.title,
      author: item.artist,
      youtubeUrl: item.videoId != null ? 'https://www.youtube.com/watch?v=${item.videoId}' : '',
      duration: item.duration,
      thumbnailUrl: item.thumbnailUrl,
    );

    final isDownloaded = item.videoId != null && _downloadService.isDownloaded(item.videoId!);

    showModalBottomSheet(
      context: context,
      backgroundColor: widget.settingsService.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded, color: Colors.white),
                title: const Text('Play next', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.playerService.addToQueue(playableTrack);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added "${item.title}" to play next')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add, color: Colors.white),
                title: const Text('Add to playlist', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  showAddToPlaylistSheet(
                    context: context,
                    track: track,
                    playlistService: widget.playlistService,
                    accentColor: widget.settingsService.accentColor,
                  );
                },
              ),
              if (item.videoId != null && item.videoId!.isNotEmpty)
                ListTile(
                  leading: Icon(
                    isDownloaded ? Icons.delete_outline_rounded : Icons.download_rounded,
                    color: isDownloaded ? Colors.redAccent : widget.settingsService.accentColor,
                  ),
                  title: Text(
                    isDownloaded ? 'Remove from downloads' : 'Download (Space Saver Opus)',
                    style: TextStyle(
                      color: isDownloaded ? Colors.redAccent : Colors.white,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (isDownloaded) {
                      await _downloadService.deleteDownload(item.videoId!);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Removed "${item.title}" from downloads')),
                        );
                      }
                    } else {
                      _downloadService.downloadTrack(playableTrack);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Downloading "${item.title}" in Space-Saver Opus…')),
                        );
                      }
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close_rounded, color: Colors.white70),
                title: const Text('Remove from cache history', style: TextStyle(color: Colors.white70)),
                onTap: () {
                  Navigator.pop(ctx);
                  _historyService.removeTrack(item.title, item.artist);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.settingsService.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                title: const Text('Clear All Cached Songs', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  _historyService.clearHistory();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cached song history cleared')),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
