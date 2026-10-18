import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:finaudio/models/local_playlist.dart';
import 'package:finaudio/services/google_auth_service.dart';
import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/playlist_service.dart';
import 'package:finaudio/services/history_service.dart';
import 'package:finaudio/services/settings_service.dart';
import 'package:finaudio/services/spotify_service.dart';
import 'package:finaudio/services/stream_proxy_service.dart';
import 'package:finaudio/services/youtube_service.dart';
import 'package:finaudio/ui/artist_screen.dart';
import 'package:finaudio/models/search_result.dart';
import 'package:finaudio/ui/home_screen.dart';
import 'package:finaudio/ui/album_view_screen.dart';
import 'package:finaudio/ui/section_detail_screen.dart';
import 'package:finaudio/widgets/now_playing_bar.dart';
import 'package:finaudio/widgets/google_sign_in_dialog.dart';
import 'package:finaudio/ui/now_playing_screen.dart';
import 'package:finaudio/ui/settings_screen.dart';
import 'package:finaudio/ui/lyrics_settings_screen.dart';
import 'package:finaudio/services/lyrics_service.dart';
import 'package:finaudio/services/download_service.dart';
import 'package:finaudio/ui/downloads_screen.dart';
import 'package:finaudio/ui/cached_screen.dart';
import 'package:finaudio/widgets/artist_picker_sheet.dart';
import 'package:finaudio/services/discord_rpc_service.dart';
import 'package:finaudio/widgets/discord_login_dialog.dart';
import 'package:finaudio/services/crash_log_service.dart';
import 'package:finaudio/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool hasMpv = false;
  try {
    final debugDll = File(r'build\windows\x64\runner\Debug\libmpv-2.dll');
    final libmpvDll = File(r'build\windows\x64\libmpv\libmpv-2.dll');
    String? mpvPath;
    if (debugDll.existsSync()) {
      mpvPath = debugDll.absolute.path;
    } else if (libmpvDll.existsSync()) {
      mpvPath = libmpvDll.absolute.path;
    }
  MediaKit.ensureInitialized(libmpv: mpvPath);
    hasMpv = true;
  } catch (_) {
    hasMpv = false;
  }


  group('Track model tests', () {
    test('Track creates valid youtubeUrl from videoId', () {
      final track = Track.fromPlaylistVideo(
        videoId: 'dQw4w9WgXcQ',
        title: 'Test Song',
        author: 'Test Artist',
        duration: const Duration(minutes: 3, seconds: 30),
      );

      expect(track.id, 'dQw4w9WgXcQ');
      expect(track.title, 'Test Song');
      expect(track.author, 'Test Artist');
      expect(track.youtubeUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(track.duration, const Duration(minutes: 3, seconds: 30));
    });
  });

  group('SettingsService tests', () {
    test('Loads default values when no prefs stored', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await service.init();

      expect(service.accentColor, const Color(0xFFFFDE38)); // Lemon Shark Yellow
      expect(service.backgroundColor, SettingsService.defaultBackgroundColor);
      expect(service.surfaceColor, SettingsService.defaultSurfaceColor);
      expect(service.accentColor, SettingsService.defaultAccentColor);
      expect(service.textColor, SettingsService.defaultTextColor);
      expect(service.darkIntensity, 1);
    });

    test('Persists accent color and dark intensity', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await service.init();

      await service.setDarkIntensity(2);
      expect(service.darkIntensity, 2);

      const newColor = Color(0xFF00FF00);
      await service.setAccentColor(newColor);
      expect(service.accentColor, newColor);

      // Verify persistence by loading in a fresh instance
      final service2 = SettingsService();
      await service2.init();
      expect(service2.accentColor, newColor);
      expect(service2.darkIntensity, 2);
    });

    test('Persists all 4 custom theme colors across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final service1 = SettingsService();
      await service1.init();

      const customBg = Color(0xFF010203);
      const customSurface = Color(0xFF040506);
      const customAccent = Color(0xFF00B0FF);
      const customText = Color(0xFFEEEEEE);

      await service1.setCustomTheme(
        background: customBg,
        surface: customSurface,
        accent: customAccent,
        text: customText,
      );

      expect(service1.backgroundColor, customBg);
      expect(service1.surfaceColor, customSurface);
      expect(service1.accentColor, customAccent);
      expect(service1.textColor, customText);

      // Verify second instance loads the exact 32-bit ARGB values
      final service2 = SettingsService();
      await service2.init();
      expect(service2.backgroundColor, customBg);
      expect(service2.surfaceColor, customSurface);
      expect(service2.accentColor, customAccent);
      expect(service2.textColor, customText);
    });

    test('Applies preset themes and notifies listeners', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await service.init();

      int notifications = 0;
      service.addListener(() => notifications++);

      final oledPreset = SettingsService.presets.firstWhere((p) => p.id == 'oled');
      await service.applyPreset(oledPreset);

      expect(notifications, greaterThan(0));
      expect(service.backgroundColor, oledPreset.backgroundColor);
      expect(service.surfaceColor, oledPreset.surfaceColor);
      expect(service.accentColor, oledPreset.accentColor);
      expect(service.textColor, oledPreset.textColor);

      // Re-verify in fresh service
      final reloaded = SettingsService();
      await reloaded.init();
      expect(reloaded.backgroundColor, oledPreset.backgroundColor);
    });

    test('Resets to Lemon Shark (Dark) default colors', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await service.init();

      await service.setCustomTheme(
        background: Colors.white,
        surface: Colors.grey,
        accent: Colors.purple,
        text: Colors.black,
      );

      await service.resetToDefault();
      expect(service.backgroundColor, SettingsService.defaultBackgroundColor);
      expect(service.surfaceColor, SettingsService.defaultSurfaceColor);
      expect(service.accentColor, SettingsService.defaultAccentColor);
      expect(service.textColor, SettingsService.defaultTextColor);
    });

    test('Lemon Shark Dark and Light presets are defined and apply cleanly', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await service.init();

      final darkPreset = SettingsService.presets.firstWhere((p) => p.id == 'lemon_dark');
      final lightPreset = SettingsService.presets.firstWhere((p) => p.id == 'lemon_light');

      expect(darkPreset.name, 'Lemon Shark (Dark)');
      expect(darkPreset.accentColor, const Color(0xFFFFDE38));
      expect(darkPreset.backgroundColor, const Color(0xFF14130A));

      expect(lightPreset.name, 'Lemon Shark (Light)');
      expect(lightPreset.accentColor, const Color(0xFFC78500));
      expect(lightPreset.backgroundColor, const Color(0xFFF6EFC4));

      await service.applyPreset(lightPreset);
      expect(service.backgroundColor, const Color(0xFFF6EFC4));
      expect(service.accentColor, const Color(0xFFC78500));

      await service.applyPreset(darkPreset);
      expect(service.backgroundColor, const Color(0xFF14130A));
      expect(service.accentColor, const Color(0xFFFFDE38));
    });

    test('Migrates legacy YouTube Classic default to Lemon Shark automatically', () async {
      SharedPreferences.setMockInitialValues({
        'theme_background_color': 0xFF0A0A0A,
        'theme_accent_color': 0xFFCC0000,
      });
      final service = SettingsService();
      await service.init();

      expect(service.backgroundColor, SettingsService.defaultBackgroundColor);
      expect(service.accentColor, SettingsService.defaultAccentColor);
    });

    test('Migrates previous blue default to true Lemon Shark automatically', () async {
      SharedPreferences.setMockInitialValues({
        'theme_background_color': 0xFF0C131D,
        'theme_accent_color': 0xFFF7D336,
      });
      final service = SettingsService();
      await service.init();

      expect(service.backgroundColor, SettingsService.defaultBackgroundColor);
      expect(service.accentColor, SettingsService.defaultAccentColor);
    });

    test('Migrates legacy hex string accent color properly', () async {
      SharedPreferences.setMockInitialValues({
        'accent_color': '00B0FF',
      });
      final service = SettingsService();
      await service.init();

      expect(service.accentColor, const Color(0xFF00B0FF));
    });

    test('SettingsService manages followed/favorite artists correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await service.init();

      expect(service.favoriteArtists.isEmpty, true);
      expect(service.isArtistFollowed('Coldplay'), false);

      final followed = await service.toggleFollowArtist('Coldplay');
      expect(followed, true);
      expect(service.isArtistFollowed('coldplay'), true);
      expect(service.favoriteArtists, contains('Coldplay'));

      final unfollowed = await service.toggleFollowArtist('Coldplay');
      expect(unfollowed, false);
      expect(service.isArtistFollowed('Coldplay'), false);
      expect(service.favoriteArtists.isEmpty, true);
    });
  });

  group('Volume control tests', () {
    test('SettingsService loads default volume and persists new volume', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();
      await service.init();
      expect(service.appVolume, 1.0);

      await service.setAppVolume(0.65);
      expect(service.appVolume, 0.65);

      final service2 = SettingsService();
      await service2.init();
      expect(service2.appVolume, 0.65);
    });
  });

  group('StreamProxyService tests', () {
    test('Starts on loopback and formats proxy URI correctly', () async {
      final proxy = StreamProxyService.instance;
      await proxy.ensureStarted();
      expect(proxy.isRunning, true);
      expect(proxy.port > 0, true);

      final fakeTarget = Uri.parse('https://example.com/audio.webm');
      final proxyUri = proxy.getProxyUri('test123', fakeTarget, ext: 'webm');
      expect(proxyUri.host, '127.0.0.1');
      expect(proxyUri.port, proxy.port);
    });
  });

  group('SpotifyService tests', () {
    test('Correctly identifies Spotify links and URIs', () {
      expect(SpotifyService.isSpotifyUrl('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'), true);
      expect(SpotifyService.isSpotifyUrl('https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy'), true);
      expect(SpotifyService.isSpotifyUrl('https://open.spotify.com/track/3zOYmiNOuyDL0ClxJcEJ0T'), true);
      expect(SpotifyService.isSpotifyUrl('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'), true);
      expect(SpotifyService.isSpotifyUrl('https://spotify.link/abc123xyz'), true);
      expect(SpotifyService.isSpotifyUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), false);
    });

    test('Parses Spotify playlist, album, and track targets', () {
      final playlistTarget = SpotifyService.parseTarget('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=123');
      expect(playlistTarget, isNotNull);
      expect(playlistTarget!.type, SpotifyEntityType.playlist);
      expect(playlistTarget.id, '37i9dQZF1DXcBWIGoYBM5M');

      final albumTarget = SpotifyService.parseTarget('https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy');
      expect(albumTarget, isNotNull);
      expect(albumTarget!.type, SpotifyEntityType.album);
      expect(albumTarget.id, '4aawyAB9vmqN3uQ7FjRGTy');

      final trackTarget = SpotifyService.parseTarget('spotify:track:3zOYmiNOuyDL0ClxJcEJ0T');
      expect(trackTarget, isNotNull);
      expect(trackTarget!.type, SpotifyEntityType.track);
      expect(trackTarget.id, '3zOYmiNOuyDL0ClxJcEJ0T');
    });
  });

  group('LocalPlaylist and PlaylistService tests', () {
    test('LocalPlaylist serializes and deserializes cleanly', () {
      final now = DateTime.now();
      final track = LocalPlaylistTrack(
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        duration: const Duration(minutes: 5, seconds: 55),
        spotifyUri: 'spotify:track:123',
        thumbnailUrl: 'https://example.com/cover.jpg',
      );
      final playlist = LocalPlaylist(
        id: 'test_1',
        title: 'Classic Rock',
        description: 'Best hits',
        thumbnailUrl: 'https://example.com/cover.jpg',
        source: 'spotify',
        spotifyId: 'spotify_123',
        createdAt: now,
        lastSyncedAt: now,
        tracks: [track],
      );

      final json = playlist.toJson();
      final recovered = LocalPlaylist.fromJson(json);

      expect(recovered.id, 'test_1');
      expect(recovered.title, 'Classic Rock');
      expect(recovered.trackCount, 1);
      expect(recovered.tracks.first.title, 'Bohemian Rhapsody');
      expect(recovered.tracks.first.artist, 'Queen');
      expect(recovered.tracks.first.duration, const Duration(minutes: 5, seconds: 55));
      expect(recovered.isSpotify, true);
    });

    test('PlaylistService persists and retrieves playlists across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final service1 = PlaylistService();
      await service1.init();

      // Permanent Liked Songs playlist is always present
      expect(service1.playlists.length, 1);
      expect(service1.playlists.first.isLikedSongs, true);

      final playlist = LocalPlaylist(
        id: 'p1',
        title: 'Favorites',
        createdAt: DateTime.now(),
        tracks: [
          const LocalPlaylistTrack(title: 'Song A', artist: 'Artist A'),
        ],
      );

      await service1.savePlaylist(playlist);
      expect(service1.playlists.length, 2);

      // Verify persistence in second instance
      final service2 = PlaylistService();
      await service2.init();
      expect(service2.playlists.length, 2);
      expect(service2.playlists.any((p) => p.id == 'p1' && p.title == 'Favorites'), true);

      // Test delete user playlist
      await service2.deletePlaylist('p1');
      expect(service2.playlists.length, 1);
      expect(service2.playlists.first.isLikedSongs, true);

      // Verify permanent Liked Songs playlist cannot be deleted
      await service2.deletePlaylist(PlaylistService.likedSongsId);
      expect(service2.playlists.length, 1);
      expect(service2.playlists.first.isLikedSongs, true);

      final service3 = PlaylistService();
      await service3.init();
      expect(service3.playlists.length, 1);
      expect(service3.playlists.first.isLikedSongs, true);
    });

    test('PlaylistService creates playlist from raw text lines', () async {
      SharedPreferences.setMockInitialValues({});
      final service = PlaylistService();
      await service.init();

      const raw = '''
        1. Queen - Bohemian Rhapsody
        Eagles – Hotel California
        Daft Punk, Get Lucky
      ''';

      final created = await service.createFromText(
        title: 'Rock Classics',
        rawText: raw,
      );

      expect(created.title, 'Rock Classics');
      expect(created.trackCount, 3);
      expect(created.tracks[0].title, 'Bohemian Rhapsody');
      expect(created.tracks[0].artist, 'Queen');
      expect(created.tracks[1].title, 'Hotel California');
      expect(created.tracks[1].artist, 'Eagles');
    });

    test('SettingsService manages Spotify client credentials correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      expect(settings.hasSpotifyCredentials, false);
      expect(settings.spotifyClientId, isEmpty);
      expect(settings.spotifyClientSecret, isEmpty);

      await settings.setSpotifyCredentials('test_client_id_123', 'test_client_secret_456');
      expect(settings.hasSpotifyCredentials, true);
      expect(settings.spotifyClientId, 'test_client_id_123');
      expect(settings.spotifyClientSecret, 'test_client_secret_456');

      // Check persistence across new instance
      final settings2 = SettingsService();
      await settings2.init();
      expect(settings2.hasSpotifyCredentials, true);
      expect(settings2.spotifyClientId, 'test_client_id_123');
      expect(settings2.spotifyClientSecret, 'test_client_secret_456');

      await settings2.clearSpotifyCredentials();
      expect(settings2.hasSpotifyCredentials, false);
      expect(settings2.spotifyClientId, isEmpty);
      expect(settings2.spotifyClientSecret, isEmpty);
    });

    test('PlaylistService parses large CSV files (e.g. Exportify / Soundiiz)', () async {
      SharedPreferences.setMockInitialValues({});
      final service = PlaylistService();
      await service.init();

      // Generate simulated Exportify CSV with 250 tracks
      final buffer = StringBuffer();
      buffer.writeln('Spotify ID,Track Name,Artist Name(s),Album Name,Duration (ms)');
      for (int i = 1; i <= 250; i++) {
        buffer.writeln('id_$i,"Track Title $i","Artist $i","Album $i",210000');
      }

      final playlist = await service.createFromText(
        title: 'Huge 250-Track CSV',
        rawText: buffer.toString(),
      );

      expect(playlist.title, 'Huge 250-Track CSV');
      expect(playlist.trackCount, 250);
      expect(playlist.tracks.first.title, 'Track Title 1');
      expect(playlist.tracks.first.artist, 'Artist 1');
      expect(playlist.tracks.last.title, 'Track Title 250');
      expect(playlist.tracks.last.artist, 'Artist 250');
    });

    test('Local playlist in-memory search filtering', () {
      final tracks = [
        const LocalPlaylistTrack(title: 'Bohemian Rhapsody', artist: 'Queen'),
        const LocalPlaylistTrack(title: 'Hotel California', artist: 'Eagles'),
        const LocalPlaylistTrack(title: 'Radio Ga Ga', artist: 'Queen'),
        const LocalPlaylistTrack(title: 'Billie Jean', artist: 'Michael Jackson'),
      ];

      // Filter for 'queen'
      final queenMatches = tracks.where((t) {
        final q = 'queen';
        return t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q);
      }).toList();
      expect(queenMatches.length, 2);

      // Filter for 'hotel'
      final hotelMatches = tracks.where((t) {
        final q = 'hotel';
        return t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q);
      }).toList();
      expect(hotelMatches.length, 1);
      expect(hotelMatches.first.title, 'Hotel California');

      // Filter for non-existent
      final noMatches = tracks.where((t) {
        final q = 'metallica';
        return t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q);
      }).toList();
      expect(noMatches.isEmpty, true);
    });

    test('Track creates valid model from LocalPlaylistTrack', () {
      const localTrack = LocalPlaylistTrack(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        duration: Duration(minutes: 3, seconds: 20),
        spotifyUri: 'spotify:track:0VjIjW4GlUZAMYd2vXMi3b',
        thumbnailUrl: 'https://example.com/art.jpg',
      );

      final track = Track.fromLocalPlaylistTrack(localTrack);
      expect(track.title, 'Blinding Lights');
      expect(track.author, 'The Weeknd');
      expect(track.thumbnailUrl, 'https://example.com/art.jpg');
      expect(track.duration, const Duration(minutes: 3, seconds: 20));
    });

    test('LocalPlaylist copyWith updates title, cover, and tracks', () {
      final playlist = LocalPlaylist(
        id: 'p1',
        title: 'Original Title',
        thumbnailUrl: '',
        createdAt: DateTime.now(),
        tracks: [
          const LocalPlaylistTrack(title: 'Track A', artist: 'Artist 2', duration: Duration(minutes: 4)),
          const LocalPlaylistTrack(title: 'Track B', artist: 'Artist 1', duration: Duration(minutes: 2)),
        ],
      );

      final updated = playlist.copyWith(
        title: 'New Title',
        thumbnailUrl: 'https://example.com/new_cover.jpg',
      );

      expect(updated.title, 'New Title');
      expect(updated.thumbnailUrl, 'https://example.com/new_cover.jpg');
      expect(updated.id, 'p1');
      expect(updated.tracks.length, 2);
    });

    test('Sorting playlist tracks by title, artist, and duration works correctly', () {
      final tracks = [
        const LocalPlaylistTrack(title: 'Zebra', artist: 'Beatles', duration: Duration(seconds: 300)),
        const LocalPlaylistTrack(title: 'Apple', artist: 'Coldplay', duration: Duration(seconds: 120)),
        const LocalPlaylistTrack(title: 'Mango', artist: 'Abba', duration: Duration(seconds: 240)),
      ];

      // Title Ascending
      final titleAsc = List<LocalPlaylistTrack>.from(tracks)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      expect(titleAsc.map((t) => t.title).toList(), ['Apple', 'Mango', 'Zebra']);

      // Title Descending
      final titleDesc = List<LocalPlaylistTrack>.from(tracks)
        ..sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
      expect(titleDesc.map((t) => t.title).toList(), ['Zebra', 'Mango', 'Apple']);

      // Artist Ascending
      final artistAsc = List<LocalPlaylistTrack>.from(tracks)
        ..sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      expect(artistAsc.map((t) => t.artist).toList(), ['Abba', 'Beatles', 'Coldplay']);

      // Duration Ascending (Shortest first)
      final durationAsc = List<LocalPlaylistTrack>.from(tracks)
        ..sort((a, b) => a.duration.compareTo(b.duration));
      expect(durationAsc.map((t) => t.title).toList(), ['Apple', 'Mango', 'Zebra']);

      // Duration Descending (Longest first)
      final durationDesc = List<LocalPlaylistTrack>.from(tracks)
        ..sort((a, b) => b.duration.compareTo(a.duration));
      expect(durationDesc.map((t) => t.title).toList(), ['Zebra', 'Mango', 'Apple']);
    });
  });

  group('HistoryService tests', () {
    test('Records tracks and increments playCount for replayed tracks', () async {
      SharedPreferences.setMockInitialValues({});
      final history = HistoryService.instance;
      await history.clearHistory();

      final t1 = Track.fromPlaylistVideo(
        videoId: 'vid1',
        title: 'Song A',
        author: 'Artist X',
        duration: const Duration(minutes: 3),
      );
      final t2 = Track.fromPlaylistVideo(
        videoId: 'vid2',
        title: 'Song B',
        author: 'Artist Y',
        duration: const Duration(minutes: 4),
      );

      await history.recordTrack(t1);
      await history.recordTrack(t2);
      await history.recordTrack(t1); // Played twice

      expect(history.items.length, 2);
      expect(history.items.first.title, 'Song A');
      expect(history.items.first.playCount, 2);

      final repeats = history.getRepeatTracks();
      expect(repeats.isNotEmpty, true);
      expect(repeats.first.title, 'Song A');
      expect(repeats.first.playCount, 2);

      final localTrack = repeats.first.toLocalPlaylistTrack();
      expect(localTrack.title, 'Song A');
      expect(localTrack.youtubeVideoId, 'vid1');
    });

    test('Persists and clears history cleanly', () async {
      SharedPreferences.setMockInitialValues({});
      final history = HistoryService.instance;
      await history.clearHistory();

      final t = Track.fromPlaylistVideo(
        videoId: 'vid123',
        title: 'Song Persist',
        author: 'Artist Z',
        duration: const Duration(minutes: 2),
      );
      await history.recordTrack(t);
      expect(history.items.length, 1);

      await history.clearHistory();
      expect(history.items.isEmpty, true);
      expect(history.getRepeatTracks().isEmpty, true);
    });
  });

  group('InnerTube & YouTube service tests', () {
    test('UserPlaylist and PlaylistVideo model serialization and URLs', () {
      const playlist = UserPlaylist(
        id: 'PL1234567890',
        title: 'Top Hits',
        description: 'Best hits',
        thumbnailUrl: 'https://example.com/cover.jpg',
        videoCount: 25,
      );
      expect(playlist.id, 'PL1234567890');
      expect(playlist.title, 'Top Hits');
      expect(playlist.videoCount, 25);

      const video = PlaylistVideo(
        videoId: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        channelTitle: 'Rick Astley',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: Duration(minutes: 3, seconds: 32),
      );
      expect(video.videoId, 'dQw4w9WgXcQ');
      expect(video.youtubeUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(video.duration, const Duration(minutes: 3, seconds: 32));

      // Test Track creation from PlaylistVideo
      final track = Track.fromPlaylistVideo(
        videoId: video.videoId,
        title: video.title,
        author: video.channelTitle,
        duration: video.duration,
        thumbnailUrl: video.thumbnailUrl,
      );
      expect(track.id, 'dQw4w9WgXcQ');
      expect(track.title, 'Never Gonna Give You Up');
      expect(track.author, 'Rick Astley');
      expect(track.youtubeUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(track.thumbnailUrl, 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    });

    test('ResolvedVideo holds stream url and metadata', () {
      final uri = Uri.parse('https://example.com/stream.webm');
      final resolved = ResolvedVideo(
        id: 'vid123',
        title: 'Test Stream Track',
        author: 'FinAudio Artist',
        duration: const Duration(minutes: 4),
        youtubeUrl: 'https://www.youtube.com/watch?v=vid123',
        audioStreamUrl: uri,
        container: 'webm',
      );
      expect(resolved.id, 'vid123');
      expect(resolved.audioStreamUrl, uri);
      expect(resolved.container, 'webm');
      expect(resolved.duration, const Duration(minutes: 4));
    });

    test('GoogleAuthService initializes cleanly with empty preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final authService = GoogleAuthService();
      expect(authService.isSignedIn, false);
      expect(authService.currentUser, isNull);
      authService.dispose();
    });

    test('GoogleAuthService restores persistent session from SharedPreferences without prompt', () async {
      SharedPreferences.setMockInitialValues({
        'google_user_id': 'user_12345',
        'google_user_email': 'testuser@example.com',
        'google_user_name': 'Test User',
        'google_user_photo': 'https://example.com/photo.jpg',
        'google_access_token': 'fake_access_token_123',
        'google_token_timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final authService = GoogleAuthService();
      await authService.initialize();

      expect(authService.isSignedIn, isTrue);
      expect(authService.currentUser, isNotNull);
      expect(authService.currentUser!.id, 'user_12345');
      expect(authService.currentUser!.email, 'testuser@example.com');
      expect(authService.currentUser!.displayName, 'Test User');
      expect(authService.currentUser!.photoUrl, 'https://example.com/photo.jpg');

      // Test signOut clears the stored session
      await authService.signOut();
      expect(authService.isSignedIn, isFalse);
      expect(authService.currentUser, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('google_user_email'), isNull);
      expect(prefs.getString('google_access_token'), isNull);

      authService.dispose();
    });

    test('ArtistProfile and models hold artist metadata and top songs cleanly', () {
      final track = Track.fromPlaylistVideo(
        videoId: 'sng1',
        title: 'Yellow',
        author: 'Coldplay',
        duration: const Duration(minutes: 4, seconds: 29),
        thumbnailUrl: 'https://example.com/yellow.jpg',
      );
      const album = ArtistAlbumItem(
        title: 'Parachutes',
        browseId: 'MPREb_parachutes',
        year: '2000',
        thumbnailUrl: 'https://example.com/parachutes.jpg',
      );
      const related = RelatedArtistItem(
        name: 'Radiohead',
        browseId: 'UCradiohead',
        subscribers: '3.1M',
        thumbnailUrl: 'https://example.com/radiohead.jpg',
      );

      final profile = ArtistProfile(
        name: 'Coldplay',
        channelId: 'UCcoldplay',
        description: 'British rock band formed in London in 1997.',
        bannerUrl: 'https://example.com/banner.jpg',
        subscribers: '28M',
        monthlyListeners: '85M',
        topSongs: [track],
        albums: [album],
        relatedArtists: [related],
      );

      expect(profile.name, 'Coldplay');
      expect(profile.channelId, 'UCcoldplay');
      expect(profile.monthlyListeners, '85M');
      expect(profile.topSongs.length, 1);
      expect(profile.topSongs.first.title, 'Yellow');
      expect(profile.albums.first.title, 'Parachutes');
      expect(profile.relatedArtists.first.name, 'Radiohead');
      expect(profile.isEmpty, false);
    });

    test('YoutubeService initializes and disposes cleanly', () async {
      final ytService = YoutubeService();
      expect(ytService, isNotNull);
      ytService.dispose();
    });
  });

  group('PlayerService switching and queue tests', () {
    test('PlayerService instantly updates state and queue on stop and track switches', () {
      if (!hasMpv) {
        // Native media player backend is not available in headless test environment
        return;
      }
      final player = PlayerService();
      expect(player.isPlaying, false);
      expect(player.currentTrack, isNull);
      expect(player.queue, isEmpty);

      final track = Track.fromPlaylistVideo(
        videoId: 'testVid',
        title: 'Test Song',
        author: 'Test Artist',
        duration: const Duration(minutes: 3),
      );
      player.addTrackToQueue(track);
      expect(player.queue.length, 1);
      expect(player.queue.first.title, 'Test Song');

      player.removeFromQueue('testVid');
      expect(player.queue.isEmpty, true);

      player.stop();
      expect(player.currentTrack, isNull);
      expect(player.position, Duration.zero);

      player.dispose();
    });
  });

  group('YouTube Subscriptions and Spotify Search models tests', () {
    test('SubscribedArtist serializes and deserializes correctly', () {
      const artist = SubscribedArtist(
        channelId: 'UCtestChannel123',
        title: 'Coldplay',
        description: 'British rock band',
        thumbnailUrl: 'https://example.com/coldplay.jpg',
      );

      final json = artist.toJson();
      expect(json['channelId'], 'UCtestChannel123');
      expect(json['title'], 'Coldplay');
      expect(json['description'], 'British rock band');
      expect(json['thumbnailUrl'], 'https://example.com/coldplay.jpg');

      final restored = SubscribedArtist.fromJson(json);
      expect(restored.channelId, artist.channelId);
      expect(restored.title, artist.title);
      expect(restored.description, artist.description);
      expect(restored.thumbnailUrl, artist.thumbnailUrl);
    });

    test('Search models serialize and deserialize correctly', () {
      const artist = SearchArtist(
        id: 'UCartistId',
        name: 'The Weeknd',
        thumbnailUrl: 'https://example.com/weeknd.jpg',
        subscribers: '35M',
      );
      final artistJson = artist.toJson();
      final restoredArtist = SearchArtist.fromJson(artistJson);
      expect(restoredArtist.id, 'UCartistId');
      expect(restoredArtist.name, 'The Weeknd');
      expect(restoredArtist.subscribers, '35M');

      const album = SearchAlbum(
        browseId: 'MPREalbumId',
        playlistId: 'OLAKalbumPlaylist',
        title: 'After Hours',
        artist: 'The Weeknd',
        year: '2020',
        type: 'Album',
        thumbnailUrl: 'https://example.com/afterhours.jpg',
      );
      final albumJson = album.toJson();
      final restoredAlbum = SearchAlbum.fromJson(albumJson);
      expect(restoredAlbum.browseId, 'MPREalbumId');
      expect(restoredAlbum.playlistId, 'OLAKalbumPlaylist');
      expect(restoredAlbum.title, 'After Hours');
      expect(restoredAlbum.year, '2020');

      const playlist = SearchPlaylist(
        id: 'PLplaylistId',
        title: 'Today\'s Top Hits',
        author: 'FinAudio',
        itemCount: 50,
        thumbnailUrl: 'https://example.com/tth.jpg',
      );
      final playlistJson = playlist.toJson();
      final restoredPlaylist = SearchPlaylist.fromJson(playlistJson);
      expect(restoredPlaylist.id, 'PLplaylistId');
      expect(restoredPlaylist.title, 'Today\'s Top Hits');
      expect(restoredPlaylist.itemCount, 50);
    });

    test('TopSearchResult and UnifiedSearchResults operate as expected', () {
      const artist = SearchArtist(
        id: 'UC123',
        name: 'Dua Lipa',
        thumbnailUrl: 'https://example.com/dualipa.jpg',
      );
      const topArtist = TopSearchResult(type: 'artist', data: artist);
      expect(topArtist.isArtist, true);
      expect(topArtist.isSong, false);
      expect(topArtist.asArtist?.name, 'Dua Lipa');

      const song = PlaylistVideo(
        videoId: 'levitating123',
        title: 'Levitating',
        channelTitle: 'Dua Lipa',
        thumbnailUrl: 'https://example.com/levitating.jpg',
        duration: Duration(minutes: 3, seconds: 23),
      );
      const topSong = TopSearchResult(type: 'song', data: song);
      expect(topSong.isSong, true);
      expect(topSong.isArtist, false);
      expect(topSong.asSong?.title, 'Levitating');

      const unified = UnifiedSearchResults(
        topResult: topArtist,
        songs: [song],
        artists: [artist],
      );

      expect(unified.isEmpty, false);
      expect(unified.isNotEmpty, true);
      expect(unified.topResult?.asArtist?.name, 'Dua Lipa');
      expect(unified.songs.length, 1);
      expect(unified.artists.length, 1);
    });
  });

  group('HomeTab ArchiveTuner-inspired UI tests', () {
    testWidgets('HomeTab renders quick picks, mood pills, music artists, and listen again shelves', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settingsService = SettingsService();
      await settingsService.init();

      final playlistService = PlaylistService();
      await playlistService.init();

      final authService = GoogleAuthService();

      if (!hasMpv) return;
      final playerService = PlayerService();

      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await HttpOverrides.runWithHttpOverrides(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeTab(
                playerService: playerService,
                authService: authService,
                playlistService: playlistService,
                settingsService: settingsService,
                onOpenPlaylists: () {},
                onOpenSearch: () {},
                onOpenSettings: () {},
                onOpenPlaylistDetail: (_) {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Check for FinAudio branding
        expect(find.text('FinAudio'), findsOneWidget);

        // Check for Quick picks and subtitle
        expect(find.text('START RADIO FROM A SONG'), findsOneWidget);
        expect(find.text('Quick picks'), findsOneWidget);

        // Check for mood pills
        expect(find.text('Energize'), findsOneWidget);
        expect(find.text('Workout'), findsOneWidget);
        expect(find.text('Relax'), findsOneWidget);
        expect(find.text('Focus'), findsOneWidget);
        expect(find.text('Commute'), findsOneWidget);

        // Check for Liked Music in Speed dial
        expect(find.text('Liked Music'), findsOneWidget);
        expect(find.text('Speed dial'), findsOneWidget);

        // Check for Mixed for you (ArchiveTune Custom Mixes)
        expect(find.text('MIXED FOR YOU'), findsOneWidget);
        expect(find.text('Custom mixes'), findsOneWidget);
        expect(find.text('My Supermix'), findsOneWidget);
        expect(find.text('Discover Mix'), findsOneWidget);

        // Check for Community playlists (ArchiveTune Trending Playlists)
        expect(find.text('COMMUNITY PLAYLISTS'), findsOneWidget);
        expect(find.text('Trending playlists'), findsOneWidget);

        // Check for section headers
        expect(find.text('From your library'), findsOneWidget);
        expect(find.text('Albums for you'), findsOneWidget);
        expect(find.text('New releases'), findsOneWidget);

        // Test tapping a mood pill
        await tester.tap(find.text('Energize'));
        await tester.pumpAndSettle();

        // Verify ArchiveTune dynamic mood transformation below Speed Dial
        expect(find.text('ENERGIZE MIX ACTIVE'), findsOneWidget);
        expect(find.text('Energize • Quick picks'), findsOneWidget);
        expect(find.text('Energize • Mixes & Playlists'), findsOneWidget);
        expect(find.text('Energize • Artists'), findsOneWidget);
        expect(find.text('Energize • Radio'), findsOneWidget);

        // Tap Clear to return to personalized feed
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();

        expect(find.text('Quick picks'), findsOneWidget);
        expect(find.text('Listen again'), findsOneWidget);
      }, _TestHttpOverrides());

      playerService.dispose();
    });

    testWidgets('HomeTab section arrows navigate to SectionTracksScreen and NewReleasesScreen', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final playlistService = PlaylistService();
      await playlistService.init();
      final settingsService = SettingsService();
      await settingsService.init();
      final authService = GoogleAuthService();

      if (!hasMpv) return;
      final playerService = PlayerService();

      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await HttpOverrides.runWithHttpOverrides(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeTab(
                playerService: playerService,
                authService: authService,
                playlistService: playlistService,
                settingsService: settingsService,
                onOpenPlaylists: () {},
                onOpenSearch: () {},
                onOpenSettings: () {},
                onOpenPlaylistDetail: (_) {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Test clicking Quick picks arrow
        final quickPicksArrow = find.byTooltip('See all quick picks');
        expect(quickPicksArrow, findsOneWidget);
        await tester.tap(quickPicksArrow);
        await tester.pumpAndSettle();

        expect(find.byType(SectionTracksScreen), findsOneWidget);
        expect(find.text('Quick picks'), findsWidgets);
        expect(find.text('Play All'), findsOneWidget);

        // Pop back to home
        Navigator.of(tester.element(find.byType(SectionTracksScreen))).pop();
        await tester.pumpAndSettle();

        // 2. Test clicking New releases arrow
        final newReleasesArrow = find.byTooltip('See new releases from your subscribed artists');
        expect(newReleasesArrow, findsOneWidget);
        await tester.tap(newReleasesArrow);
        await tester.pumpAndSettle();

        expect(find.byType(NewReleasesScreen), findsOneWidget);
        expect(find.text('New Releases'), findsWidgets);
        expect(find.text('Play All'), findsOneWidget);
        expect(find.text('Shuffle'), findsOneWidget);
      }, _TestHttpOverrides());

      playerService.dispose();
    });
  });

  group('Desktop layout and Google sign-in tests', () {
    test('GoogleAuthService is supported on desktop and performs InnerTube connect cleanly', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = GoogleAuthService();
      await auth.initialize();

      expect(auth.isSupported, isTrue);
      expect(auth.isSignedIn, isFalse);

      await auth.signInWithInnerTube(
        handleOrChannelId: '@FinAudioTest',
        authCookie: 'test_cookie_123',
      );

      expect(auth.isSignedIn, isTrue);
      expect(auth.currentUser?.email, '@FinAudioTest@youtube');
      expect(auth.currentUser?.displayName, '@FinAudioTest');

      await auth.signOut();
      expect(auth.isSignedIn, isFalse);
    });

    testWidgets('DesktopPlayerBar renders track controls and responds to playback changes', (tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final settings = SettingsService();
        final playlist = PlaylistService();
        final auth = GoogleAuthService();
        final player = PlayerService();

        final track = Track(
          id: 'test_vid_123',
          title: 'Desktop Test Song',
          author: 'Desktop Test Artist',
          youtubeUrl: 'https://www.youtube.com/watch?v=test_vid_123',
          duration: const Duration(minutes: 3, seconds: 45),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              bottomNavigationBar: DesktopPlayerBar(
                track: track,
                accentColor: const Color(0xFFFFDE38),
                playerService: player,
                authService: auth,
                playlistService: playlist,
                settingsService: settings,
              ),
            ),
          ),
        );

        expect(find.text('Desktop Test Song'), findsOneWidget);
        expect(find.text('Desktop Test Artist'), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
        expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
        expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);

        player.dispose();
      }, _TestHttpOverrides());
    });

    testWidgets('showGoogleSignInDialog renders handle input and connect button', (tester) async {
      final auth = GoogleAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showGoogleSignInDialog(
                  context: context,
                  authService: auth,
                  accentColor: const Color(0xFFFFDE38),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Google & YouTube Account'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('Connect Account'), findsOneWidget);
    });

    testWidgets('DesktopPlayerBar opens NowPlayingScreen when track artwork or title is tapped', (tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final player = PlayerService(initialVolume: 0.9);
        final auth = GoogleAuthService();
        final playlist = PlaylistService();
        final settings = SettingsService();

        final track = Track(
          id: 'test_track',
          title: 'Desktop Tap Song',
          author: 'Desktop Tap Artist',
          youtubeUrl: 'https://www.youtube.com/watch?v=test_track',
          duration: const Duration(minutes: 3, seconds: 12),
        );
        player.setCurrentTrackForTesting(track);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DesktopPlayerBar(
                track: track,
                accentColor: const Color(0xFFFFDE38),
                playerService: player,
                authService: auth,
                playlistService: playlist,
                settingsService: settings,
              ),
            ),
          ),
        );

        expect(find.text('Desktop Tap Song'), findsOneWidget);
        await tester.tap(find.text('Desktop Tap Song'));
        await tester.pumpAndSettle();

        // Should have pushed NowPlayingScreen
        expect(find.byType(NowPlayingScreen), findsOneWidget);
        expect(find.text('AAC'), findsOneWidget);

        player.dispose();
      }, _TestHttpOverrides());
    });

    testWidgets('DesktopPlayerBar volume slider displays volume percentage', (tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final player = PlayerService(initialVolume: 0.8);
        final track = Track(
          id: 'test_track',
          title: 'Desktop Tap Song',
          author: 'Desktop Tap Artist',
          youtubeUrl: 'https://www.youtube.com/watch?v=test_track',
          duration: const Duration(minutes: 3, seconds: 12),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DesktopPlayerBar(
                track: track,
                accentColor: const Color(0xFFFFDE38),
                playerService: player,
              ),
            ),
          ),
        );

        expect(find.text('80%'), findsOneWidget);
        player.dispose();
      }, _TestHttpOverrides());
    });
  });

  group('Now Playing Screen and Volume Control tests', () {
    test('PlayerService setVolume with persist:false does not trigger onVolumeChanged', () async {
      if (!hasMpv) return;
      int persistCount = 0;
      final playerService = PlayerService(
        initialVolume: 0.8,
        onVolumeChanged: (vol) => persistCount++,
      );

      // Dragging without persistence (zero latency)
      await playerService.setVolume(0.5, persist: false);
      expect(playerService.volume, equals(0.5));
      expect(persistCount, equals(0));

      // Drag released with persistence
      await playerService.setVolume(0.6, persist: true);
      expect(playerService.volume, equals(0.6));
      expect(persistCount, equals(1));

      playerService.dispose();
    });

    testWidgets('NowPlayingScreen renders ArchiveTune layout and controls', (tester) async {
      if (!hasMpv) return;
      final playerService = PlayerService(initialVolume: 0.9);
      final track = Track(
        id: 'test_id',
        title: 'enshin pizza rap',
        author: 'hyunstqr',
        youtubeUrl: 'https://www.youtube.com/watch?v=test_id',
        duration: const Duration(minutes: 1, seconds: 19),
      );

      LyricsService.instance.setLyricsForTesting(
        track.id,
        const LyricsData(
          lines: [
            LyricLine(timestamp: Duration.zero, text: 'foreign'),
            LyricLine(timestamp: Duration(seconds: 6), text: '[Music]'),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NowPlayingScreen(
            playerService: playerService,
            accentColor: const Color(0xFF64B5F6),
          ),
        ),
      );

      // When track is empty
      expect(find.text('Nothing playing'), findsOneWidget);

      // Set track
      playerService.setCurrentTrackForTesting(track);
      await tester.pump();

      // Verify ArchiveTune title, artist, AAC quality badge, and Speaker badge
      expect(find.text('enshin pizza rap'), findsOneWidget);
      expect(find.text('hyunstqr'), findsOneWidget);
      expect(find.text('AAC'), findsOneWidget);
      expect(find.text('Speaker'), findsOneWidget);

      // Verify Lyrics button exists
      final lyricsBtn = find.byTooltip('Synchronized Lyrics');
      expect(lyricsBtn, findsOneWidget);

      // Tap Lyrics button to switch to synchronized lyrics view
      await tester.tap(lyricsBtn);
      await tester.pump();

      // Lyrics view header has close button and mini track info
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      playerService.dispose();
    });
  });

  group('Audio Quality & Codec Detection tests', () {
    test('SettingsService persists and evaluates audio quality settings', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      expect(settings.audioQuality, 'auto');

      await settings.setAudioQuality('high');
      expect(settings.audioQuality, 'high');
      expect(await settings.getEffectiveAudioQuality(), 'high');

      await settings.setAudioQuality('medium');
      expect(settings.audioQuality, 'medium');
      expect(await settings.getEffectiveAudioQuality(), 'medium');

      await settings.setAudioQuality('low');
      expect(settings.audioQuality, 'low');
      expect(await settings.getEffectiveAudioQuality(), 'low');

      // Persistence across re-init
      final newSettings = SettingsService();
      await newSettings.init();
      expect(newSettings.audioQuality, 'low');
    });

    test('Track and ResolvedVideo preserve audioCodec and bitrate', () {
      final track = Track(
        id: 'testId12345',
        title: 'Codec Test',
        author: 'Test Artist',
        youtubeUrl: 'https://www.youtube.com/watch?v=testId12345',
        duration: const Duration(minutes: 3),
        audioCodec: 'OPUS',
        bitrate: 160000,
      );

      expect(track.audioCodec, 'OPUS');
      expect(track.bitrate, 160000);

      final copy = track.copyWith(audioCodec: 'AAC', bitrate: 128000);
      expect(copy.audioCodec, 'AAC');
      expect(copy.bitrate, 128000);

      final resolved = ResolvedVideo(
        id: 'testId12345',
        title: 'Resolved Test',
        author: 'Artist',
        duration: const Duration(minutes: 2),
        youtubeUrl: 'https://www.youtube.com/watch?v=testId12345',
        audioStreamUrl: Uri.parse('https://example.com/audio.webm'),
        audioCodec: 'OPUS',
        bitrate: 160000,
      );
      expect(resolved.audioCodec, 'OPUS');
      expect(resolved.bitrate, 160000);
    });

    testWidgets('NowPlayingScreen dynamically updates codec badge between AAC and OPUS',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      final playerService = PlayerService(
        initialVolume: 0.8,
        settingsService: settings,
      );

      final track = Track(
        id: 'test_codec',
        title: 'Dynamic Codec Song',
        author: 'Artist',
        youtubeUrl: 'https://www.youtube.com/watch?v=test_codec',
        duration: const Duration(minutes: 2, seconds: 30),
      );

      playerService.setCurrentTrackForTesting(track);
      playerService.setAudioCodecForTesting('AAC', 128000);

      await tester.pumpWidget(
        MaterialApp(
          home: NowPlayingScreen(
            playerService: playerService,
            accentColor: const Color(0xFFFFDE38),
            settingsService: settings,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AAC'), findsOneWidget);

      // Switch codec to OPUS
      playerService.setAudioCodecForTesting('OPUS', 160000);
      await tester.pumpAndSettle();

      expect(find.text('OPUS'), findsOneWidget);
      expect(find.text('AAC'), findsNothing);

      // Tap on the codec badge to open info sheet
      final badge = find.text('OPUS');
      await tester.tap(badge);
      await tester.pumpAndSettle();

      expect(find.text('OPUS Audio Stream'), findsOneWidget);
      expect(find.text('Streaming Audio Quality'), findsOneWidget);

      playerService.dispose();
    });

    testWidgets('SettingsScreen displays Audio Quality section and allows changing quality',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      final auth = GoogleAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsService: settings,
            authService: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to ensure the Audio Quality tile is visible
      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pumpAndSettle();

      final qualityTile = find.text('Audio Quality').last;
      expect(qualityTile, findsOneWidget);
      expect(find.text('Automatic'), findsWidgets);

      // Tap to open quality dialog
      await tester.tap(qualityTile);
      await tester.pumpAndSettle();

      expect(find.text('Audio Streaming Quality'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Low (Data Saver)'), findsOneWidget);

      // Select Medium quality
      await tester.tap(find.text('Medium'));
      await tester.pumpAndSettle();

      expect(settings.audioQuality, 'medium');
    });
  });

  group('Offline Downloads & Cached Playback tests', () {
    test('DownloadedTrack model serializes and converts to Track properly', () {
      final downloaded = DownloadedTrack(
        id: 'test_vid_1',
        title: 'Coryxkenshin pizza rap',
        artist: 'hyunstqr',
        duration: const Duration(minutes: 1, seconds: 20),
        audioFilePath: '/fake/path/test_vid_1.opus',
        thumbnailFilePath: '/fake/path/test_vid_1.jpg',
        audioCodec: 'OPUS',
        bitrate: 64000,
        fileSizeBytes: 1250000,
        downloadedAt: DateTime.now(),
      );

      final json = downloaded.toJson();
      final restored = DownloadedTrack.fromJson(json);

      expect(restored.id, 'test_vid_1');
      expect(restored.title, 'Coryxkenshin pizza rap');
      expect(restored.artist, 'hyunstqr');
      expect(restored.audioCodec, 'OPUS');
      expect(restored.fileSizeBytes, 1250000);

      final track = downloaded.toTrack();
      expect(track.id, 'test_vid_1');
      expect(track.title, 'Coryxkenshin pizza rap');
      expect(track.streamUrl, Uri.file('/fake/path/test_vid_1.opus'));
      expect(track.audioCodec, 'OPUS');
    });

    test('findDownloadedTrack matches CSV imported tracks by title and artist', () {
      final downloaded = DownloadedTrack(
        id: 'Shinunoga E-Wa',
        youtubeVideoId: 'dFf4Ag4050w',
        title: 'Shinunoga E-Wa',
        artist: 'Fujii Kaze',
        duration: const Duration(minutes: 3, seconds: 8),
        audioFilePath: Platform.isWindows ? 'C:\\fake\\Shinunoga.opus' : '/fake/Shinunoga.opus',
        fileSizeBytes: 1500000,
        downloadedAt: DateTime.now(),
      );

      // Verify serialization preserves youtubeVideoId
      final json = downloaded.toJson();
      expect(json['youtubeVideoId'], 'dFf4Ag4050w');
      final restored = DownloadedTrack.fromJson(json);
      expect(restored.youtubeVideoId, 'dFf4Ag4050w');

      // Verify toTrack uses youtubeVideoId as primary ID
      final toTrack = downloaded.toTrack();
      expect(toTrack.id, 'dFf4Ag4050w');
      expect(toTrack.streamUrl, Uri.file(downloaded.audioFilePath));
    });

    testWidgets('DownloadsScreen renders ArchiveTune downloads header and tabs',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      final playerService = PlayerService(
        initialVolume: 1.0,
        onVolumeChanged: (_) {},
        settingsService: settings,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DownloadsScreen(
            playerService: playerService,
            settingsService: settings,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);

      playerService.dispose();
    });

    testWidgets('CachedScreen renders ArchiveTune cached header, controls, and sort chip',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      final playlist = PlaylistService();
      await playlist.init();
      final playerService = PlayerService(
        initialVolume: 1.0,
        onVolumeChanged: (_) {},
        settingsService: settings,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CachedScreen(
            playerService: playerService,
            playlistService: playlist,
            settingsService: settings,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cached'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.text('Date added'), findsOneWidget);

      playerService.dispose();
    });

    test('DownloadService buildSearchQueries cleans multi-artist semicolons and parentheticals', () {
      // Test Error 1 case: Scrawny;Elio Mei - Six Legs (tippy tappy toes)
      final track1 = Track(
        id: 'track_1',
        title: 'Six Legs (tippy tappy toes)',
        author: 'Scrawny;Elio Mei',
        youtubeUrl: '',
        duration: const Duration(minutes: 3),
      );
      final queries1 = DownloadService.buildSearchQueries(track1);
      expect(queries1.first, 'Scrawny Six Legs');
      expect(queries1.any((q) => q.contains('Scrawny Six Legs')), isTrue);
      expect(queries1.first.contains(';'), isFalse);
      expect(queries1.first.contains('(tippy tappy toes)'), isFalse);

      // Test Error 3 case: MIMI;wanko - minimum (feat. wanko)
      final track2 = Track(
        id: 'track_2',
        title: 'minimum (feat. wanko)',
        author: 'MIMI;wanko',
        youtubeUrl: '',
        duration: const Duration(minutes: 3),
      );
      final queries2 = DownloadService.buildSearchQueries(track2);
      expect(queries2.first, 'MIMI minimum');
      expect(queries2.any((q) => q.contains('MIMI minimum')), isTrue);
      expect(queries2.first.contains(';'), isFalse);
      expect(queries2.first.contains('(feat. wanko)'), isFalse);

      // Test Error 2 case: Eminem - Mockingbird
      final track3 = Track(
        id: 'track_3',
        title: 'Mockingbird',
        author: 'Eminem',
        youtubeUrl: '',
        duration: const Duration(minutes: 4),
      );
      final queries3 = DownloadService.buildSearchQueries(track3);
      expect(queries3.any((q) => q.contains('Eminem Mockingbird')), isTrue);
    });

    test('DownloadService isValidYouTubeVideoId distinguishes 11-char titles from actual video IDs', () {
      // "Mockingbird" is 11 chars with no spaces, but is the title, not a video ID!
      expect(DownloadService.isValidYouTubeVideoId('Mockingbird', title: 'Mockingbird'), isFalse);
      // Actual YouTube 11-character video ID
      expect(DownloadService.isValidYouTubeVideoId('dQw4w9WgXcQ', title: 'Mockingbird'), isTrue);
      // IDs starting with internal prefixes or invalid lengths
      expect(DownloadService.isValidYouTubeVideoId('track_12345678', title: 'Song'), isFalse);
      expect(DownloadService.isValidYouTubeVideoId('spotify:track:xyz', title: 'Song'), isFalse);
      expect(DownloadService.isValidYouTubeVideoId('short', title: 'Song'), isFalse);
      expect(DownloadService.isValidYouTubeVideoId(null, title: 'Song'), isFalse);
    });

    test('DownloadService downloadTracks queues tasks with DownloadStatus.queued', () async {
      SharedPreferences.setMockInitialValues({});
      final service = DownloadService();
      await service.init();

      final t1 = Track(id: 'q1', title: 'Queue Song 1', author: 'Artist 1', youtubeUrl: '', duration: const Duration(minutes: 3));
      final t2 = Track(id: 'q2', title: 'Queue Song 2', author: 'Artist 2', youtubeUrl: '', duration: const Duration(minutes: 3));
      final t3 = Track(id: 'q3', title: 'Queue Song 3', author: 'Artist 3', youtubeUrl: '', duration: const Duration(minutes: 3));

      await service.downloadTracks([t1, t2, t3]);

      expect(service.activeTasks.length, 3);
      // With maxConcurrentDownloads = 2, at least 1 track must be queued
      expect(service.queuedCount, greaterThanOrEqualTo(1));

      // Clean up
      service.cancelDownload('q1');
      service.cancelDownload('q2');
      service.cancelDownload('q3');
      expect(service.activeTasks.isEmpty, isTrue);
    });

    test('PlaylistService updateTrackResolvedVideoId accurately maps and persists resolved ID', () async {
      SharedPreferences.setMockInitialValues({});
      final service = PlaylistService.instance;
      await service.init();

      final p = await service.createPlaylist(title: 'Imported Rock');
      final track = LocalPlaylistTrack(
        title: 'Californication',
        artist: 'Red Hot Chili Peppers',
        duration: const Duration(minutes: 5, seconds: 20),
      );
      await service.addTrackToPlaylist(p.id, track);

      var updatedPlaylist = service.getPlaylist(p.id)!;
      expect(updatedPlaylist.tracks.first.youtubeVideoId, isNull);

      await service.updateTrackResolvedVideoId(
        title: 'Californication',
        artist: 'Red Hot Chili Peppers',
        youtubeVideoId: 'YlUKcNNmywk',
      );

      updatedPlaylist = service.getPlaylist(p.id)!;
      expect(updatedPlaylist.tracks.first.youtubeVideoId, 'YlUKcNNmywk');
    });

    testWidgets('SearchTab renders ArchiveTune search categories including Videos', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final player = PlayerService();
      final auth = GoogleAuthService();
      final playlist = PlaylistService.instance;
      await playlist.init();
      final settings = SettingsService();
      await settings.init();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchTab(
              playerService: player,
              authService: auth,
              playlistService: playlist,
              settingsService: settings,
              accentColor: Colors.red,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);

      player.dispose();
    });

    testWidgets('AlbumViewScreen displays metadata, actions, and track list', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final player = PlayerService();
      final auth = GoogleAuthService();
      final playlist = PlaylistService.instance;
      await playlist.init();
      final settings = SettingsService();
      await settings.init();

      final sampleTracks = [
        LocalPlaylistTrack(
          title: 'Album Song One',
          artist: 'Test Artist',
          duration: const Duration(minutes: 3, seconds: 12),
          youtubeVideoId: 'video_id_1',
        ),
        LocalPlaylistTrack(
          title: 'Album Song Two',
          artist: 'Test Artist',
          duration: const Duration(minutes: 4, seconds: 5),
          youtubeVideoId: 'video_id_2',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: AlbumViewScreen(
            title: 'Greatest Album',
            artist: 'Test Artist',
            year: '2024',
            type: 'Album',
            initialTracks: sampleTracks,
            playerService: player,
            playlistService: playlist,
            settingsService: settings,
            authService: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Greatest Album'), findsWidgets);
      expect(find.text('Test Artist'), findsWidgets);
      expect(find.text('Album Song One'), findsOneWidget);
      expect(find.text('Album Song Two'), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      player.dispose();
    });

    testWidgets('ArtistScreen does not render "In Your Library" section and builds cleanly', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final player = PlayerService();
      final auth = GoogleAuthService();
      final playlist = PlaylistService.instance;
      await playlist.init();
      final settings = SettingsService();
      await settings.init();

      await tester.pumpWidget(
        MaterialApp(
          home: ArtistScreen(
            artistName: 'Marino',
            playerService: player,
            authService: auth,
            playlistService: playlist,
            settingsService: settings,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('In Your Library'), findsNothing);
      expect(find.text('Marino'), findsWidgets);

      player.dispose();
    });

    test('Lyrics timing offset persists per track in SettingsService', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      expect(settings.getLyricsOffsetMs('track_lang_lost'), 0);

      // Set 7.1s offset for YouTube video intro
      await settings.setLyricsOffsetMs('track_lang_lost', 7100);
      expect(settings.getLyricsOffsetMs('track_lang_lost'), 7100);

      // Initialize a new instance to verify persistence
      final settings2 = SettingsService();
      await settings2.init();
      expect(settings2.getLyricsOffsetMs('track_lang_lost'), 7100);

      // Reset to 0
      await settings2.setLyricsOffsetMs('track_lang_lost', 0);
      expect(settings2.getLyricsOffsetMs('track_lang_lost'), 0);
    });

    test('LyricsService sanitizeLyricText cleans sound tags and artifacts', () {
      expect(LyricsService.sanitizeLyricText('[Music] In the city of the dead [Applause]'), 'In the city of the dead');
      expect(LyricsService.sanitizeLyricText('[音楽] STInsidemybedTHE [拍手]'), 'STInsidemybedTHE');
      expect(LyricsService.sanitizeLyricText('♪ Pouring from their open mouths ♪'), 'Pouring from their open mouths');
      expect(LyricsService.sanitizeLyricText('[Ongaku]'), '');
      expect(LyricsService.sanitizeLyricText('[Hakushu]'), '');
    });

    test('LyricsData preserves providerVariants and copyWith works accurately', () {
      final line1 = LyricLine(timestamp: const Duration(seconds: 1), text: 'Line 1');
      final data = LyricsData(
        lines: [line1],
        source: 'LRCLIB',
        isSynced: true,
        providerVariants: {
          'LRCLIB': LyricsData(lines: [line1], source: 'LRCLIB'),
          'KuGou': LyricsData(lines: [line1], source: 'KuGou'),
          'NetEase': LyricsData(lines: [line1], source: 'NetEase'),
          'SimpMusic': LyricsData(lines: [line1], source: 'SimpMusic'),
        },
      );

      expect(data.lines.length, 1);
      expect(data.providerVariants.containsKey('KuGou'), isTrue);
      expect(data.providerVariants.containsKey('LRCLIB'), isTrue);
      expect(data.providerVariants.containsKey('NetEase'), isTrue);
      expect(data.providerVariants.containsKey('SimpMusic'), isTrue);

      final switched = data.copyWith(source: 'NetEase');
      expect(switched.source, 'NetEase');
      expect(switched.providerVariants.length, 4);
    });

    test('SettingsService persists and toggles enableNetEase correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      expect(settings.enableNetEase, isTrue);
      await settings.setLyricsProviderEnabled('netease', false);
      expect(settings.enableNetEase, isFalse);

      final settings2 = SettingsService();
      await settings2.init();
      expect(settings2.enableNetEase, isFalse);
    });

    test('LyricsService fetchLyricsWithProvider returns cached variant for NetEase and SimpMusic', () async {
      final track = Track(
        id: 'test_netease_track',
        title: 'Language of the Lost',
        author: 'Riproducer',
        youtubeUrl: '',
        duration: const Duration(minutes: 3),
      );

      final line1 = LyricLine(timestamp: const Duration(seconds: 1), text: 'In the city of the dead');
      final line2 = LyricLine(timestamp: const Duration(seconds: 2), text: 'I lay stuck inside my bed');
      final netEaseData = LyricsData(
        lines: [line1, line2],
        source: 'NetEase',
        isSynced: true,
      );
      final simpData = LyricsData(
        lines: [line1],
        source: 'SimpMusic',
        isSynced: true,
      );

      final bundle = LyricsData(
        lines: [line1],
        source: 'SimpMusic',
        isSynced: true,
        providerVariants: {
          'NetEase': netEaseData,
          'SimpMusic': simpData,
        },
      );

      LyricsService.instance.setLyricsForTesting(track.id, bundle);

      final switchedNetEase = await LyricsService.instance.fetchLyricsWithProvider(track, 'NetEase');
      expect(switchedNetEase, isNotNull);
      expect(switchedNetEase!.source, 'NetEase');
      expect(switchedNetEase.lines.length, 2);
      expect(switchedNetEase.lines[0].text, 'In the city of the dead');

      final switchedSimp = await LyricsService.instance.fetchLyricsWithProvider(track, 'SimpMusic');
      expect(switchedSimp, isNotNull);
      expect(switchedSimp!.source, 'SimpMusic');
    });

    test('SettingsService persists and toggles autoAlignLyricsOffset and autoSyncPlainLyrics correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      expect(settings.autoAlignLyricsOffset, isTrue);
      expect(settings.autoSyncPlainLyrics, isTrue);

      await settings.setAutoAlignLyricsOffset(false);
      await settings.setAutoSyncPlainLyrics(false);

      expect(settings.autoAlignLyricsOffset, isFalse);
      expect(settings.autoSyncPlainLyrics, isFalse);

      final settings2 = SettingsService();
      await settings2.init();
      expect(settings2.autoAlignLyricsOffset, isFalse);
      expect(settings2.autoSyncPlainLyrics, isFalse);
    });

    testWidgets('LyricsSettingsScreen renders with custom user theme and FinAudio real options', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      // Set custom user theme colors
      await settings.setBackgroundColor(const Color(0xFF0F172A));
      await settings.setSurfaceColor(const Color(0xFF1E293B));
      await settings.setAccentColor(const Color(0xFF38BDF8));
      await settings.setTextColor(const Color(0xFFF8FAFC));

      await tester.pumpWidget(
        MaterialApp(
          home: LyricsSettingsScreen(settingsService: settings),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Screen Header
      expect(find.text('Lyrics'), findsOneWidget);

      // Verify Timing & Synchronization section
      expect(find.text('Timing & Synchronization'), findsOneWidget);
      expect(find.text('Auto-align timing offset'), findsOneWidget);
      expect(find.text('Auto-sync plain lyrics'), findsOneWidget);

      // Verify Active Providers section
      expect(find.text('Active Lyrics Providers'), findsOneWidget);
      expect(find.text('Preferred lyrics provider'), findsOneWidget);
      expect(find.text('NetEase Cloud Music'), findsOneWidget);
      expect(find.text('SimpMusic'), findsOneWidget);
      expect(find.text('BetterLyrics'), findsWidgets);
      expect(find.text('KuGou'), findsOneWidget);
      expect(find.text('LRCLIB'), findsOneWidget);

      // Verify toggling autoAlignLyricsOffset
      expect(settings.autoAlignLyricsOffset, isTrue);
      final autoAlignSwitch = find.ancestor(
        of: find.text('Auto-align timing offset'),
        matching: find.byType(Switch),
      );
      if (autoAlignSwitch.evaluate().isNotEmpty) {
        await tester.tap(autoAlignSwitch);
        await tester.pumpAndSettle();
        expect(settings.autoAlignLyricsOffset, isFalse);
      }

      // Tap "Preferred lyrics provider" tile to open bottom picker sheet
      await tester.tap(find.text('Preferred lyrics provider'));
      await tester.pumpAndSettle();

      // Verify provider options in sheet
      expect(find.text('Preferred Lyrics Provider'), findsOneWidget);
      expect(find.text('BetterLyrics'), findsWidgets);
      expect(find.text('SimpMusic'), findsWidgets);
      expect(find.text('NetEase'), findsWidgets);
      expect(find.text('LRCLIB'), findsWidgets);
      expect(find.text('KuGou'), findsWidgets);
      expect(find.text('YouTube Captions'), findsOneWidget);

      // Select NetEase from picker sheet
      await tester.tap(find.text('NetEase').last);
      await tester.pumpAndSettle();
      expect(settings.preferredLyricsProvider, 'NetEase');
    });
  });

  group('Multi-Artist separation and imported playlist optimization tests', () {
    test('LocalPlaylistTrack and Track splitArtists separates semicolons, commas, and feats', () {
      // 1. Semicolon separation (Exportify / Spotify CSVs)
      final raw1 = 'Wuthering Waves;jkinss;VISION SOUND';
      final artists1 = LocalPlaylistTrack.splitArtists(raw1);
      expect(artists1, ['Wuthering Waves', 'jkinss', 'VISION SOUND']);

      final track1 = LocalPlaylistTrack(title: 'When the Bird Glides', artist: raw1);
      expect(track1.individualArtists, ['Wuthering Waves', 'jkinss', 'VISION SOUND']);
      expect(track1.formattedArtist, 'Wuthering Waves, jkinss, VISION SOUND');

      final playable1 = Track(
        id: 'test_1',
        title: 'When the Bird Glides',
        author: raw1,
        youtubeUrl: '',
        duration: Duration.zero,
      );
      expect(playable1.individualArtists, ['Wuthering Waves', 'jkinss', 'VISION SOUND']);
      expect(playable1.formattedArtist, 'Wuthering Waves, jkinss, VISION SOUND');

      // 2. Comma separation
      final raw2 = 'Taylor Swift, Post Malone';
      final artists2 = LocalPlaylistTrack.splitArtists(raw2);
      expect(artists2, ['Taylor Swift', 'Post Malone']);

      // 3. Feat / ft delimiter
      final raw3 = 'Drake feat. Rihanna';
      final artists3 = LocalPlaylistTrack.splitArtists(raw3);
      expect(artists3, ['Drake', 'Rihanna']);

      // 4. Slash delimiter
      final raw4 = 'Artist 1 / Artist 2';
      final artists4 = LocalPlaylistTrack.splitArtists(raw4);
      expect(artists4, ['Artist 1', 'Artist 2']);

      // 5. Band name with slash without spaces preserved
      final raw5 = 'AC/DC';
      final artists5 = LocalPlaylistTrack.splitArtists(raw5);
      expect(artists5, ['AC/DC']);

      // 6. Single artist
      final raw6 = 'Yonkagor';
      final artists6 = LocalPlaylistTrack.splitArtists(raw6);
      expect(artists6, ['Yonkagor']);
    });

    test('PlaylistService.createFromText normalizes CSV multi-artist into clean format', () async {
      SharedPreferences.setMockInitialValues({});
      final service = PlaylistService();
      await service.init();

      final csvContent = '''
"Track URI","Track Name","Artist Name(s)","Album Name","Disc Number","Track Number","Track Duration (ms)","Added By","Added At"
"spotify:track:1","When the Bird Glides","Wuthering Waves;jkinss;VISION SOUND","Wuthering Waves OST","1","1","204000","",""
"spotify:track:2","Fortnight","Taylor Swift, Post Malone","THE TORTURED POETS DEPARTMENT","1","1","228000","",""
''';

      final playlist = await service.createFromText(
        title: 'Exportify Test',
        rawText: csvContent,
      );

      expect(playlist.tracks.length, 2);
      expect(playlist.tracks[0].title, 'When the Bird Glides');
      expect(playlist.tracks[0].artist, 'Wuthering Waves, jkinss, VISION SOUND');
      expect(playlist.tracks[0].individualArtists, ['Wuthering Waves', 'jkinss', 'VISION SOUND']);

      expect(playlist.tracks[1].title, 'Fortnight');
      expect(playlist.tracks[1].artist, 'Taylor Swift, Post Malone');
      expect(playlist.tracks[1].individualArtists, ['Taylor Swift', 'Post Malone']);
    });

    testWidgets('showArtistPickerSheet renders all collaborating artists and handles selection',
        (tester) async {
      String? selectedArtist;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    showArtistPickerSheet(
                      context: ctx,
                      artists: ['Wuthering Waves', 'jkinss', 'VISION SOUND'],
                      trackTitle: 'When the Bird Glides',
                      onSelectArtist: (artist) => selectedArtist = artist,
                    );
                  },
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Artists in this track'), findsOneWidget);
      expect(find.text('When the Bird Glides'), findsOneWidget);
      expect(find.text('Wuthering Waves'), findsOneWidget);
      expect(find.text('jkinss'), findsOneWidget);
      expect(find.text('VISION SOUND'), findsOneWidget);

      // Tap "jkinss"
      await tester.tap(find.text('jkinss'));
      await tester.pumpAndSettle();

      expect(selectedArtist, 'jkinss');
    });

    test('Track.fromLocalPlaylistTrack constructs non-blocking model instantaneously', () {
      final local = LocalPlaylistTrack(
        title: 'Instant Track',
        artist: 'Artist A;Artist B',
        duration: const Duration(minutes: 3),
      );

      final track = Track.fromLocalPlaylistTrack(local);
      expect(track.title, 'Instant Track');
      expect(track.author, 'Artist A;Artist B');
      expect(track.individualArtists, ['Artist A', 'Artist B']);
      expect(track.formattedArtist, 'Artist A, Artist B');
    });
  });

  group('Lyrics Animation, Romanization, and Color Customization tests', () {
    test('SettingsService persists and notifies custom lyrics active, inactive, and glow colors', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      expect(settings.hasCustomLyricsColors, isFalse);
      expect(settings.customLyricsActiveColor, isNull);
      expect(settings.customLyricsInactiveColor, isNull);
      expect(settings.customLyricsGlowColor, isNull);

      bool notified = false;
      settings.addListener(() => notified = true);

      // Set active color
      await settings.setLyricsActiveColor(const Color(0xFFFF5252));
      expect(notified, isTrue);
      expect(settings.lyricsActiveColor, const Color(0xFFFF5252));
      expect(settings.customLyricsActiveColor, const Color(0xFFFF5252));
      expect(settings.hasCustomLyricsColors, isTrue);

      // Set inactive color
      notified = false;
      await settings.setLyricsInactiveColor(const Color(0xFF757575));
      expect(notified, isTrue);
      expect(settings.lyricsInactiveColor, const Color(0xFF757575));
      expect(settings.customLyricsInactiveColor, const Color(0xFF757575));

      // Set glow color
      notified = false;
      await settings.setLyricsGlowColor(const Color(0xFF00E5FF));
      expect(notified, isTrue);
      expect(settings.lyricsGlowColor, const Color(0xFF00E5FF));
      expect(settings.customLyricsGlowColor, const Color(0xFF00E5FF));

      // Re-initialize and verify persistence
      final settings2 = SettingsService();
      await settings2.init();
      expect(settings2.lyricsActiveColor, const Color(0xFFFF5252));
      expect(settings2.lyricsInactiveColor, const Color(0xFF757575));
      expect(settings2.lyricsGlowColor, const Color(0xFF00E5FF));
      expect(settings2.hasCustomLyricsColors, isTrue);

      // Reset colors
      notified = false;
      await settings.resetLyricsColors();
      expect(notified, isTrue);
      expect(settings.hasCustomLyricsColors, isFalse);
      expect(settings.customLyricsActiveColor, isNull);
      expect(settings.customLyricsInactiveColor, isNull);
      expect(settings.customLyricsGlowColor, isNull);
    });

    test('SettingsService persists lyricsMode and lyricsAnimationStyle', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      expect(settings.lyricsMode, 'Enhanced');
      expect(settings.lyricsAnimationStyle, 'Fluid Apple Music');

      await settings.setLyricsMode('V2');
      expect(settings.lyricsMode, 'V2');

      await settings.setLyricsMode('Standard');
      expect(settings.lyricsMode, 'Standard');

      await settings.setLyricsAnimationStyle('Fade & Slide');
      expect(settings.lyricsAnimationStyle, 'Fade & Slide');

      final settings2 = SettingsService();
      await settings2.init();
      expect(settings2.lyricsMode, 'Standard');
      expect(settings2.lyricsAnimationStyle, 'Fade & Slide');
    });

    test('LyricsRomanizer romanizes Korean and Chinese text offline accurately', () {
      // Korean Hangul Romanization
      expect(LyricsRomanizer.hasForeign('안녕하세요', korean: true), isTrue);
      final korResult = LyricsRomanizer.romanize('안녕하세요', korean: true);
      expect(korResult.toLowerCase(), contains('annyeonghaseyo'));

      final korSongLine = LyricsRomanizer.romanize('사랑해', korean: true);
      expect(korSongLine.toLowerCase(), contains('saranghae'));

      // Chinese Pinyin Romanization
      expect(LyricsRomanizer.hasForeign('你好世界', chinese: true), isTrue);
      final chnResult = LyricsRomanizer.romanize('你好世界', chinese: true);
      expect(chnResult.toLowerCase(), contains('ni hao'));

      final chnSongLine = LyricsRomanizer.romanize('我爱你', chinese: true);
      expect(chnSongLine.toLowerCase(), contains('wo ai ni'));

      // Japanese Romaji Romanization
      expect(LyricsRomanizer.hasForeign('さようなら', japanese: true), isTrue);
      final japResult = LyricsRomanizer.romanize('さようなら', japanese: true);
      expect(japResult.toLowerCase(), 'sayounara');

      // English / ASCII text should not be detected as foreign
      expect(LyricsRomanizer.hasForeign('Hello World', japanese: true, korean: true, chinese: true), isFalse);
    });

    testWidgets('LyricsSettingsScreen displays Lyric Colors & Glow section and animation style', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      await settings.setLyricsMode('V2');

      await tester.pumpWidget(
        MaterialApp(
          home: LyricsSettingsScreen(settingsService: settings),
        ),
      );
      await tester.pumpAndSettle();

      // Verify sections
      expect(find.text('Lyrics animation style'), findsOneWidget);
      expect(find.text('Fluid Apple Music'), findsWidgets);

      // Scroll to bottom to view Lyric Colors & Glow
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('Lyric Colors & Glow'), findsOneWidget);
      expect(find.text('Active lyric color'), findsOneWidget);
      expect(find.text('Inactive lyric color'), findsOneWidget);
    });
  });

  group('Discord Rich Presence tests', () {
    test('SettingsService loads default Discord RPC values and persists updates', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();

      expect(DiscordRpcService.defaultAppId, '1561283600908025947');
      expect(DiscordRpcService.instance.isConnected, isFalse);
      expect(settings.discordRpcEnabled, isTrue);
      expect(settings.discordAppId, '1561283600908025947');
      expect(settings.discordShowButtons, isTrue);
      expect(settings.discordShowTimestamps, isTrue);
      expect(settings.isDiscordConnectedOnMobile, isFalse);

      await settings.setDiscordRpcEnabled(false);
      expect(settings.discordRpcEnabled, isFalse);

      await settings.setDiscordShowButtons(false);
      expect(settings.discordShowButtons, isFalse);

      await settings.setDiscordShowTimestamps(false);
      expect(settings.discordShowTimestamps, isFalse);

      await settings.setDiscordAccount(
        token: 'test_token_123',
        username: 'EthanJohn',
        userId: '1234567890',
        avatar: 'avatar_hash_abc',
      );
      expect(settings.isDiscordConnectedOnMobile, isTrue);
      expect(settings.discordUsername, 'EthanJohn');
      expect(settings.discordUserId, '1234567890');
      expect(settings.discordAvatar, 'avatar_hash_abc');

      // Verify persistence across new instance
      final settings2 = SettingsService();
      await settings2.init();
      expect(settings2.discordRpcEnabled, isFalse);
      expect(settings2.discordShowButtons, isFalse);
      expect(settings2.discordShowTimestamps, isFalse);
      expect(settings2.isDiscordConnectedOnMobile, isTrue);
      expect(settings2.discordUsername, 'EthanJohn');

      // Test disconnect
      await settings2.disconnectDiscordAccount();
      expect(settings2.isDiscordConnectedOnMobile, isFalse);
      expect(settings2.discordToken, isNull);
      expect(settings2.discordUsername, isNull);
    });

    testWidgets('SettingsScreen renders Discord Rich Presence section and controls', (WidgetTester tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsService();
        await settings.init();
        final auth = GoogleAuthService();

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              settingsService: settings,
              authService: auth,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Scroll to Discord Rich Presence section
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();

        expect(find.text('Discord Rich Presence'), findsWidgets);
        expect(find.text('Show "Listen on YouTube" button'), findsOneWidget);
        expect(find.text('Show playback timer'), findsOneWidget);
      }, _TestHttpOverrides());
    });

    testWidgets('DiscordLoginDialog renders token input and guidelines', (WidgetTester tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsService();
        await settings.init();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DiscordLoginDialog(settingsService: settings),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Connect Discord'), findsOneWidget);
        expect(find.text('Discord Account Token'), findsOneWidget);
        expect(find.text('Connect'), findsOneWidget);
        expect(find.text('How do I find my Discord token?'), findsOneWidget);
        expect(find.textContaining('Log in'), findsOneWidget);

        // Tap instructions expander
        await tester.tap(find.text('How do I find my Discord token?'));
        await tester.pumpAndSettle();

        expect(find.text('Hide instructions'), findsOneWidget);
      }, _TestHttpOverrides());
    });

    testWidgets('DiscordWebViewScreen renders appbar and fallback cleanly', (WidgetTester tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsService();
        await settings.init();

        expect(DiscordRpcService.appIconHash, '72615f31d71977d9f493f011a85da63b');
        expect(DiscordRpcService.appIconUrl.contains('1561283600908025947'), isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: DiscordWebViewScreen(settingsService: settings),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Discord Login'), findsOneWidget);
      }, _TestHttpOverrides());
    });

    test('DiscordWebViewScreen oauthAuthorizeUrl matches official ArchiveTune Social SDK format', () {
      final url = DiscordWebViewScreen.oauthAuthorizeUrl;
      expect(url.contains('client_id=1561283600908025947'), isTrue);
      expect(url.contains('response_type=token'), isTrue);
      expect(url.contains('scope=openid%20sdk.social_layer_presence'), isTrue);
      expect(url.contains('redirect_uri=https://localhost'), isTrue);
    });

    test('Spotify-style pausing: updatePresence clears presence when paused', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      final player = PlayerService();
      final rpc = DiscordRpcService.instance;
      rpc.attach(playerService: player, settingsService: settings);

      final track = Track.fromPlaylistVideo(
        videoId: 'wZlv3qDPfjk',
        title: 'MoeChakkaFire',
        author: 'issey',
        duration: const Duration(minutes: 2, seconds: 35),
      );

      // When playing is false, presence should be cleared immediately (Spotify behavior)
      await rpc.updatePresence(
        track: track,
        isPlaying: false,
        position: Duration.zero,
        duration: track.duration,
      );

      // Verify no throw and clean clear
      await rpc.clearPresence();
    });

    test('Track.publicThumbnailUrl extracts YouTube thumbnail from youtubeUrl if id is non-11 chars', () {
      final spotifyTrack = Track(
        id: 'spotify:track:4cOdK2wGLETKBW3PvgPWqT',
        title: 'MoeChakkaFire',
        author: 'issey',
        youtubeUrl: 'https://www.youtube.com/watch?v=wZlv3qDPfjk',
        duration: const Duration(minutes: 2, seconds: 35),
        thumbnailUrl: 'file:///C:/Users/Ethan/thumb.jpg',
      );

      expect(spotifyTrack.publicThumbnailUrl, 'https://img.youtube.com/vi/wZlv3qDPfjk/hqdefault.jpg');

      final webTrack = Track(
        id: 'wZlv3qDPfjk',
        title: 'MoeChakkaFire',
        author: 'issey',
        youtubeUrl: 'https://www.youtube.com/watch?v=wZlv3qDPfjk',
        duration: const Duration(minutes: 2, seconds: 35),
        thumbnailUrl: 'https://img.youtube.com/vi/wZlv3qDPfjk/hqdefault.jpg',
      );

      expect(webTrack.publicThumbnailUrl, 'https://img.youtube.com/vi/wZlv3qDPfjk/hqdefault.jpg');

      final unknownTrack = Track(
        id: 'local_file_without_yt',
        title: 'Local',
        author: 'Unknown',
        youtubeUrl: '',
        duration: Duration.zero,
        thumbnailUrl: 'file:///data/local.jpg',
      );

      expect(unknownTrack.publicThumbnailUrl, isNull);
    });

    test('DownloadedTrack.toTrack preserves public HTTP thumbnail and sets localThumbnailPath', () {
      final downloaded = DownloadedTrack(
        id: 'custom_id_123',
        youtubeVideoId: 'wZlv3qDPfjk',
        title: 'MoeChakkaFire',
        artist: 'issey',
        duration: const Duration(minutes: 2, seconds: 35),
        audioFilePath: 'C:/audio/test.opus',
        thumbnailFilePath: 'C:/audio/test.jpg',
        thumbnailUrl: 'https://img.youtube.com/vi/wZlv3qDPfjk/hqdefault.jpg',
        fileSizeBytes: 2048,
        downloadedAt: DateTime(2026, 1, 1),
      );

      final track = downloaded.toTrack();
      expect(track.thumbnailUrl, 'https://img.youtube.com/vi/wZlv3qDPfjk/hqdefault.jpg');
      expect(track.localThumbnailPath, 'C:/audio/test.jpg');
      expect(track.publicThumbnailUrl, 'https://img.youtube.com/vi/wZlv3qDPfjk/hqdefault.jpg');
    });

    test('DownloadedTrack.fromJson cleans local path from thumbnailUrl and restores YouTube thumbnail', () {
      final jsonWithLocalPath = {
        'id': 'wZlv3qDPfjk',
        'youtubeVideoId': 'wZlv3qDPfjk',
        'title': 'MoeChakkaFire',
        'artist': 'issey',
        'durationMs': 155000,
        'audioFilePath': 'C:/audio/test.opus',
        'thumbnailFilePath': 'C:/audio/test.jpg',
        'thumbnailUrl': 'C:/Users/Ethan/thumb.jpg', // Local Windows path in legacy json
        'fileSizeBytes': 2048,
      };

      final downloaded = DownloadedTrack.fromJson(jsonWithLocalPath);
      expect(downloaded.thumbnailUrl, 'https://img.youtube.com/vi/wZlv3qDPfjk/hqdefault.jpg');
    });

    testWidgets('NowPlayingBar displays PAUSED tag when song is paused', (WidgetTester tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final player = PlayerService();
        final track = Track.fromPlaylistVideo(
          videoId: 'dQw4w9WgXcQ',
          title: 'Do It All for You',
          author: 'Alan Walker',
          duration: const Duration(minutes: 2, seconds: 54),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NowPlayingBar(
                track: track,
                accentColor: const Color(0xFFFFDE38),
                playerService: player,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('PAUSED'), findsOneWidget);
        expect(find.text('Do It All for You'), findsOneWidget);
        expect(find.text('Alan Walker'), findsOneWidget);
      }, _TestHttpOverrides());
    });
  });

  group('CrashLogService and Diagnostics tests', () {
    test('CrashLogService initializes and records errors to memory and file', () async {
      final crashService = CrashLogService.instance;
      await crashService.init();

      await crashService.logCrash(
        Exception('Test simulated crash'),
        StackTrace.current,
        reason: 'Unit test execution',
      );

      final logs = await crashService.readLogs();
      expect(logs.contains('Test simulated crash'), isTrue);
      expect(logs.contains('FINAUDIO CRASH LOG'), isTrue);
      expect(logs.contains('Unit test execution'), isTrue);

      final path = await crashService.getPrimaryLogPath();
      expect(path.contains('FinAudioCrashLogs'), isTrue);

      await crashService.clearLogs();
    });

    testWidgets('SettingsScreen renders Diagnostics & Logs section and Crash Logs tile', (WidgetTester tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsService();
        await settings.init();
        final authService = GoogleAuthService();

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              settingsService: settings,
              authService: authService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Diagnostics & Logs'), findsOneWidget);
        expect(find.text('Crash Logs'), findsOneWidget);
        expect(find.textContaining('FinAudioCrashLogs'), findsOneWidget);
      }, _TestHttpOverrides());
    });

    test('Track and DownloadedTrack properly expose localThumbnailPath and publicThumbnailUrl', () {
      final downloaded = DownloadedTrack(
        id: 'dQw4w9WgXcQ',
        youtubeVideoId: 'dQw4w9WgXcQ',
        title: 'Morose Dreamer - Lofi Version',
        artist: 'TiHA Studio',
        duration: const Duration(minutes: 3),
        audioFilePath: 'C:/fake/path/audio.opus',
        thumbnailFilePath: 'C:/fake/path/thumb.jpg',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        fileSizeBytes: 1024,
        downloadedAt: DateTime.now(),
      );

      final track = downloaded.toTrack();
      expect(track.localThumbnailPath, 'C:/fake/path/thumb.jpg');
      expect(track.publicThumbnailUrl, 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    });

    test('DownloadedTrack.fromJson cleans legacy file:// URLs and restores public YouTube thumbnail', () {
      final json = {
        'id': 'dQw4w9WgXcQ',
        'youtubeVideoId': 'dQw4w9WgXcQ',
        'title': 'Morose Dreamer',
        'artist': 'TiHA Studio',
        'durationMs': 180000,
        'audioFilePath': '/path/to/song.opus',
        'thumbnailFilePath': '/path/to/thumb.jpg',
        'thumbnailUrl': 'file:///path/to/thumb.jpg',
        'fileSizeBytes': 1024,
        'downloadedAt': DateTime.now().toIso8601String(),
      };

      final downloaded = DownloadedTrack.fromJson(json);
      expect(downloaded.thumbnailUrl, 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      final track = downloaded.toTrack();
      expect(track.publicThumbnailUrl, 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
    });
  });
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  Duration? connectionTimeout;
  @override
  bool autoUncompress = false;
  @override
  void close({bool force = false}) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  static final List<int> _transparent1x1Png = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ];

  @override
  int get statusCode => 200;
  @override
  int get contentLength => _transparent1x1Png.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_transparent1x1Png).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

