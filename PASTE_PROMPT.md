# Paste this prompt at the start of a new session to restore full context

I'm building a Flutter app called **FinAudio** at path: `C:\Users\Ethan John\Documents\FinAudio\finaudio`

**What it does**: Ad-free YouTube audio player + Google playlist sync

**Tech stack**:
- `youtube_explode_dart: ^3.1.0` — extracts audio stream URLs from YouTube (no download)
- `just_audio: ^0.9.46` — plays audio streams (ExoPlayer on Android; custom YouTubeStreamSource for header forwarding)
- `google_sign_in: ^7.2.0` — Google authentication (v7 API, uses `authenticate()` not `signIn()`)
- `googleapis: ^17.0.0` — YouTube Data API v3 for fetching liked playlists
- `googleapis_auth: ^2.3.3` — OAuth2 authenticated HTTP clients
- `extension_google_sign_in_as_googleapis_auth: ^3.0.0` — bridges google_sign_in with googleapis
- `rxdart: ^0.28.0` — reactive streams
- `http: ^1.2.0` — HTTP client
- `shared_preferences: ^2.3.3` — persistent settings storage
- `flutter_colorpicker: ^1.1.0` — accent color picker

**File structure**:
```
lib/
├── main.dart                      # Full UI: App root + all screens
│   ├── FinAudioApp                # App root with theme, settings, player/auth services
│   ├── _MainScaffold              # Bottom nav: Player, Playlists tabs
│   ├── PlayerTab                  # Music player: album art, seek bar, transport controls, up-next
│   ├── PlaylistsTab               # Google Sign-In → liked videos + search → play all / play one
│   ├── _AlbumArt                  # Large album art with shadow (280x280)
│   ├── _SeekBar                   # Seek bar with live position/duration via streams
│   ├── _TransportControls         # Shuffle | Prev | Play/Pause | Next | Repeat
│   ├── _PlayPauseButton           # Large circular play/pause button
│   ├── _UpNextSection/Tile        # Vertical queue list with thumbnails
│   ├── _AuthSection               # Sign-in/sign-out UI for playlists
│   └── _MusicListTile             # Video list tile with thumbnail + play button
├── services/
│   ├── player_service.dart        # Centralized PlayerService with queue, shuffle, loop, auto-advance
│   │   ├── Track                  # id, title, author, youtubeUrl, streamUrl, duration
│   │   ├── LoopMode enum          # off, one, all
│   │   └── PlayerService          # Owns AudioPlayer + YoutubeService
│   │       - _playTrack()         # Plays via YouTubeStreamSource (Dart HTTP, not ExoPlayer HTTP)
│   │       - nextTrack()          # Skip to next track in queue
│   │       - previousTrack()      # Skip to previous (or restart if >3s in)
│   │       - toggleShuffle()      # Shuffle/unshuffle queue (keeps current at front)
│   │       - onTrackEnd()         # Auto-advance on track completion (auto-wired via processingStateStream)
│   │       - positionStream       # Live position updates for seek bar
│   │       - durationStream       # Live duration updates for seek bar
│   │       - nowPlayingStream     # Fires when track changes
│   ├── youtube_service.dart       # YoutubeExplode resolver: URL → audio stream URL (forces HTTPS)
│   │   └── ResolvedVideo          # title, author, duration, videoUrl, audioStreamUrl
│   └── youtube_stream_source.dart # Custom StreamAudioSource: Dart HttpClient sends headers to YouTube CDN
│   ├── google_auth_service.dart   # Google Sign-In v7 + YouTube Data API v3
│   │   ├── PlaylistVideo          # videoId, title, channelTitle, thumbnailUrl, duration
│   │   └── GoogleAuthService      # signIn, signOut, fetchLikedVideos, searchMusic (music-only, category 10)
│   └── settings_service.dart      # Persistent accent color + dark intensity via SharedPreferences
├── ui/
│   └── settings_screen.dart       # Settings page: dark intensity presets, accent color picker
└── widgets/
    └── now_playing_bar.dart       # Compact bar: thumbnail, title, play/pause, next, progress
```

**Key architecture details**:
- **PlayerService** is the central playback engine. All playback goes through `_playTrack()` which uses `YouTubeStreamSource` (Dart HTTP) to send proper User-Agent/Referer headers to YouTube's CDN. ExoPlayer's built-in HTTP layer silently drops these headers, causing 403 errors. Auto-wired via `processingStateStream`.
- **Shuffle**: `toggleShuffle()` randomizes queue but keeps current track at index 0. `toggleShuffle()` again restores original order.
- **Position/Duration**: Tracked via internal streams (`positionStream`, `durationStream`), NOT via AudioPlayer getters.
- **Track** class has: `id`, `title`, `author`, `youtubeUrl`, `streamUrl`, `duration`.
- **Music filtering**: YouTube search and playlist fetch filter to category 10 (music) only.
- **Play All**: PlaylistsTab has "Play all" button that enqueues all songs from liked music or search results.
- **previousTrack()**: If >3 seconds in, restarts current song. Otherwise goes to previous track.
- **SettingsScreen** creates its own `SettingsService` instance — not a singleton.
- **googleapis search API**: `type` parameter is `List<String>?`, use `type: ['video']`.

**Google Cloud setup (already done)**:
- Project: "FinAudio" on Google Cloud Console
- YouTube Data API v3: enabled
- Two OAuth client IDs: Android + Web (Web used as `serverClientId` in `google_auth_service.dart`)

**Current status**:
- ✅ `flutter analyze` passes with zero errors
- ✅ `flutter test` passes
- ✅ Player tab: full music player UI with album art, seek bar, transport controls
- ✅ Transport: shuffle, prev, play/pause, next, repeat (off/one/all)
- ✅ Auto-advance: tracks play sequentially with loop support (wired via processingStateStream)
- ✅ Android audio: custom `YouTubeStreamSource` bypasses ExoPlayer HTTP layer with proper headers
- ✅ Android config: cleartext traffic allowed via network_security_config.xml
- ✅ Playlists tab: Google Sign-In, liked videos, search (music-only), Play All
- ✅ Now-playing bar: compact with progress, play/pause, next
- ✅ Settings: dark intensity, accent color picker

**Known issues / TODOs**:
1. Google Sign-In requires Google verification for production — set OAuth consent screen to "Testing" mode for testing
2. YouTube stream resolution may need JS solver (DenoEJSSolver) for some videos
3. `StreamAudioSource` is experimental in just_audio — monitor for breaking changes
4. Queue doesn't persist across app restarts
5. Deprecated `.alpha`/`.red`/`.green`/`.blue` Color properties (info-level)

**Platform**: Windows (Flutter 3.47.0, Dart 3.13.0)
