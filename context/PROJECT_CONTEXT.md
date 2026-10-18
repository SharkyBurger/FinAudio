# FinAudio - Project Context Document

## Overview
**Name**: FinAudio  
**Path**: `C:\Users\Ethan John\Documents\FinAudio\finaudio`  
**Type**: Flutter mobile app  
**Version**: 1.0.0+1  
**Purpose**: Ad-free YouTube audio player with Google playlist sync, rock-solid background audio playback, minimal mobile data usage (<1 MB/min via raw audio streaming), native Android media notification controls, independent in-app volume, and deep theme customization.

---

## Tech Stack
- **Flutter**: 3.47.0
- **Dart**: 3.13.0 (SDK ^3.13.0)
- **Target Platform**: Android (Physical devices & emulators), Windows (secondary)

### Key Packages
| Package | Version | Purpose |
|---------|---------|---------|
| `media_kit` | ^1.2.6 | High-performance, cross-platform audio player powered by native `libmpv` |
| `media_kit_libs_audio` | ^1.0.7 | Audio binaries for `libmpv` |
| `audio_service` | ^0.18.19 | Android Foreground Service, MediaSession, lock screen & notification player panel |
| `youtube_explode_dart` | ^3.1.0 | Fast YouTube search, metadata resolution, and direct audio-only stream extraction |
| `ytmusicapi_dart` | ^2.4.1 | InnerTube YouTube Music API client for search, playlists, catalogs, and recommendations |
| `google_sign_in` | ^7.2.0 | Google authentication (v7 API with lightweight silent session restoration) |
| `rxdart` | ^0.28.0 | Reactive streams for player state & UI bindings |
| `shared_preferences` | ^2.3.3 | Persistent settings (32-bit ARGB colors, dark intensity, app volume) |
| `flutter_colorpicker` | ^1.1.0 | UI theme color picker |
| `flutter_lints` | ^6.0.0 | Lint rules |

---

## File Structure
```
lib/
├── main.dart                          # App entry point, MediaKit.ensureInitialized(), reactive theme builder, 4-tab MainScaffold
│   ├── FinAudioApp                    # App root, initializes Settings, GoogleAuthService, PlayerService, AudioHandler
│   ├── _MainScaffold                  # Bottom nav (Player, Search, Playlists, Settings) + NowPlayingBar
│   ├── PlayerTab                      # Direct URL / query input, now-playing card, seek bar, queue view, volume row
│   ├── SearchTab                      # Dedicated music search page with query debounce & result list
│   ├── PlaylistsTab                   # Google YouTube playlists browser & PlaylistDetailScreen navigator
│   └── PlaylistDetailScreen           # Playlist track list, full queue loading, track selection
├── services/
│   ├── audio_handler.dart             # FinAudioHandler (BaseAudioHandler): MediaSession, notification controls
│   ├── player_service.dart            # Central playback engine (media_kit Player, queue, shuffle, loop, volume)
│   │   ├── Track                      # Track metadata (id, title, author, youtubeUrl, duration, streamUrl)
│   │   ├── LoopMode                   # off, one, all
│   │   └── PlayerService              # Playback methods, queue management, shuffle toggle, loop cycle, volume
│   ├── youtube_service.dart           # Fast search, metadata resolution, InnerTube catalog, and audio stream extraction
│   ├── google_auth_service.dart       # Google Sign-In v7 + session persistence + InnerTube (YTMusic) catalog
│   │   ├── UserPlaylist               # id, title, description, thumbnailUrl, videoCount
│   │   ├── PlaylistVideo              # videoId, title, channelTitle, thumbnailUrl, duration
│   │   └── GoogleAuthService          # ChangeNotifier: auto-restore session, signIn, signOut, fetchPlaylists, searchMusic
│   └── settings_service.dart          # Persistent 4-color theme engine, 32-bit ARGB storage, volume persistence, presets
├── ui/
│   ├── appearance_screen.dart         # Dedicated theme & appearance screen: live preview, 7 presets, 4-color custom pickers
│   ├── now_playing_screen.dart        # Fullscreen expandable now-playing player with lyrics/queue tabs & volume slider
│   └── settings_screen.dart           # Streamlined settings tab: Google account profile, Theme navigation tile, App info
└── widgets/
    └── now_playing_bar.dart           # Floating mini-player bar docked above bottom navigation
test/
└── widget_test.dart                   # Unit tests for Track model, volume persistence, and SettingsService theme persistence
android/
├── app/src/main/
│   ├── AndroidManifest.xml            # Permissions (WAKE_LOCK, FOREGROUND_SERVICE), AudioService & MediaButtonReceiver
│   └── kotlin/.../MainActivity.kt     # Extends AudioServiceActivity, manages clean back-press task minimization
```

---

## Core Architecture & Key Implementations

### 1. Audio Playback Engine (`player_service.dart` & `youtube_service.dart`)
- **Engine**: Native `media_kit` backed by `libmpv` (via `media_kit_libs_android_audio`).
- **Why WebViews Paused in Background & How media_kit Solves It**:
  - In Flutter on Android, `PlatformView` / `webview_flutter` uses Texture Layer Hybrid Composition (`ImageReader`). When an activity moves to the background or the screen locks, Android WindowManager detaches the window surface (`disconnectFromSurface`). Chromium detects this surface loss and immediately terminates hardware audio/video decoders (`Codec released`, `AAudioStream_requestStop`, `AAudioStream_close`), regardless of any activity lifecycle overrides.
  - `media_kit` (`libmpv.so`) runs directly in C, communicates with OpenSL ES / AAudio without requiring any View or Surface, and operates reliably inside the background process.
- **Mobile Data Saver Optimization**:
  - `youtube_service.dart` extracts direct audio-only streams (Opus/AAC ~128 kbps) via `youtube_explode_dart`.
  - Zero video frames are requested, downloaded, or decoded, restricting consumption to < 1 MB per minute of playback.
  - HTTP headers (`User-Agent`, `Referer: https://www.youtube.com/`) are attached to stream requests to prevent 403 Forbidden CDN blocks.
- **Queue & Shuffling**:
  - `playVideos(videos, startIndex)`: Loads entire playlist into queue starting at chosen song.
  - `toggleShuffle()` / `setShuffle(bool)`: Preserves currently playing song at index 0 and randomizes remaining queue. Restores original order when untoggled.
  - `cycleLoopMode()` / `setLoopMode(mode)`: Cycles between `off`, `one` (repeat single song), and `all` (repeat queue).
  - Auto-advance: Automatically plays next song in queue when current track completes.
- **Independent In-App Volume Control**:
  - Controls playback volume natively via `_player.setVolume((_volume * 100).toDouble())` (0.0 to 1.0).
  - Users can lower or mute FinAudio audio directly without reducing system notification, ringtone, or other app volumes.
  - Persisted across restarts in `SettingsService` (`app_volume`) and automatically restored on startup and track transitions.
  - Accessible via responsive sliders and tap-to-mute buttons in both `NowPlayingScreen` and `PlayerTab`.
- **Media3 / ExoPlayer-Grade Instant Switching & Preloading**:
  - **Immediate Audio Cutoff**: Calling track switches immediately invokes `await _player.stop()`, resets playback position to zero, and updates the now-playing UI synchronously so previous tracks do not linger while resolving the next stream.
  - **Cancellation Tokens & Session IDs**: Each play request increments `_playSessionId`. In-flight asynchronous resolutions from rapidly skipped tracks detect stale sessions (`_playSessionId != session`) and discard themselves, completely preventing out-of-order audio race conditions.
  - **In-Memory Stream Cache**: Resolved stream URLs and metadata are cached in `_streamCache` for up to 4 hours, eliminating network roundtrips when replaying or switching back and forth.
  - **In-Flight Future Deduplication**: `_resolveOrFetch` consolidates concurrent requests for the same track ID into a single shared network future.
  - **Background Lookahead Preloading**: `_preloadQueue` proactively resolves streams for the next 1–2 tracks in the active queue in the background. Subsequent skips play immediately with near-zero latency.
  - **Proxy Connection Pooling & Redirect Preservation**: `StreamProxyService` maintains persistent HTTP keep-alive connections (`idleTimeout: 60s`, `maxConnectionsPerHost: 10`), flushes data chunks immediately (`bufferOutput = false`), manually follows 302 redirects without dropping `Range` or rewriting `User-Agent` to Dart's default, handles `HEAD` requests safely without response body errors, and wires `onStreamExpired` to auto-recover from 403/410 errors transparently.
- **Layout Robustness**:
  - Transport controls use dynamic `MainAxisAlignment.spaceEvenly` to guarantee zero pixel overflow on narrow 360dp mobile screens.

### 2. Background Playback & Notification Controls (`MainActivity.kt` & `audio_handler.dart`)
- **Android Foreground Service**:
  - `AndroidManifest.xml` declares `com.ryanheise.audioservice.AudioService` with `android:foregroundServiceType="mediaPlayback"`.
  - Permissions: `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, and `POST_NOTIFICATIONS`.
- **Decoupled Lifecycle**:
  - The native audio decoder in `libmpv` is completely independent of Android Views or Surfaces.
  - Minimizing the app or locking the screen has zero impact on audio playback.
  - `MainActivity.kt` calls `moveTaskToBack(true)` on back press, keeping the activity alive in the background without restarting.
- **MediaSession & Notification Bar**:
  - `FinAudioHandler` seamlessly mirrors playback state to Android's `MediaSessionCompat` and system notification shade with interactive play, pause, next, previous, seek, shuffle, and repeat controls.

### 3. Theme & Appearance Engine (`settings_service.dart` & `appearance_screen.dart`)
- **4-Color Customization**:
  - `backgroundColor`: Overall scaffold and backdrop.
  - `surfaceColor`: Card containers, dialogs, sheets, and bottom navigation bar.
  - `accentColor`: Primary buttons, active playback seek bars, highlights, and selection indicators.
  - `textColor`: Headings and primary titles, with automatic contrast-aware muted/dim body variations.
- **Reliable Persistence**:
  - Colors are stored directly as clean 32-bit ARGB integers via `toARGB32()` in `SharedPreferences`, resolving previous string encoding/decoding substring mismatch bugs.
  - `SettingsService.init()` is awaited in `main()` before calling `runApp()`, preventing launch color flicker and race conditions.
  - Extends `ChangeNotifier` to broadcast instant theme updates across all screens without reloading.
- **Interactive Live Preview**:
  - `AppearanceScreen` displays a real-time mock music card showing track title, artist, seek slider, play button, and sample elevated button styled with the user's active theme.
- **Curated Presets**:
  - 7 one-tap coordinated palettes: **YouTube Classic**, **Pure OLED**, **Midnight Ocean**, **Emerald Cyber**, **Sunset Glow**, **Neon Pink**, and **Monochrome Slate**.
  - Instant "Reset All to Defaults" feature.
- **Streamlined Settings Navigation**:
  - `SettingsScreen` has a dedicated **Theme & Appearance** navigation tile displaying live mini color dots that opens `AppearanceScreen`.

---

## Google Cloud Configuration
- **Project**: "FinAudio" on Google Cloud Console
- **APIs**: YouTube Data API v3 enabled
- **Client IDs**:
  - Android Client ID: SHA-1 fingerprint registered for package `com.example.finaudio`
  - Web Client ID: Configured in `google_auth_service.dart` as `_serverClientId`

---

## Build & Run Instructions
```bash
# Analyze code
flutter analyze

# Run on connected Android device
flutter run -d android

# Run tests
flutter test

# Native Android debug build
cd android && gradlew.bat assembleDebug
```
