import 'dart:io';
import 'package:flutter/material.dart';
import 'package:finaudio/services/download_service.dart';
import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/settings_service.dart';

/// Full-featured Downloads / Offline screen matching ArchiveTune styling.
/// Displays Downloaded songs and In-progress downloads with speed & space tracking.
class DownloadsScreen extends StatefulWidget {
  final PlayerService playerService;
  final SettingsService settingsService;

  const DownloadsScreen({
    super.key,
    required this.playerService,
    required this.settingsService,
  });

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final DownloadService _downloadService = DownloadService.instance;
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _downloadService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _downloadService.removeListener(_onServiceUpdate);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.settingsService.backgroundColor;
    final surface = widget.settingsService.surfaceColor;
    final text = widget.settingsService.textColor;
    final accent = widget.settingsService.accentColor;

    final downloads = _downloadService.downloadedTracks;
    final activeTasks = _downloadService.activeTasks;

    final filteredDownloads = _searchQuery.isEmpty
        ? downloads
        : downloads.where((d) {
            final q = _searchQuery.toLowerCase();
            return d.title.toLowerCase().contains(q) ||
                d.artist.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top App Bar
            _buildAppBar(text, accent),

            // Tab Bar: Downloaded / In progress
            _buildTabBar(text, accent),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Downloaded
                  _buildDownloadedTab(
                    filteredDownloads,
                    downloads.length,
                    surface,
                    text,
                    accent,
                  ),

                  // Tab 2: In progress
                  _buildInProgressTab(activeTasks, surface, text, accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(Color text, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 26),
            color: text,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          if (!_isSearching) ...[
            Text(
              'Downloads',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: text,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.search_rounded, size: 24),
              color: text,
              onPressed: () {
                setState(() => _isSearching = true);
              },
            ),
          ] else ...[
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: text, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search downloads…',
                  hintStyle: TextStyle(color: text.withAlpha(120)),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 22),
              color: text,
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar(Color text, Color accent) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: text.withAlpha(20),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: accent,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: accent,
        unselectedLabelColor: text.withAlpha(140),
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.check_circle_outline_rounded, size: 18),
                SizedBox(width: 8),
                Text('Downloaded'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.download_rounded, size: 18),
                const SizedBox(width: 8),
                const Text('In progress'),
                if (_downloadService.activeTasks.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_downloadService.activeTasks.length}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
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

  Widget _buildDownloadedTab(
    List<DownloadedTrack> filteredList,
    int totalCount,
    Color surface,
    Color text,
    Color accent,
  ) {
    final hasActive = _downloadService.activeTasks.isNotEmpty;

    if (totalCount == 0) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (hasActive) _buildActiveProgressBanner(surface, text, accent),
          const SizedBox(height: 48),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_download_outlined,
                    size: 36,
                    color: text.withAlpha(120),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No downloaded songs',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Downloaded tracks are saved in space-saving Opus format for offline playback with minimal storage.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: text.withAlpha(140),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Live in-progress banner if downloads are running
        if (hasActive) ...[
          _buildActiveProgressBanner(surface, text, accent),
          const SizedBox(height: 12),
        ],

        // Songs Header Card (ArchiveTune styling)
        _buildSongsHeaderCard(totalCount, surface, text, accent),

        const SizedBox(height: 12),

        // Downloaded items list
        ...filteredList.map((track) => _buildDownloadedTrackItem(track, surface, text, accent)),
      ],
    );
  }

  Widget _buildActiveProgressBanner(Color surface, Color text, Color accent) {
    final count = _downloadService.activeTasks.length;
    return Container(
      decoration: BoxDecoration(
        color: accent.withAlpha(30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withAlpha(80)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _tabController.animateTo(1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _downloadService.queuedCount > 0
                            ? 'Downloading ${_downloadService.runningCount} of $count (${_downloadService.queuedCount} queued)…'
                            : 'Downloading $count song${count == 1 ? '' : 's'}…',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to monitor active speeds & progress in real time',
                        style: TextStyle(
                          fontSize: 12,
                          color: text.withAlpha(160),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: accent, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongsHeaderCard(int count, Color surface, Color text, Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Play all downloaded songs
            final all = _downloadService.downloadedTracks;
            if (all.isNotEmpty) {
              widget.playerService.playTrack(all.first.toTrack());
              for (int i = 1; i < all.length; i++) {
                widget.playerService.addToQueue(all[i].toTrack());
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Music note icon in rounded themed container
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.music_note_rounded,
                      color: accent,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Title and count
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Songs',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$count song${count == 1 ? '' : 's'} • ${_downloadService.formattedStorageUsed}',
                        style: TextStyle(
                          fontSize: 13,
                          color: text.withAlpha(150),
                        ),
                      ),
                    ],
                  ),
                ),
                // Delete All button (circular accent icon)
                GestureDetector(
                  onTap: _confirmDeleteAll,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.black,
                      size: 20,
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

  Widget _buildDownloadedTrackItem(DownloadedTrack track, Color surface, Color text, Color accent) {
    final thumbFile = track.thumbnailFilePath != null ? File(track.thumbnailFilePath!) : null;
    final hasLocalThumb = thumbFile != null && thumbFile.existsSync();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            widget.playerService.playTrack(track.toTrack());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Artwork thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: Colors.black26,
                    child: hasLocalThumb
                        ? Image.file(thumbFile, fit: BoxFit.cover)
                        : (track.thumbnailUrl != null &&
                                track.thumbnailUrl!.isNotEmpty &&
                                (track.thumbnailUrl!.startsWith('http://') ||
                                    track.thumbnailUrl!.startsWith('https://')))
                            ? Image.network(
                                track.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.music_note,
                                  color: Colors.white54,
                                ),
                              )
                            : (track.youtubeVideoId != null && track.youtubeVideoId!.isNotEmpty)
                                ? Image.network(
                                    'https://img.youtube.com/vi/${track.youtubeVideoId}/hqdefault.jpg',
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
                const SizedBox(width: 12),

                // Title and Artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
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
                          Expanded(
                            child: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: text.withAlpha(150),
                              ),
                            ),
                          ),
                          // Codec pill badge (OPUS or AAC)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: text.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              track.audioCodec,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: text.withAlpha(180),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Duration Pill badge (ArchiveTune style: "1:20")
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatDuration(track.duration),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: text.withAlpha(180),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Delete trash button (circular themed button matching ArchiveTune layout)
                GestureDetector(
                  onTap: () => _confirmDeleteTrack(track),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.black,
                      size: 19,
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

  Widget _buildInProgressTab(
    List<DownloadTask> tasks,
    Color surface,
    Color text,
    Color accent,
  ) {
    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 48,
                color: text.withAlpha(100),
              ),
              const SizedBox(height: 16),
              Text(
                'No downloads in progress',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: text,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = tasks[index];
        final isFailed = task.status == DownloadStatus.failed;
        final isQueued = task.status == DownloadStatus.queued;
        final percent = (task.progress * 100).toInt();
        final downloadedMb = (task.downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
        final totalMb = (task.totalBytes / (1024 * 1024)).toStringAsFixed(1);
        final speedKb = (task.speedBytesPerSec / 1024).round();

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: isFailed ? Border.all(color: Colors.redAccent.withAlpha(120)) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 44,
                      height: 44,
                      color: Colors.black26,
                      child: task.thumbnailUrl != null
                          ? Image.network(
                              task.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(Icons.music_note),
                            )
                          : const Icon(Icons.music_note),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: text.withAlpha(140),
                                ),
                              ),
                            ),
                            if (isQueued)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: text.withAlpha(25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.schedule_rounded, size: 11, color: text.withAlpha(160)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Queued',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: text.withAlpha(180),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isFailed) ...[
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Retry Download',
                      color: accent,
                      onPressed: () => _downloadService.retryDownload(task.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Dismiss',
                      color: text.withAlpha(160),
                      onPressed: () => _downloadService.dismissTask(task.id),
                    ),
                  ] else ...[
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Cancel',
                      color: text.withAlpha(160),
                      onPressed: () => _downloadService.cancelDownload(task.id),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              if (isFailed) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          task.error ?? 'Download failed',
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isQueued) ...[
                // Queued Progress Bar (flat static bar at 0, no CPU-wasting animation)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: 0.0,
                    backgroundColor: text.withAlpha(20),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Waiting in queue…',
                      style: TextStyle(
                        fontSize: 12,
                        color: text.withAlpha(140),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      'Pending',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: text.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: task.progress > 0 ? task.progress : null,
                    backgroundColor: text.withAlpha(20),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),

                // Speed & byte stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$percent% • $downloadedMb MB / $totalMb MB',
                      style: TextStyle(
                        fontSize: 12,
                        color: text.withAlpha(160),
                      ),
                    ),
                    if (speedKb > 0)
                      Text(
                        '$speedKb KB/s',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteTrack(DownloadedTrack track) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.settingsService.surfaceColor,
        title: const Text('Delete Download'),
        content: Text('Remove "${track.title}" from offline downloads?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadService.deleteDownload(track.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.settingsService.surfaceColor,
        title: const Text('Clear All Downloads'),
        content: const Text(
          'Delete all offline tracks and free up storage?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadService.deleteAllDownloads();
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

