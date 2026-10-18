import 'dart:convert';

/// Represents a single track within a local or imported playlist.
class LocalPlaylistTrack {
  final String title;
  final String artist;
  final Duration duration;
  final String? spotifyUri;
  final String? youtubeVideoId;
  final String? thumbnailUrl;

  const LocalPlaylistTrack({
    required this.title,
    required this.artist,
    this.duration = Duration.zero,
    this.spotifyUri,
    this.youtubeVideoId,
    this.thumbnailUrl,
  });

  LocalPlaylistTrack copyWith({
    String? title,
    String? artist,
    Duration? duration,
    String? spotifyUri,
    String? youtubeVideoId,
    String? thumbnailUrl,
  }) {
    return LocalPlaylistTrack(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
      spotifyUri: spotifyUri ?? this.spotifyUri,
      youtubeVideoId: youtubeVideoId ?? this.youtubeVideoId,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }

  /// Separates multi-artist strings (e.g. "Artist1;Artist2;Artist3", "Artist1, Artist2",
  /// "Artist1 feat. Artist2", or "Artist1 & Artist2") into a clean list of individual artist names.
  static List<String> splitArtists(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return [];

    // 1. Explicit semicolon delimiter (used in Exportify and CSV exports)
    if (trimmed.contains(';')) {
      final items = trimmed
          .split(';')
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList();
      if (items.isNotEmpty) return items;
    }

    // 2. Comma delimiter: "Artist A, Artist B"
    if (trimmed.contains(',')) {
      final items = trimmed
          .split(RegExp(r',\s*'))
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList();
      if (items.length > 1) return items;
    }

    // 3. Feature, slash, or ampersand delimiters: " feat. ", " ft. ", " / ", " & "
    final splitRegex = RegExp(r'\s+(?:feat\.?|ft\.?|/|&)\s+', caseSensitive: false);
    if (splitRegex.hasMatch(trimmed)) {
      final items = trimmed
          .split(splitRegex)
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList();
      if (items.length > 1) return items;
    }

    return [trimmed];
  }

  /// Returns individual artist names parsed from [artist].
  List<String> get individualArtists => splitArtists(artist);

  /// Returns a clean human-readable artist string formatted with commas (e.g. "Artist 1, Artist 2").
  String get formattedArtist {
    final list = individualArtists;
    return list.isNotEmpty ? list.join(', ') : artist;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'durationMs': duration.inMilliseconds,
        'spotifyUri': spotifyUri,
        'youtubeVideoId': youtubeVideoId,
        'thumbnailUrl': thumbnailUrl,
      };

  factory LocalPlaylistTrack.fromJson(Map<String, dynamic> json) {
    return LocalPlaylistTrack(
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      spotifyUri: json['spotifyUri'] as String?,
      youtubeVideoId: json['youtubeVideoId'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }
}

/// Represents a user playlist saved locally in FinAudio
/// (can be imported from Spotify, custom created, or pasted from text).
class LocalPlaylist {
  final String id;
  final String title;
  final String description;
  final String thumbnailUrl;
  final String source; // 'spotify', 'local', 'text'
  final String? spotifyUrl;
  final String? spotifyId;
  final DateTime createdAt;
  final DateTime? lastSyncedAt;
  final List<LocalPlaylistTrack> tracks;

  const LocalPlaylist({
    required this.id,
    required this.title,
    this.description = '',
    this.thumbnailUrl = '',
    this.source = 'local',
    this.spotifyUrl,
    this.spotifyId,
    required this.createdAt,
    this.lastSyncedAt,
    this.tracks = const [],
  });

  int get trackCount => tracks.length;

  bool get isSpotify => source == 'spotify' || spotifyId != null;

  /// Whether this playlist is the special permanent Liked Songs playlist.
  bool get isLikedSongs => id == 'liked_songs' || source == 'system';

  /// Returns the custom thumbnail URL, or automatically resolves to the
  /// YouTube canvas/thumbnail of the first track in the playlist.
  String get effectiveThumbnailUrl {
    if (thumbnailUrl.trim().isNotEmpty) return thumbnailUrl.trim();
    for (final track in tracks) {
      if (track.thumbnailUrl != null && track.thumbnailUrl!.trim().isNotEmpty) {
        return track.thumbnailUrl!.trim();
      }
      if (track.youtubeVideoId != null && track.youtubeVideoId!.trim().isNotEmpty) {
        return 'https://img.youtube.com/vi/${track.youtubeVideoId}/hqdefault.jpg';
      }
    }
    return '';
  }

  LocalPlaylist copyWith({
    String? id,
    String? title,
    String? description,
    String? thumbnailUrl,
    String? source,
    String? spotifyUrl,
    String? spotifyId,
    DateTime? createdAt,
    DateTime? lastSyncedAt,
    List<LocalPlaylistTrack>? tracks,
  }) {
    return LocalPlaylist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      source: source ?? this.source,
      spotifyUrl: spotifyUrl ?? this.spotifyUrl,
      spotifyId: spotifyId ?? this.spotifyId,
      createdAt: createdAt ?? this.createdAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      tracks: tracks ?? this.tracks,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'thumbnailUrl': thumbnailUrl,
        'source': source,
        'spotifyUrl': spotifyUrl,
        'spotifyId': spotifyId,
        'createdAt': createdAt.toIso8601String(),
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) {
    return LocalPlaylist(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? 'Untitled Playlist',
      description: json['description'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      source: json['source'] as String? ?? 'local',
      spotifyUrl: json['spotifyUrl'] as String?,
      spotifyId: json['spotifyId'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.tryParse(json['lastSyncedAt'] as String)
          : null,
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((t) => LocalPlaylistTrack.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  static String encodeList(List<LocalPlaylist> list) =>
      jsonEncode(list.map((p) => p.toJson()).toList());

  static List<LocalPlaylist> decodeList(String jsonString) {
    if (jsonString.isEmpty) return [];
    try {
      final list = jsonDecode(jsonString) as List<dynamic>;
      return list
          .map((item) => LocalPlaylist.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
