# FinAudio - Project Context Document

## Overview
**Name**: FinAudio
**Path**: `C:\Users\Ethan John\Documents\FinAudio\finaudio`
**Type**: Flutter app
**Version**: 1.0.0+1
**Purpose**: Ad-free YouTube audio player + Google playlist sync

## Tech Stack
- **Flutter**: 3.47.0
- **Dart**: 3.13.0 (SDK ^3.13.0)
- **Platform**: Windows (primary), Android (for testing)

### Key Packages
| Package | Version | Purpose |
|---------|---------|---------|
| youtube_explode_dart | ^3.1.0 | Extracts audio stream URLs from YouTube |
| just_audio | ^0.9.46 | Plays audio streams (ExoPlayer on Android) |
| google_sign_in | ^7.2.0 | Google authentication (v7 API) |
| googleapis | ^17.0.0 | YouTube Data API v3 |
| googleapis_auth | ^2.3.3 | OAuth2 authenticated HTTP clients |
| extension_google_sign_in_as_googleapis_auth | ^3.0.0 | Bridges google_sign_in with googleapis |
| rxdart | ^0.28.0 | Reactive streams |
| http | ^1.2.0 | HTTP client |
| shared_preferences | ^2.3.3 | Persistent settings storage |
| flutter_colorpicker | ^1.1.0 | Accent color picker |
| flutter_lints | ^6.0.0 | Lint rules |

## File Structure
```
lib/
├── main.dart                          # Full UI: HomeScreen with BottomNavigationBar
│   ├── FinAudioApp                    # App root with theme, settings init, player/auth services
│   ├── _MainScaffold                  # Bottom nav: Player, Playlists, Settings tabs
│   ├── PlayerTab                      # Paste YouTube URL → plays audio. Seek bar, transport, queue
│   ├── PlaylistsTab                   # Google Sign-In → liked videos + search → tap to play
│   ├── _ControlButton                 # Reusable transport button (accepts Widget icon)
│   ├── _NowPlayingHero                # Now-playing cover art + title/author card
│   ├── _UpNextSection/_UpNextChip     # Horizontal queue display
│   ├── _AuthSection                   # Sign-in/sign-out UI for playlists
│   └── _MusicListTile                 # Video list tile with thumbnail + play button
├── services/
│   ├── player_service.dart            # Centralized playback: AudioPlayer + queue + loop
│   │   ├── Track                      # id, title, author, youtubeUrl, streamUrl, duration
│   │   ├── LoopMode                   # off, one, all
│   │   └── PlayerService             # Owns AudioPlayer + YoutubeService, manages queue
│   ├── youtube_service.dart           # YoutubeExplode: URL → audio stream URL
│   │   └── ResolvedVideo             # title, author, duration, videoUrl, audioStreamUrl
│   └── youtube_stream_source.dart     # Custom StreamAudioSource bypassing ExoPlayer's HTTP layer
│   ├── google_auth_service.dart       # Google Sign-In v7 + YouTube Data API v3
│   │   ├── PlaylistVideo             # videoId, title, channelTitle, thumbnailUrl, duration
│   │   └── GoogleAuthService          # signIn, signOut, fetchLikedVideos, searchMusic
│   └── settings_service.dart          # Persistent accent color + dark intensity via SharedPreferences
├── ui/
│   └── settings_screen.dart           # Settings: dark intensity, accent color picker, about
└── widgets/
    └── now_playing_bar.dart           # Compact now-playing bar (shown above bottom nav)
test/
└── widget_test.dart                   # Smoke test: verifies Player/Playlists tabs render
```

## Architecture

### PlayerService (lib/services/player_service.dart)
- Central playback engine used by both PlayerTab and PlaylistsTab
- Owns `AudioPlayer` (from just_audio) and `YoutubeService`
- **position** and **duration** tracked via internal stream listeners (`_position`, `_duration` fields), NOT via AudioPlayer getters
- `isPlaying` checks `_player.playing`
- All playback goes through `_playTrack(Track)` which uses `YouTubeStreamSource` (Dart HTTP) to send proper headers to YouTube's CDN
- Queue management: `play()`, `playList()`, `togglePlayPause()`, `stop()`, `replay()`, `cycleLoopMode()`, `seek()`
- `onTrackEnd()` handles loop/queue advancement — wired to `processingStateStream` (fires when `ProcessingState.completed`)

### Track class
- Fields: `id`, `title`, `author`, `youtubeUrl`, `streamUrl`, `duration`
- No `isNotEmpty` getter — use `id.isNotEmpty` to check if a track has valid data

### YoutubeService (lib/services/youtube_service.dart)
- Uses `YoutubeExplode` to resolve YouTube URLs
- Extracts audio-only stream with `manifest.audioOnly.withHighestBitrate()`
- Prefers AAC/M4A streams for maximum compatibility
- Forces HTTPS on returned stream URLs to avoid Android cleartext HTTP restrictions
- Retry logic: Up to 2 retries on timeout errors

### YouTubeStreamSource (lib/services/youtube_stream_source.dart)
- Custom `StreamAudioSource` that bypasses ExoPlayer's built-in HTTP layer
- Uses Dart's `HttpClient` to send proper headers (User-Agent, Referer) to YouTube's CDN
- ExoPlayer's `DefaultHttpDataSource` silently drops custom headers, causing YouTube to return 403
- Handles byte-range requests for seeking support

### GoogleAuthService (lib/services/google_auth_service.dart)
- Google Sign-In v7 API: uses `authenticate()` not `signIn()`
- Requires Web OAuth client ID as `serverClientId`
- Access token wrapped in `auth.AccessToken('Bearer', token, expiry)` for googleapis_auth
- YouTube Data API v3: `fetchLikedVideos()`, `fetchPlaylistVideos()`, `searchMusic()`
- **Important**: `search.list` `type` parameter is `List<String>?`, use `type: ['video']`

### SettingsService (lib/services/settings_service.dart)
- Non-singleton: each consumer creates its own instance
- Persists via SharedPreferences: accent color (hex string), dark intensity (int 0-2)
- Predefined dark intensity presets: Soft dark (0), Default (1), Deep black (2)

### UI Widgets
- **_ControlButton**: accepts `Widget icon` (not `IconData`). Wrap `Icon(...)` widgets.
- **NowPlayingBar**: Public wrapper class in `widgets/now_playing_bar.dart`. Use `NowPlayingBar`, not `_NowPlayingBar`.
- **SettingsScreen**: Creates its own `SettingsService()` instance locally.

## Google Cloud Setup (Already Done)
- **Project**: "FinAudio" on Google Cloud Console
- **YouTube Data API v3**: Enabled
- **Two OAuth client IDs**:
  1. Android client ID (SHA-1 fingerprint + package `com.example.finaudio`)
  2. Web client ID (used as `serverClientId` in code)
- **Web client ID location**: `google_auth_service.dart` as `_serverClientId`

## Current Status
### ✅ Working
- `flutter analyze` passes with zero errors (info-level deprecation hints only)
- `flutter test` passes
- Player tab: paste URL → resolves audio stream → plays via just_audio
- Playlists tab: Google Sign-In → fetch liked videos → search YouTube → tap to play
- Settings tab: dark intensity presets, accent color picker (presets + full ColorPicker)
- Now-playing bar at bottom when track is loaded
- Transport controls: play/pause, replay, seek bar, loop mode (off/one/all)
- Queue management: up-next display, remove from queue

### Android Configuration
- **AndroidManifest.xml**: `android:usesCleartextTraffic="true"` + `android:networkSecurityConfig` to allow HTTP for local network IPs (YouTube CDN sometimes resolves to local cache)
- **network_security_config.xml**: Permits cleartext only to `127.0.0.1`, `10.0.0.2`, and `localhost`

### ⚠️ Known Issues
1. **Google Sign-In verification**: Requires Google Cloud Console verification for production. For testing:
   - Go to Google Cloud Console → APIs & Services → OAuth consent screen
   - Set Publishing status to "Testing" (not In Production)
   - Add test email as a Test user

2. **YouTube stream resolution**: Some videos may need JS solver (DenoEJSSolver) for signature solving

3. **StreamAudioSource is experimental**: `just_audio` marks `StreamAudioSource` as experimental — monitor for breaking changes in future `just_audio` updates

4. **Deprecated Color properties**: `settings_service.dart` and `settings_screen.dart` use deprecated `.alpha`/`.red`/`.green`/`.blue` — should migrate to `.a`/`.r`/`.g`/`.b`

## Code Conventions
- Uses `flutter_lints` package for lint rules
- Analysis excludes build/, android/, ios/, web/, windows/, macos/, linux/
- Material 3 design with deep purple color scheme
- Dark theme support based on system setting

## Testing
- Basic widget test in `test/widget_test.dart` — verifies Player and Playlists tabs render

## Next Steps / TODOs
1. ~~Wire `AudioPlayer.onPlayerComplete` → `PlayerService.onTrackEnd()` for auto-advance~~ — Done
2. ~~Fix audio playback on Android (403/cleartext/streaming errors)~~ — Done: custom `YouTubeStreamSource` bypasses ExoPlayer HTTP layer
3. Implement persistent queue across app restarts
4. Add signature solving (DenoEJSSolver) for videos that need it
5. Migrate deprecated Color properties (`.alpha`→`.a`, `.red`→`.r`, etc.)
6. Add loading states and better UI feedback
7. Consider adding playlist queue management UI
8. Add offline caching for frequently played songs

## Build & Run
```bash
# Windows
flutter run -d windows

# Android
flutter run -d android

# Analyze
flutter analyze

# Test
flutter test
```

## Environment Variables / Secrets
- Web OAuth client ID is hardcoded in `google_auth_service.dart` as `_serverClientId`
- No .env file currently used
