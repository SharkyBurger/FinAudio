import '../services/google_auth_service.dart';

/// Represents an artist returned in search results.
class SearchArtist {
  final String id;
  final String name;
  final String thumbnailUrl;
  final String? subscribers;

  const SearchArtist({
    required this.id,
    required this.name,
    required this.thumbnailUrl,
    this.subscribers,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'thumbnailUrl': thumbnailUrl,
        if (subscribers != null) 'subscribers': subscribers,
      };

  factory SearchArtist.fromJson(Map<String, dynamic> json) => SearchArtist(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        subscribers: json['subscribers'] as String?,
      );
}

/// Represents an album or single returned in search results.
class SearchAlbum {
  final String browseId;
  final String? playlistId;
  final String title;
  final String artist;
  final String? year;
  final String? type;
  final String thumbnailUrl;

  const SearchAlbum({
    required this.browseId,
    this.playlistId,
    required this.title,
    required this.artist,
    this.year,
    this.type,
    required this.thumbnailUrl,
  });

  Map<String, dynamic> toJson() => {
        'browseId': browseId,
        if (playlistId != null) 'playlistId': playlistId,
        'title': title,
        'artist': artist,
        if (year != null) 'year': year,
        if (type != null) 'type': type,
        'thumbnailUrl': thumbnailUrl,
      };

  factory SearchAlbum.fromJson(Map<String, dynamic> json) => SearchAlbum(
        browseId: json['browseId'] as String? ?? '',
        playlistId: json['playlistId'] as String?,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        year: json['year'] as String?,
        type: json['type'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      );
}

/// Represents a playlist returned in search results.
class SearchPlaylist {
  final String id;
  final String title;
  final String? author;
  final int? itemCount;
  final String thumbnailUrl;

  const SearchPlaylist({
    required this.id,
    required this.title,
    this.author,
    this.itemCount,
    required this.thumbnailUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (author != null) 'author': author,
        if (itemCount != null) 'itemCount': itemCount,
        'thumbnailUrl': thumbnailUrl,
      };

  factory SearchPlaylist.fromJson(Map<String, dynamic> json) => SearchPlaylist(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        author: json['author'] as String?,
        itemCount: json['itemCount'] as int?,
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      );
}

/// Top result card in Spotify search (can be an artist, song, album, or playlist).
class TopSearchResult {
  final String type; // 'artist', 'song', 'album', 'playlist'
  final dynamic data; // SearchArtist, PlaylistVideo, SearchAlbum, or SearchPlaylist

  const TopSearchResult({
    required this.type,
    required this.data,
  });

  bool get isArtist => type == 'artist';
  bool get isSong => type == 'song';
  bool get isAlbum => type == 'album';
  bool get isPlaylist => type == 'playlist';

  SearchArtist? get asArtist => data is SearchArtist ? data as SearchArtist : null;
  PlaylistVideo? get asSong => data is PlaylistVideo ? data as PlaylistVideo : null;
  SearchAlbum? get asAlbum => data is SearchAlbum ? data as SearchAlbum : null;
  SearchPlaylist? get asPlaylist => data is SearchPlaylist ? data as SearchPlaylist : null;
}

/// Consolidated Spotify-style search results containing top result and categorized collections.
class UnifiedSearchResults {
  final TopSearchResult? topResult;
  final List<PlaylistVideo> songs;
  final List<SearchArtist> artists;
  final List<SearchAlbum> albums;
  final List<SearchPlaylist> playlists;

  const UnifiedSearchResults({
    this.topResult,
    this.songs = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
  });

  bool get isEmpty =>
      topResult == null &&
      songs.isEmpty &&
      artists.isEmpty &&
      albums.isEmpty &&
      playlists.isEmpty;

  bool get isNotEmpty => !isEmpty;
}

