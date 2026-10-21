import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ytmusicapi_dart/enums.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

import '../models/local_playlist.dart';
import '../services/google_auth_service.dart';
import '../services/player_service.dart';
import '../services/playlist_service.dart';
import '../services/settings_service.dart';
import '../widgets/add_to_playlist_sheet.dart';
import 'artist_screen.dart';

/// Dedicated screen for Albums, EPs, Singles, and Curated/Community Playlists.
/// Displays high-resolution cover artwork, metadata (artist, year, track count,
/// total duration), Play All, Shuffle, track search filtering, and the complete
/// song list with track numbers, live playback indicator, and options menu.
class AlbumViewScreen extends StatefulWidget {
  final String title;
  final String? artist;
  final String? browseId;
  final String? playlistId;
  final String? coverUrl;
  final String? year;
  final String? type; // 'Album', 'Single', 'EP', 'Playlist', 'Mix'
  final String? subtitle;
  final List<LocalPlaylistTrack>? initialTracks;
  final bool isPlaylist;
  final bool isEmbedded;
  final VoidCallback? onBack;

  final PlayerService playerService;
  final PlaylistService playlistService;
  final SettingsService settingsService;
  final GoogleAuthService? authService;

  const AlbumViewScreen({
    super.key,
    required this.title,
    this.artist,
    this.browseId,
    this.playlistId,
    this.coverUrl,
    this.year,
    this.type,
    this.subtitle,
    this.initialTracks,
    this.isPlaylist = false,
    this.isEmbedded = false,
    this.onBack,
    required this.playerService,
    required this.playlistService,
    required this.settingsService,
    this.authService,
  });

  @override
  State<AlbumViewScreen> createState() => _AlbumViewScreenState();
}

class _AlbumViewScreenState extends State<AlbumViewScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Track> _tracks = [];
  bool _loading = true;
  String? _error;
  bool _showSearchBar = false;
  String _searchQuery = '';

  String? _resolvedTitle;
  String? _resolvedArtist;
  String? _resolvedCoverUrl;
  String? _resolvedYear;
  String? _resolvedType;
  String? _resolvedDescription;

  StreamSubscription<Track?>? _trackSub;
  Track? _currentTrack;

  @override
  void initState() {
    super.initState();
    _resolvedTitle = widget.title;
    _resolvedArtist = widget.artist;
    _resolvedCoverUrl = widget.coverUrl;
    _resolvedYear = widget.year;
    _resolvedType = widget.type ?? (widget.isPlaylist ? 'Playlist' : 'Album');

    _currentTrack = widget.playerService.currentTrack;
    _trackSub = widget.playerService.nowPlayingStream.listen((t) {
      if (mounted) setState(() => _currentTrack = t);
    });

    _loadTracks();
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTracks() async {
    // 0. If pre-supplied tracks exist (e.g. custom mix)
    if (widget.initialTracks != null && widget.initialTracks!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _tracks = widget.initialTracks!
              .map((t) => Track.fromLocalPlaylistTrack(t))
              .toList();
          _loading = false;
        });
      }
      return;
    }

    final bool isTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTest) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final yt = await YTMusic.create();

      // 1. Try fetching via browseId (official album)
      if (widget.browseId != null && widget.browseId!.isNotEmpty) {
        try {
          final albumData = await yt.getAlbum(widget.browseId!);
          _extractAlbumData(albumData);
          if (_tracks.isNotEmpty) {
            if (mounted) setState(() => _loading = false);
            return;
          }
        } catch (e) {
          debugPrint('AlbumViewScreen: yt.getAlbum failed ($e)');
        }
      }

      // 2. Try fetching via playlistId (official or community playlist)
      final effectivePlaylistId = widget.playlistId ??
          (widget.browseId != null && widget.browseId!.startsWith('VL')
              ? widget.browseId!.substring(2)
              : null);

      if (effectivePlaylistId != null && effectivePlaylistId.isNotEmpty) {
        try {
          final plData = await yt.getPlaylist(effectivePlaylistId);
          _extractPlaylistData(plData);
          if (_tracks.isNotEmpty) {
            if (mounted) setState(() => _loading = false);
            return;
          }
        } catch (e) {
          debugPrint('AlbumViewScreen: yt.getPlaylist failed ($e)');
        }
      }

      // 3. Search YT Music
      final query = '${widget.title} ${widget.artist ?? ''}'.trim();

      // If album, try search albums first to get the official browseId
      if (!widget.isPlaylist) {
        try {
          final albumResults = await yt.search(
            query,
            filter: SearchFilterType.albums,
            limit: 4,
          );
          for (final item in albumResults) {
            if (item is Map && item['browseId'] != null) {
              final bId = item['browseId'].toString();
              final albumData = await yt.getAlbum(bId);
              _extractAlbumData(albumData);
              if (_tracks.isNotEmpty) {
                if (mounted) setState(() => _loading = false);
                return;
              }
            }
          }
        } catch (e) {
          debugPrint('AlbumViewScreen: album search failed ($e)');
        }
      } else {
        // If playlist, try community playlists search
        try {
          final plResults = await yt.search(
            query,
            filter: SearchFilterType.playlists,
            limit: 4,
          );
          for (final item in plResults) {
            if (item is Map) {
              final pId = (item['playlistId'] ?? item['browseId'])?.toString();
              if (pId != null && pId.isNotEmpty) {
                final cleanId = pId.startsWith('VL') ? pId.substring(2) : pId;
                final plData = await yt.getPlaylist(cleanId);
                _extractPlaylistData(plData);
                if (_tracks.isNotEmpty) {
                  if (mounted) setState(() => _loading = false);
                  return;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('AlbumViewScreen: playlist search failed ($e)');
        }
      }

      // 4. Fallback: Search songs directly for the album/playlist title + artist
      try {
        final songResults = await yt.search(
          query,
          filter: SearchFilterType.songs,
          limit: 25,
        );
        _extractSongResults(songResults);
      } catch (e) {
        debugPrint('AlbumViewScreen: song search fallback failed ($e)');
      }
    } catch (e) {
      debugPrint('AlbumViewScreen error: $e');
      _error = 'Could not load tracklist. Please check your network connection.';
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _extractAlbumData(Map<String, dynamic> data) {
    _resolvedTitle ??= data['title']?.toString();
    _resolvedDescription ??= data['description']?.toString();
    _resolvedYear ??= data['year']?.toString();
    _resolvedType ??= data['type']?.toString();

    if (data['artists'] is List && (data['artists'] as List).isNotEmpty) {
      final names = (data['artists'] as List)
          .map((a) => a is Map ? a['name']?.toString() : a.toString())
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');
      if (names.isNotEmpty) _resolvedArtist ??= names;
    }

    if (data['thumbnails'] is List && (data['thumbnails'] as List).isNotEmpty) {
      final last = (data['thumbnails'] as List).last;
      if (last is Map && last['url'] != null) {
        _resolvedCoverUrl ??= last['url'].toString();
      }
    }

    final rawTracks = data['tracks'] as List? ?? [];
    final list = <Track>[];
    for (final t in rawTracks) {
      if (t is! Map) continue;
      final vId = t['videoId']?.toString();
      if (vId == null || vId.isEmpty) continue;
      final title = t['title']?.toString() ?? 'Untitled';

      String artist = _resolvedArtist ?? widget.artist ?? 'Unknown Artist';
      if (t['artists'] is List && (t['artists'] as List).isNotEmpty) {
        final names = (t['artists'] as List)
            .map((a) => a is Map ? a['name']?.toString() : a.toString())
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        if (names.isNotEmpty) artist = names;
      }

      Duration dur = Duration.zero;
      if (t['duration_seconds'] is num) {
        dur = Duration(seconds: (t['duration_seconds'] as num).toInt());
      } else if (t['duration'] is String) {
        dur = _parseDuration(t['duration'] as String);
      }

      String? thumb = _resolvedCoverUrl ?? widget.coverUrl;
      if (t['thumbnails'] is List && (t['thumbnails'] as List).isNotEmpty) {
        final last = (t['thumbnails'] as List).last;
        if (last is Map && last['url'] != null) {
          thumb = last['url'].toString();
        }
      }

      list.add(Track.fromPlaylistVideo(
        videoId: vId,
        title: title,
        author: artist,
        duration: dur,
        thumbnailUrl: thumb,
      ));
    }

    if (list.isNotEmpty) {
      _tracks = list;
    }
  }

  void _extractPlaylistData(Map<String, dynamic> data) {
    _resolvedTitle ??= data['title']?.toString();
    _resolvedDescription ??= data['description']?.toString();
    _resolvedYear ??= data['year']?.toString();

    if (data['author'] is Map && data['author']['name'] != null) {
      _resolvedArtist ??= data['author']['name'].toString();
    } else if (data['author'] is String && (data['author'] as String).isNotEmpty) {
      _resolvedArtist ??= data['author'] as String;
    } else if (data['artists'] is List && (data['artists'] as List).isNotEmpty) {
      final names = (data['artists'] as List)
          .map((a) => a is Map ? a['name']?.toString() : a.toString())
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');
      if (names.isNotEmpty) _resolvedArtist ??= names;
    }

    if (data['thumbnails'] is List && (data['thumbnails'] as List).isNotEmpty) {
      final last = (data['thumbnails'] as List).last;
      if (last is Map && last['url'] != null) {
        _resolvedCoverUrl ??= last['url'].toString();
      }
    }

    final rawTracks = data['tracks'] as List? ?? [];
    final list = <Track>[];
    for (final t in rawTracks) {
      if (t is! Map) continue;
      final vId = t['videoId']?.toString();
      if (vId == null || vId.isEmpty) continue;
      final title = t['title']?.toString() ?? 'Untitled';

      String artist = _resolvedArtist ?? widget.artist ?? 'YouTube Music';
      if (t['artists'] is List && (t['artists'] as List).isNotEmpty) {
        final names = (t['artists'] as List)
            .map((a) => a is Map ? a['name']?.toString() : a.toString())
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        if (names.isNotEmpty) artist = names;
      }

      Duration dur = Duration.zero;
      if (t['duration_seconds'] is num) {
        dur = Duration(seconds: (t['duration_seconds'] as num).toInt());
      } else if (t['duration'] is String) {
        dur = _parseDuration(t['duration'] as String);
      }

      String? thumb = _resolvedCoverUrl ?? widget.coverUrl;
      if (t['thumbnails'] is List && (t['thumbnails'] as List).isNotEmpty) {
        final last = (t['thumbnails'] as List).last;
        if (last is Map && last['url'] != null) {
          thumb = last['url'].toString();
        }
      }

      list.add(Track.fromPlaylistVideo(
        videoId: vId,
        title: title,
        author: artist,
        duration: dur,
        thumbnailUrl: thumb,
      ));
    }

    if (list.isNotEmpty) {
      _tracks = list;
    }
  }

  void _extractSongResults(List<dynamic> results) {
    final list = <Track>[];
    for (final item in results) {
      if (item is! Map) continue;
      final vId = item['videoId']?.toString();
      if (vId == null || vId.isEmpty) continue;
      final title = item['title']?.toString() ?? 'Untitled';

      String artist = widget.artist ?? 'YouTube Music';
      final artists = item['artists'];
      if (artists is List && artists.isNotEmpty) {
        final names = artists
            .map((a) => a is Map ? a['name']?.toString() : a.toString())
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        if (names.isNotEmpty) artist = names;
      }

      Duration dur = Duration.zero;
      if (item['duration_seconds'] is num) {
        dur = Duration(seconds: (item['duration_seconds'] as num).toInt());
      } else if (item['duration'] is String) {
        dur = _parseDuration(item['duration'] as String);
      }

      String? thumb = widget.coverUrl;
      final thumbs = item['thumbnails'];
      if (thumbs is List && thumbs.isNotEmpty) {
        final last = thumbs.last;
        if (last is Map && last['url'] != null) {
          thumb = last['url'].toString();
        }
      }

      list.add(Track.fromPlaylistVideo(
        videoId: vId,
        title: title,
        author: artist,
        duration: dur,
        thumbnailUrl: thumb,
      ));
    }

    if (list.isNotEmpty) {
      _tracks = list;
    }
  }

  static Duration _parseDuration(String durationStr) {
    final parts = durationStr.trim().split(':');
    if (parts.length == 2) {
      final mins = int.tryParse(parts[0]) ?? 0;
      final secs = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: mins, seconds: secs);
    } else if (parts.length == 3) {
      final hrs = int.tryParse(parts[0]) ?? 0;
      final mins = int.tryParse(parts[1]) ?? 0;
      final secs = int.tryParse(parts[2]) ?? 0;
      return Duration(hours: hrs, minutes: mins, seconds: secs);
    }
    return Duration.zero;
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatTotalDuration(List<Track> list) {
    final totalSecs = list.fold<int>(0, (acc, t) => acc + t.duration.inSeconds);
    if (totalSecs == 0) return '';
    final dur = Duration(seconds: totalSecs);
    if (dur.inHours > 0) {
      return '${dur.inHours} hr ${dur.inMinutes % 60} min';
    }
    return '${dur.inMinutes} min';
  }

  List<Track> get _filteredTracks {
    if (_searchQuery.trim().isEmpty) return _tracks;
    final q = _searchQuery.trim().toLowerCase();
    return _tracks.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.author.toLowerCase().contains(q);
    }).toList();
  }

  void _playAll({bool shuffle = false}) {
    if (_tracks.isEmpty) return;
    HapticFeedback.lightImpact();
    if (shuffle) {
      final shuffled = List<Track>.from(_tracks)..shuffle();
      widget.playerService.playList(shuffled, startIndex: 0);
    } else {
      widget.playerService.playList(_tracks, startIndex: 0);
    }
  }

  void _openArtistPage(String artistName) {
    if (widget.authService == null || artistName.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistScreen(
          artistName: artistName,
          playerService: widget.playerService,
          authService: widget.authService!,
          playlistService: widget.playlistService,
          settingsService: widget.settingsService,
        ),
      ),
    );
  }

  void _showTrackOptionsMenu(Track track) {
    final surface = widget.settingsService.surfaceColor;
    final accent = widget.settingsService.accentColor;
    final text = widget.settingsService.textColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: text.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: track.thumbnailUrl != null
                      ? CachedNetworkImage(
                          imageUrl: track.thumbnailUrl!,
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Container(
                            width: 46,
                            height: 46,
                            color: text.withAlpha(20),
                            child: Icon(Icons.music_note, color: accent),
                          ),
                        )
                      : Container(
                          width: 46,
                          height: 46,
                          color: text.withAlpha(20),
                          child: Icon(Icons.music_note, color: accent),
                        ),
                ),
                title: Text(
                  track.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.author,
                  style: TextStyle(color: text.withAlpha(160)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.playlist_play_rounded, color: text),
                title: Text('Play next', style: TextStyle(color: text)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.playerService.playNext(track);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Playing "${track.title}" next')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.queue_music_rounded, color: text),
                title: Text('Add to queue', style: TextStyle(color: text)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.playerService.addToQueue(track);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added "${track.title}" to queue')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.playlist_add_rounded, color: text),
                title: Text('Add to playlist', style: TextStyle(color: text)),
                onTap: () {
                  Navigator.pop(ctx);
                  final localTrack = LocalPlaylistTrack(
                    title: track.title,
                    artist: track.author,
                    duration: track.duration,
                    youtubeVideoId: track.id,
                    thumbnailUrl: track.thumbnailUrl,
                  );
                  showAddToPlaylistSheet(
                    context: context,
                    track: localTrack,
                    playlistService: widget.playlistService,
                    accentColor: accent,
                    surfaceColor: surface,
                    textColor: text,
                  );
                },
              ),
              if (widget.authService != null) ...[
                if (track.individualArtists.length > 1) ...[
                  for (final artist in track.individualArtists)
                    ListTile(
                      leading: Icon(Icons.person_rounded, color: text),
                      title: Text('Go to artist ($artist)',
                          style: TextStyle(color: text)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _openArtistPage(artist);
                      },
                    ),
                ] else if (track.author.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.person_rounded, color: text),
                    title: Text(
                        'Go to artist (${track.individualArtists.firstOrNull ?? track.author})',
                        style: TextStyle(color: text)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openArtistPage(track.individualArtists.firstOrNull ?? track.author);
                    },
                  ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.settingsService.backgroundColor;
    final surface = widget.settingsService.surfaceColor;
    final accent = widget.settingsService.accentColor;
    final text = widget.settingsService.textColor;
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black;

    final isDesktop = MediaQuery.of(context).size.width >= 800 || widget.isEmbedded;
    final displayTitle = _resolvedTitle ?? widget.title;
    final displayArtist = _resolvedArtist ?? widget.artist ?? '';
    final displayCover = _resolvedCoverUrl ?? widget.coverUrl;
    final displayType = _resolvedType ?? (widget.isPlaylist ? 'Playlist' : 'Album');
    final totalDurationStr = _formatTotalDuration(_tracks);
    final filtered = _filteredTracks;

    final scrollContent = CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Top App Bar for mobile or non-embedded desktop
        if (!isDesktop)
          SliverAppBar(
            pinned: true,
            elevation: 0,
            backgroundColor: bg,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 20),
              onPressed: () {
                if (widget.onBack != null) {
                  widget.onBack!();
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
            title: Text(
              displayTitle,
              style: TextStyle(
                color: text,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (_tracks.isNotEmpty)
                IconButton(
                  icon: Icon(
                    _showSearchBar
                        ? Icons.close_rounded
                        : Icons.search_rounded,
                    color: text,
                  ),
                  onPressed: () {
                    setState(() {
                      _showSearchBar = !_showSearchBar;
                      if (!_showSearchBar) {
                        _searchQuery = '';
                        _searchController.clear();
                      }
                    });
                  },
                ),
            ],
          )
        else if (!widget.isEmbedded)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: text),
                    tooltip: 'Back',
                    onPressed: () {
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

        // 2. In-screen Search bar (for mobile if active)
        if (!isDesktop && _showSearchBar)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: text),
                decoration: InputDecoration(
                  hintText: 'Search songs in this ${displayType.toLowerCase()}...',
                  hintStyle: TextStyle(color: text.withAlpha(120), fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: text.withAlpha(150), size: 20),
                  filled: true,
                  fillColor: surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (q) => setState(() => _searchQuery = q),
              ),
            ),
          ),

        // 3. Header
        if (isDesktop)
          // Spotify Desktop Header Banner
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withAlpha(35),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // High-res Cover Art
                  Container(
                    width: 192,
                    height: 192,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(120),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: displayCover != null && displayCover.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: displayCover,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(color: surface),
                            errorWidget: (_, _, _) => Container(
                              color: surface,
                              child: Icon(
                                widget.isPlaylist ? Icons.playlist_play_rounded : Icons.album_rounded,
                                color: text.withAlpha(80),
                                size: 64,
                              ),
                            ),
                          )
                        : Container(
                            color: surface,
                            child: Icon(
                              widget.isPlaylist ? Icons.playlist_play_rounded : Icons.album_rounded,
                              color: text.withAlpha(80),
                              size: 64,
                            ),
                          ),
                  ),
                  const SizedBox(width: 24),
                  // Metadata Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayType.toUpperCase(),
                          style: TextStyle(
                            color: text.withAlpha(180),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          displayTitle,
                          style: TextStyle(
                            color: text,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                            height: 1.15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (displayArtist.isNotEmpty) ...[
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _openArtistPage(displayArtist),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 11,
                                      backgroundColor: accent.withAlpha(40),
                                      child: Icon(Icons.person_rounded, size: 13, color: accent),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      displayArtist,
                                      style: TextStyle(
                                        color: text,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(' • ', style: TextStyle(color: text.withAlpha(140), fontSize: 13)),
                            ],
                            if (_resolvedYear != null && _resolvedYear!.isNotEmpty) ...[
                              Text('$_resolvedYear • ', style: TextStyle(color: text.withAlpha(140), fontSize: 13)),
                            ],
                            if (_tracks.isNotEmpty) ...[
                              Text(
                                '${_tracks.length} ${_tracks.length == 1 ? 'song' : 'songs'}',
                                style: TextStyle(color: text.withAlpha(160), fontSize: 13),
                              ),
                              if (totalDurationStr.isNotEmpty)
                                Text(', $totalDurationStr', style: TextStyle(color: text.withAlpha(130), fontSize: 13)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          // Mobile Hero Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(80),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: displayCover != null && displayCover.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: displayCover,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => Container(color: surface),
                                errorWidget: (_, _, _) => Container(
                                  color: surface,
                                  child: Icon(
                                    widget.isPlaylist
                                        ? Icons.playlist_play_rounded
                                        : Icons.album_rounded,
                                    color: text.withAlpha(80),
                                    size: 64,
                                  ),
                                ),
                              )
                            : Container(
                                color: surface,
                                child: Icon(
                                  widget.isPlaylist
                                      ? Icons.playlist_play_rounded
                                      : Icons.album_rounded,
                                  color: text.withAlpha(80),
                                  size: 64,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    displayTitle,
                    style: TextStyle(
                      color: text,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  if (displayArtist.isNotEmpty)
                    GestureDetector(
                      onTap: () => _openArtistPage(displayArtist),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 11,
                            backgroundColor: accent.withAlpha(40),
                            child: Icon(Icons.person_rounded, size: 13, color: accent),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              displayArtist,
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, size: 16, color: text.withAlpha(140)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: text.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          displayType.toUpperCase(),
                          style: TextStyle(
                            color: text.withAlpha(200),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (_resolvedYear != null && _resolvedYear!.isNotEmpty) ...[
                        Text(' • $_resolvedYear', style: TextStyle(color: text.withAlpha(140), fontSize: 12)),
                      ],
                      if (_tracks.isNotEmpty) ...[
                        Text(
                          ' • ${_tracks.length} ${_tracks.length == 1 ? 'song' : 'songs'}',
                          style: TextStyle(color: text.withAlpha(140), fontSize: 12),
                        ),
                        if (totalDurationStr.isNotEmpty) ...[
                          Text(', $totalDurationStr', style: TextStyle(color: text.withAlpha(140), fontSize: 12)),
                        ],
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _playAll(shuffle: false),
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accent.withAlpha(120),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(Icons.play_arrow_rounded, size: 32, color: onAccent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      IconButton(
                        iconSize: 26,
                        icon: Icon(Icons.shuffle_rounded, color: text.withAlpha(200)),
                        tooltip: 'Shuffle',
                        onPressed: () => _playAll(shuffle: true),
                      ),
                      const Spacer(),
                      if (!_showSearchBar && _tracks.isNotEmpty)
                        IconButton(
                          iconSize: 22,
                          icon: Icon(Icons.filter_list_rounded, color: text.withAlpha(180)),
                          tooltip: 'Filter tracks',
                          onPressed: () => setState(() => _showSearchBar = true),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Desktop Action Toolbar
        if (isDesktop)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              child: Row(
                children: [
                  // Large circular play button
                  Material(
                    color: accent,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _playAll(shuffle: false),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: Center(
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 32,
                            color: onAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Shuffle button
                  IconButton(
                    iconSize: 22,
                    icon: Icon(Icons.shuffle_rounded, color: text.withAlpha(190)),
                    tooltip: 'Shuffle',
                    onPressed: () => _playAll(shuffle: true),
                  ),
                  const Spacer(),
                  // Search filter input
                  Container(
                    width: 220,
                    height: 32,
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: text.withAlpha(22)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 16, color: text.withAlpha(140)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(fontSize: 12, color: text),
                            decoration: InputDecoration(
                              hintText: 'Search in this ${displayType.toLowerCase()}',
                              hintStyle: TextStyle(fontSize: 11, color: text.withAlpha(120)),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val.trim()),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: Icon(Icons.close_rounded, size: 14, color: text.withAlpha(140)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Desktop Table Header
        if (isDesktop && filtered.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            '#',
                            style: TextStyle(
                              color: text.withAlpha(140),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Title',
                            style: TextStyle(
                              color: text.withAlpha(140),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Icon(Icons.access_time_rounded, size: 16, color: text.withAlpha(140)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: text.withAlpha(20)),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),

        // 4. Loading Indicator
        if (_loading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Loading tracklist...',
                      style: TextStyle(color: text.withAlpha(150), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 5. Error State
        if (!_loading && _error != null && _tracks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent.withAlpha(200),
                      size: 42,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: text.withAlpha(180), fontSize: 14),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: surface,
                        foregroundColor: text,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                      onPressed: _loadTracks,
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 6. Empty State
        if (!_loading && _tracks.isEmpty && _error == null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No tracks found in this ${displayType.toLowerCase()}.',
                  style: TextStyle(color: text.withAlpha(140), fontSize: 14),
                ),
              ),
            ),
          ),

        // 7. Track List
        if (filtered.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 28 : 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = filtered[index];
                  final isCurrentPlaying = _currentTrack?.id == track.id;

                  if (isDesktop) {
                    return _DesktopAlbumTrackRow(
                      index: index + 1,
                      track: track,
                      isCurrentPlaying: isCurrentPlaying,
                      accent: accent,
                      text: text,
                      surface: surface,
                      durStr: _formatDuration(track.duration),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.playerService.playList(filtered, startIndex: index);
                      },
                      onOptions: () => _showTrackOptionsMenu(track),
                    );
                  }

                  return InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.playerService.playList(filtered, startIndex: index);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: isCurrentPlaying
                                ? Icon(
                                    Icons.equalizer_rounded,
                                    size: 18,
                                    color: accent,
                                  )
                                : Text(
                                    '${index + 1}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: text.withAlpha(130),
                                      fontSize: 14,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isCurrentPlaying ? accent : text,
                                    fontSize: 15,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  track.author,
                                  style: TextStyle(
                                    color: text.withAlpha(150),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (track.duration != Duration.zero)
                            Text(
                              _formatDuration(track.duration),
                              style: TextStyle(
                                color: text.withAlpha(130),
                                fontSize: 12,
                              ),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              Icons.more_vert_rounded,
                              size: 18,
                              color: text.withAlpha(150),
                            ),
                            onPressed: () => _showTrackOptionsMenu(track),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: filtered.length,
              ),
            ),
          ),

        // Clearance
        const SliverToBoxAdapter(
          child: SizedBox(height: 60),
        ),
      ],
    );

    if (widget.isEmbedded) {
      return Material(
        color: Colors.transparent,
        child: scrollContent,
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: scrollContent,
    );
  }
}

class _DesktopAlbumTrackRow extends StatefulWidget {
  final int index;
  final Track track;
  final bool isCurrentPlaying;
  final Color accent;
  final Color text;
  final Color surface;
  final String durStr;
  final VoidCallback onTap;
  final VoidCallback onOptions;

  const _DesktopAlbumTrackRow({
    required this.index,
    required this.track,
    required this.isCurrentPlaying,
    required this.accent,
    required this.text,
    required this.surface,
    required this.durStr,
    required this.onTap,
    required this.onOptions,
  });

  @override
  State<_DesktopAlbumTrackRow> createState() => _DesktopAlbumTrackRowState();
}

class _DesktopAlbumTrackRowState extends State<_DesktopAlbumTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? widget.text.withAlpha(18) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                // Index or Play Icon
                SizedBox(
                  width: 36,
                  child: Center(
                    child: widget.isCurrentPlaying
                        ? Icon(Icons.graphic_eq_rounded, color: widget.accent, size: 18)
                        : _hovered
                            ? Icon(Icons.play_arrow_rounded, color: widget.text, size: 20)
                            : Text(
                                '${widget.index}',
                                style: TextStyle(
                                  color: widget.text.withAlpha(140),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                  ),
                ),
                const SizedBox(width: 8),

                // Thumbnail if available
                if (widget.track.thumbnailUrl != null && widget.track.thumbnailUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: widget.track.thumbnailUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        width: 40,
                        height: 40,
                        color: widget.surface,
                        child: Icon(Icons.music_note, color: widget.text.withAlpha(80), size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // Title & Artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.track.title,
                        style: TextStyle(
                          color: widget.isCurrentPlaying ? widget.accent : widget.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.track.author,
                        style: TextStyle(
                          color: widget.text.withAlpha(160),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Duration
                if (widget.durStr.isNotEmpty)
                  Text(
                    widget.durStr,
                    style: TextStyle(
                      color: widget.text.withAlpha(140),
                      fontSize: 13,
                    ),
                  ),

                const SizedBox(width: 4),

                // Options Menu Button
                IconButton(
                  icon: Icon(Icons.more_horiz_rounded, size: 18, color: widget.text.withAlpha(160)),
                  splashRadius: 16,
                  onPressed: widget.onOptions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
