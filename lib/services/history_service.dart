import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finaudio/models/local_playlist.dart';
import 'package:finaudio/services/player_service.dart';

/// Represents a track recorded in user playback history.
class HistoryItem {
  final String title;
  final String artist;
  final String thumbnailUrl;
  final Duration duration;
  final int playCount;
  final DateTime lastPlayed;
  final String? videoId;

  const HistoryItem({
    required this.title,
    required this.artist,
    this.thumbnailUrl = '',
    this.duration = Duration.zero,
    this.playCount = 1,
    required this.lastPlayed,
    this.videoId,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'durationMs': duration.inMilliseconds,
        'playCount': playCount,
        'lastPlayed': lastPlayed.toIso8601String(),
        'videoId': videoId,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      playCount: json['playCount'] as int? ?? 1,
      lastPlayed: json['lastPlayed'] != null
          ? DateTime.tryParse(json['lastPlayed'] as String) ?? DateTime.now()
          : DateTime.now(),
      videoId: json['videoId'] as String?,
    );
  }

  HistoryItem copyWith({
    String? title,
    String? artist,
    String? thumbnailUrl,
    Duration? duration,
    int? playCount,
    DateTime? lastPlayed,
    String? videoId,
  }) {
    return HistoryItem(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      playCount: playCount ?? this.playCount,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      videoId: videoId ?? this.videoId,
    );
  }

  LocalPlaylistTrack toLocalPlaylistTrack() {
    return LocalPlaylistTrack(
      title: title,
      artist: artist,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      youtubeVideoId: videoId,
    );
  }
}

/// Service that persists and queries track playback history for "Listen Again"
/// and personalized home feed recommendations.
class HistoryService extends ChangeNotifier {
  static const String _keyHistory = 'finaudio_playback_history';
  static final HistoryService instance = HistoryService._internal();

  factory HistoryService() => instance;

  HistoryService._internal();

  final List<HistoryItem> _items = [];
  bool _initialized = false;

  List<HistoryItem> get items => List.unmodifiable(_items);
  List<HistoryItem> get recentTracks => List.unmodifiable(_items);

  /// Initializes the service from SharedPreferences.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_keyHistory);
      if (rawJson != null && rawJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(rawJson) as List<dynamic>;
        _items.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _items.add(HistoryItem.fromJson(item));
          }
        }
      }
    } catch (_) {}
    _initialized = true;
    notifyListeners();
  }

  /// Records a played track, incrementing play count and updating recency.
  Future<void> recordTrack(Track track) async {
    if (track.title.isEmpty) return;
    await init();

    final cleanTitle = track.title.trim().toLowerCase();
    final cleanArtist = track.author.trim().toLowerCase();
    final thumb = track.thumbnailUrl ?? '';
    final vidId = track.id.isNotEmpty ? track.id : null;

    final existingIndex = _items.indexWhere((i) {
      final matchTitle = i.title.trim().toLowerCase() == cleanTitle;
      final matchArtist = cleanArtist.isEmpty ||
          i.artist.trim().toLowerCase() == cleanArtist ||
          i.artist.toLowerCase().contains(cleanArtist) ||
          cleanArtist.contains(i.artist.toLowerCase());
      return matchTitle && matchArtist;
    });

    if (existingIndex != -1) {
      final existing = _items[existingIndex];
      _items.removeAt(existingIndex);
      _items.insert(
        0,
        existing.copyWith(
          playCount: existing.playCount + 1,
          lastPlayed: DateTime.now(),
          thumbnailUrl: thumb.isNotEmpty ? thumb : existing.thumbnailUrl,
          duration: track.duration != Duration.zero
              ? track.duration
              : existing.duration,
          videoId: vidId ?? existing.videoId,
        ),
      );
    } else {
      _items.insert(
        0,
        HistoryItem(
          title: track.title,
          artist: track.author,
          thumbnailUrl: thumb,
          duration: track.duration,
          playCount: 1,
          lastPlayed: DateTime.now(),
          videoId: vidId,
        ),
      );
    }

    // Keep up to 60 history items
    if (_items.length > 60) {
      _items.removeRange(60, _items.length);
    }

    notifyListeners();
    await _save();
  }

  /// Returns tracks ordered by replay frequency and recency.
  List<HistoryItem> getRepeatTracks({int limit = 10}) {
    if (_items.isEmpty) return [];
    final sorted = List<HistoryItem>.from(_items)
      ..sort((a, b) {
        final countCmp = b.playCount.compareTo(a.playCount);
        if (countCmp != 0) return countCmp;
        return b.lastPlayed.compareTo(a.lastPlayed);
      });
    return sorted.take(limit).toList();
  }

  /// Removes a single track from recorded playback history.
  Future<void> removeTrack(String title, String artist) async {
    _items.removeWhere(
      (i) =>
          i.title.trim().toLowerCase() == title.trim().toLowerCase() &&
          i.artist.trim().toLowerCase() == artist.trim().toLowerCase(),
    );
    notifyListeners();
    await _save();
  }

  /// Clears all recorded playback history.
  Future<void> clearHistory() async {
    _items.clear();
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_items.map((i) => i.toJson()).toList());
      await prefs.setString(_keyHistory, raw);
    } catch (_) {}
  }
}
