import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finaudio/models/local_playlist.dart';
import 'package:finaudio/services/audio_handler.dart';
import 'package:finaudio/services/settings_service.dart';
import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/playlist_service.dart';
import 'package:finaudio/services/spotify_service.dart';
import 'package:finaudio/services/google_auth_service.dart';
import 'package:finaudio/services/youtube_service.dart';
import 'package:finaudio/services/stream_proxy_service.dart';
import 'package:finaudio/services/download_service.dart';
import 'package:finaudio/services/discord_rpc_service.dart';
import 'package:finaudio/services/crash_log_service.dart';
import 'package:finaudio/widgets/now_playing_bar.dart';
import 'package:finaudio/ui/home_screen.dart';
import 'package:finaudio/ui/now_playing_screen.dart';
import 'package:finaudio/ui/settings_screen.dart';
import 'package:finaudio/ui/library_screen.dart';
import 'package:finaudio/ui/artist_screen.dart';
import 'package:finaudio/ui/downloads_screen.dart';
import 'package:finaudio/models/search_result.dart';
import 'package:finaudio/widgets/add_to_playlist_sheet.dart';
import 'package:finaudio/widgets/artist_picker_sheet.dart';
import 'package:finaudio/widgets/google_sign_in_dialog.dart';

AudioHandler? audioHandler;

void _initMediaKit() {
  String? mpvPath;
  if (!kIsWeb && Platform.isWindows) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir\\libmpv-2.dll',
      r'build\windows\x64\runner\Debug\libmpv-2.dll',
      r'build\windows\x64\runner\Release\libmpv-2.dll',
      r'build\windows\x64\libmpv\libmpv-2.dll',
      r'build\windows\runner\Debug\libmpv-2.dll',
      r'build\windows\runner\Release\libmpv-2.dll',
      r'build\windows\libmpv\libmpv-2.dll',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) {
        mpvPath = File(c).absolute.path;
        break;
      }
    }
  }
  MediaKit.ensureInitialized(libmpv: mpvPath);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CrashLogService.instance.init();

  try {
    _initMediaKit();
  } catch (e, st) {
    debugPrint('MediaKit initialization error: $e');
    CrashLogService.instance.logCrash(e, st, reason: 'MediaKit initialization');
  }

  try {
    await StreamProxyService.instance.ensureStarted();
  } catch (e, st) {
    debugPrint('StreamProxyService startup error: $e');
    CrashLogService.instance.logCrash(e, st, reason: 'StreamProxyService startup');
  }

  final settings = SettingsService();
  try {
    await settings.init();
  } catch (e, st) {
    debugPrint('SettingsService init error: $e');
    CrashLogService.instance.logCrash(e, st, reason: 'SettingsService init');
  }

  try {
    audioHandler = await AudioService.init(
      builder: () => FinAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.finaudio.channel.audio',
        androidNotificationChannelName: 'FinAudio Playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'drawable/ic_bg_service_small',
        androidShowNotificationBadge: true,
      ),
    );
  } catch (e, st) {
    debugPrint('AudioService init error: $e');
    CrashLogService.instance.logCrash(e, st, reason: 'AudioService.init');
  }

  runApp(FinAudioApp(audioHandler: audioHandler, settingsService: settings));
}

// ======================================================================
// App root
// ======================================================================

class FinAudioApp extends StatefulWidget {
  final AudioHandler? audioHandler;
  final SettingsService? settingsService;
  const FinAudioApp({super.key, this.audioHandler, this.settingsService});

  @override
  State<FinAudioApp> createState() => _FinAudioAppState();
}

class _FinAudioAppState extends State<FinAudioApp> {
  late final SettingsService _settings;
  late final PlayerService _playerService;
  late final GoogleAuthService _authService;
  late final PlaylistService _playlistService;

  @override
  void initState() {
    super.initState();
    _settings = widget.settingsService ?? SettingsService();
    _playerService = PlayerService(
      initialVolume: _settings.appVolume,
      onVolumeChanged: (vol) => _settings.setAppVolume(vol),
      settingsService: _settings,
    );
    _authService = GoogleAuthService();
    _playlistService = PlaylistService();
    final handler = widget.audioHandler;
    if (handler is FinAudioHandler) {
      handler.attachPlayerService(_playerService);
    }
    DiscordRpcService.instance.attach(
      playerService: _playerService,
      settingsService: _settings,
    );
    _settings.addListener(_onSettingsChange);
    _init();
  }

  void _onSettingsChange() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    if (widget.settingsService == null) {
      await _settings.init();
      _playerService.setVolume(_settings.appVolume);
    }
    await _playlistService.init();
    await _authService.initialize();
    await DownloadService.instance.init();
  }

  ThemeData _buildTheme() {
    final bg = _settings.backgroundColor;
    final surface = _settings.surfaceColor;
    final accent = _settings.accentColor;
    final text = _settings.textColor;
    final onAccent = _onPrimaryFor(accent);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.dark(
        primary: accent,
        onPrimary: onAccent,
        primaryContainer: accent.withAlpha(40),
        onPrimaryContainer: accent,
        secondary: accent.withAlpha(220),
        tertiary: accent.withAlpha(160),
        outline: text.withAlpha(90),
        outlineVariant: text.withAlpha(40),
        surface: surface,
        onSurface: text,
        surfaceContainerHighest: surface,
        error: const Color(0xFFCF6679),
        shadow: Colors.transparent,
      ),
      textTheme: _textThemeFor(text),
      dividerTheme: DividerThemeData(
        color: text.withAlpha(30),
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: text),
      ),
      iconTheme: IconThemeData(
        color: text.withAlpha(180),
        size: 24,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: text.withAlpha(40)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: text.withAlpha(100)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: text.withAlpha(60)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withAlpha(60),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.w600);
          }
          return TextStyle(color: text.withAlpha(140), fontSize: 12);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accent);
          }
          return IconThemeData(color: text.withAlpha(140));
        }),
      ),
    );
  }

  Color _onPrimaryFor(Color accent) {
    if (accent.computeLuminance() > 0.5) {
      return const Color(0xFF101010);
    }
    return const Color(0xFFFFFFFF);
  }

  TextTheme _textThemeFor(Color text) {
    final base = ThemeData.dark().textTheme;
    final mutedColor = text.withAlpha(170);
    final dimColor = text.withAlpha(110);

    return base.apply(
      bodyColor: text,
      displayColor: text,
    ).copyWith(
      bodyLarge: base.bodyLarge?.copyWith(color: text),
      bodyMedium: base.bodyMedium?.copyWith(color: text),
      bodySmall: base.bodySmall?.copyWith(color: mutedColor),
      labelLarge: base.labelLarge?.copyWith(color: text),
      labelMedium: base.labelMedium?.copyWith(color: mutedColor),
      labelSmall: base.labelSmall?.copyWith(color: dimColor),
      titleLarge: base.titleLarge?.copyWith(color: text),
      titleMedium: base.titleMedium?.copyWith(color: text),
      titleSmall: base.titleSmall?.copyWith(color: mutedColor),
      headlineMedium: base.headlineMedium?.copyWith(color: text),
      headlineSmall: base.headlineSmall?.copyWith(color: text),
    );
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChange);
    DiscordRpcService.instance.dispose();
    _playerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinAudio',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      themeMode: ThemeMode.dark,
      home: _MainScaffold(
        accentColor: _settings.accentColor,
        playerService: _playerService,
        authService: _authService,
        playlistService: _playlistService,
        settingsService: _settings,
        onSettingsChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }
}

// ======================================================================
// Main scaffold
// ======================================================================

class _MainScaffold extends StatefulWidget {
  final Color accentColor;
  final PlayerService playerService;
  final GoogleAuthService authService;
  final PlaylistService playlistService;
  final SettingsService settingsService;
  final VoidCallback onSettingsChanged;

  const _MainScaffold({
    required this.accentColor,
    required this.playerService,
    required this.authService,
    required this.playlistService,
    required this.settingsService,
    required this.onSettingsChanged,
  });

  @override
  State<_MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<_MainScaffold> {
  int _currentIndex = 0;
  Track? _nowPlaying;
  StreamSubscription<Track?>? _trackSub;

  @override
  void initState() {
    super.initState();
    _trackSub = widget.playerService.nowPlayingStream.listen((track) {
      if (mounted) {
        setState(() => _nowPlaying = track);
      }
    });
    widget.settingsService.addListener(_onSettingsChange);
    widget.authService.addListener(_onSettingsChange);
    widget.playlistService.addListener(_onSettingsChange);
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    widget.settingsService.removeListener(_onSettingsChange);
    widget.authService.removeListener(_onSettingsChange);
    widget.playlistService.removeListener(_onSettingsChange);
    super.dispose();
  }

  void _onSettingsChange() {
    if (mounted) setState(() {});
  }

  List<Widget> _buildContentTabs(Color accentColor) {
    return [
      HomeTab(
        playerService: widget.playerService,
        authService: widget.authService,
        playlistService: widget.playlistService,
        settingsService: widget.settingsService,
        onOpenPlaylists: () => setState(() => _currentIndex = 2),
        onOpenSearch: () => setState(() => _currentIndex = 1),
        onOpenSettings: () => setState(() => _currentIndex = 3),
        onOpenPlaylistDetail: (playlist) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LocalPlaylistDetailScreen(
                playlist: playlist,
                playerService: widget.playerService,
                playlistService: widget.playlistService,
                settingsService: widget.settingsService,
                authService: widget.authService,
              ),
            ),
          );
        },
      ),
      SearchTab(
        playerService: widget.playerService,
        authService: widget.authService,
        playlistService: widget.playlistService,
        settingsService: widget.settingsService,
        accentColor: accentColor,
      ),
      LibraryTab(
        playerService: widget.playerService,
        authService: widget.authService,
        playlistService: widget.playlistService,
        settingsService: widget.settingsService,
        onGoToSettings: () => setState(() => _currentIndex = 3),
        onGoToPlayer: () => setState(() => _currentIndex = 0),
        onOpenPlaylistDetail: (playlist) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LocalPlaylistDetailScreen(
                playlist: playlist,
                playlistService: widget.playlistService,
                playerService: widget.playerService,
                settingsService: widget.settingsService,
                authService: widget.authService,
              ),
            ),
          );
        },
        onOpenYtPlaylistDetail: (playlist) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(
                playlist: playlist,
                playerService: widget.playerService,
                authService: widget.authService,
                playlistService: widget.playlistService,
              ),
            ),
          );
        },
      ),
      SettingsScreen(
        key: const ValueKey('settings'),
        settingsService: widget.settingsService,
        authService: widget.authService,
        onChanged: widget.onSettingsChanged,
        onAuthChanged: () => setState(() {}),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.settingsService.accentColor;
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final contentTabs = _buildContentTabs(accentColor);

    if (isDesktop) {
      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  _DesktopSidebar(
                    currentIndex: _currentIndex,
                    onDestinationSelected: (i) => setState(() => _currentIndex = i),
                    accentColor: accentColor,
                    authService: widget.authService,
                    playlistService: widget.playlistService,
                    settingsService: widget.settingsService,
                    onOpenPlaylistDetail: (playlist) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LocalPlaylistDetailScreen(
                            playlist: playlist,
                            playlistService: widget.playlistService,
                            playerService: widget.playerService,
                            settingsService: widget.settingsService,
                            authService: widget.authService,
                          ),
                        ),
                      );
                    },
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                    child: IndexedStack(
                      index: _currentIndex.clamp(0, 3),
                      children: contentTabs,
                    ),
                  ),
                ],
              ),
            ),
            DesktopPlayerBar(
              track: _nowPlaying,
              accentColor: accentColor,
              playerService: widget.playerService,
              authService: widget.authService,
              playlistService: widget.playlistService,
              settingsService: widget.settingsService,
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex.clamp(0, 3),
          children: contentTabs,
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_nowPlaying != null)
              NowPlayingBar(
                track: _nowPlaying!,
                accentColor: accentColor,
                playerService: widget.playerService,
                authService: widget.authService,
                playlistService: widget.playlistService,
                settingsService: widget.settingsService,
              ),
            NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (i) => setState(() => _currentIndex = i),
              elevation: 0,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search_rounded),
                  label: 'Search',
                ),
                NavigationDestination(
                  icon: Icon(Icons.local_library_outlined),
                  selectedIcon: Icon(Icons.local_library_rounded),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Color accentColor;
  final GoogleAuthService authService;
  final PlaylistService playlistService;
  final SettingsService settingsService;
  final ValueChanged<LocalPlaylist> onOpenPlaylistDetail;

  const _DesktopSidebar({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.accentColor,
    required this.authService,
    required this.playlistService,
    required this.settingsService,
    required this.onOpenPlaylistDetail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final text = theme.colorScheme.onSurface;
    final user = authService.currentUser;
    final isSignedIn = authService.isSignedIn && user != null;

    final likedSongs = playlistService.likedSongsPlaylist;
    final otherPlaylists = playlistService.playlists
        .where((p) => p.id != PlaylistService.likedSongsId)
        .toList();

    return Container(
      width: 240,
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo & Branding
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accentColor.withAlpha(70)),
                  ),
                  child: Center(
                    child: Icon(Icons.graphic_eq_rounded, color: accentColor, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FinAudio',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: text,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Desktop Player',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Main Navigation
          _SidebarItem(
            icon: currentIndex == 0 ? Icons.home_rounded : Icons.home_outlined,
            label: 'Home',
            isSelected: currentIndex == 0,
            accentColor: accentColor,
            onTap: () => onDestinationSelected(0),
          ),
          _SidebarItem(
            icon: currentIndex == 1 ? Icons.search_rounded : Icons.search_outlined,
            label: 'Search',
            isSelected: currentIndex == 1,
            accentColor: accentColor,
            onTap: () => onDestinationSelected(1),
          ),
          _SidebarItem(
            icon: currentIndex == 2 ? Icons.local_library_rounded : Icons.local_library_outlined,
            label: 'Library',
            isSelected: currentIndex == 2,
            accentColor: accentColor,
            onTap: () => onDestinationSelected(2),
          ),
          _SidebarItem(
            icon: currentIndex == 3 ? Icons.settings_rounded : Icons.settings_outlined,
            label: 'Settings',
            isSelected: currentIndex == 3,
            accentColor: accentColor,
            onTap: () => onDestinationSelected(3),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(height: 1),
          ),

          // Library Playlists Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text(
                  'YOUR PLAYLISTS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  tooltip: 'Create Playlist',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => _showCreatePlaylistDialog(context),
                ),
              ],
            ),
          ),

          // Liked Songs Item
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onOpenPlaylistDetail(likedSongs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: LinearGradient(
                            colors: [accentColor, accentColor.withAlpha(160)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.favorite_rounded, color: Colors.black, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Liked Songs',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: text,
                              ),
                            ),
                            Text(
                              '${likedSongs.tracks.length} tracks',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Scrollable Playlists
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              itemCount: otherPlaylists.length,
              itemBuilder: (context, i) {
                final p = otherPlaylists[i];
                return Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onOpenPlaylistDetail(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.queue_music_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: text.withAlpha(220),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Bottom Account Tile / Google Login
          Padding(
            padding: const EdgeInsets.all(12),
            child: isSignedIn
                ? Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        if (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: NetworkImage(user.photoUrl!),
                          )
                        else
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: accentColor.withAlpha(40),
                            child: Icon(Icons.person, color: accentColor, size: 18),
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.displayName ?? 'YouTube User',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: text,
                                ),
                              ),
                              Text(
                                user.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                          onSelected: (val) async {
                            if (val == 'settings') {
                              onDestinationSelected(3);
                            } else if (val == 'signout') {
                              await authService.signOut();
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'settings',
                              child: Text('Account Settings'),
                            ),
                            const PopupMenuItem(
                              value: 'signout',
                              child: Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      showGoogleSignInDialog(
                        context: context,
                        authService: authService,
                        accentColor: accentColor,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: accentColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentColor.withAlpha(60)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_circle_outlined, color: accentColor, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sign in with Google',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: accentColor,
                                  ),
                                ),
                                Text(
                                  'Sync YouTube playlists',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: accentColor, size: 18),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await playlistService.createPlaylist(title: name);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: isSelected ? accentColor.withAlpha(35) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected ? accentColor : text.withAlpha(190),
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? accentColor : text.withAlpha(220),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// Player Tab — full music player UI
// ======================================================================

class PlayerTab extends StatefulWidget {
  final PlayerService playerService;
  final Color accentColor;

  const PlayerTab({
    super.key,
    required this.playerService,
    required this.accentColor,
  });

  @override
  State<PlayerTab> createState() => _PlayerTabState();
}

class _PlayerTabState extends State<PlayerTab> {
  final TextEditingController _queryController = TextEditingController();
  StreamSubscription<String>? _errorSub;
  StreamSubscription<Track?>? _trackSub;
  StreamSubscription<bool>? _shuffleSub;
  String? _error;

  @override
  void initState() {
    super.initState();
    _errorSub = widget.playerService.errorStream.listen((msg) {
      if (mounted) {
        setState(() => _error = msg);
      }
    });
    _trackSub = widget.playerService.nowPlayingStream.listen((_) {
      if (mounted) setState(() {});
    });
    _shuffleSub = widget.playerService.shuffleStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _trackSub?.cancel();
    _shuffleSub?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _playFromUrl() async {
    final input = _queryController.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Paste a YouTube URL or search for music.');
      return;
    }

    setState(() {
      _error = null;
    });

    try {
      await widget.playerService.play(input);
      _queryController.clear();
      setState(() {
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not resolve audio stream: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = widget.playerService.currentTrack;
    final queue = widget.playerService.queue;

    return SafeArea(
      child: Column(
        children: [
          // ---- Search bar (always at top) ----
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              controller: _queryController,
              decoration: InputDecoration(
                hintText: 'Paste a YouTube or Spotify URL…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _queryController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _queryController.clear();
                          setState(() => _error = null);
                        },
                      )
                    : null,
              ),
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _playFromUrl(),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // ---- Main content (scrolls) ----
          Expanded(
            child: track != null
                ? _buildPlayerView(track, queue, theme)
                : _buildEmptyState(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          Icon(
            Icons.headphones,
            size: 72,
            color: widget.accentColor.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing playing',
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF707070),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste a YouTube or Spotify link above to start',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF555555),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerView(Track track, List<Track> queue, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 16),

          // ---- Album art ----
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, _, _) => NowPlayingScreen(
                    playerService: widget.playerService,
                    accentColor: widget.accentColor,
                  ),
                  transitionsBuilder: (_, anim, _, child) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                      child: child,
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              );
            },
            child: _AlbumArt(
              track: track,
              accentColor: widget.accentColor,
            ),
          ),
          const SizedBox(height: 24),

          // ---- Title + artist ----
          Text(
            track.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            track.author,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),

          // ---- Seek bar ----
          _SeekBar(playerService: widget.playerService, accentColor: widget.accentColor),
          const SizedBox(height: 8),

          // ---- Transport controls ----
          _TransportControls(
            playerService: widget.playerService,
            accentColor: widget.accentColor,
          ),
          const SizedBox(height: 14),

          // ---- Independent In-App Volume Control ----
          _PlayerVolumeRow(
            playerService: widget.playerService,
            accentColor: widget.accentColor,
          ),
          const SizedBox(height: 20),

          // ---- Up next ----
          if (queue.length > 1)
            _UpNextSection(
              currentTrack: track,
              queue: queue,
              accentColor: widget.accentColor,
              onRemove: (id) => widget.playerService.removeFromQueue(id),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ======================================================================
// Album art
// ======================================================================

class _AlbumArt extends StatelessWidget {
  final Track track;
  final Color accentColor;

  const _AlbumArt({required this.track, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        color: accentColor.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
          ? Image.network(
              track.thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholderIcon(),
            )
          : (track.id.isNotEmpty && !track.id.startsWith('spotify:'))
              ? Image.network(
                  'https://img.youtube.com/vi/${track.id}/hqdefault.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _placeholderIcon(),
                )
              : _placeholderIcon(),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      color: accentColor.withAlpha(20),
      child: Icon(
        Icons.music_note,
        size: 80,
        color: accentColor.withAlpha(100),
      ),
    );
  }
}

// ======================================================================
// Seek bar with time labels
// ======================================================================

class _SeekBar extends StatelessWidget {
  final PlayerService playerService;
  final Color accentColor;

  const _SeekBar({required this.playerService, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<Duration>(
      stream: playerService.positionStream,
      initialData: playerService.position,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: playerService.durationStream,
          initialData: playerService.duration,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds > 0
                ? duration.inMilliseconds.toDouble()
                : 1.0;
            final posMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);

            return Column(
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: accentColor,
                    inactiveTrackColor: const Color(0xFF3A3A3A),
                    thumbColor: accentColor,
                    overlayColor: accentColor.withAlpha(50),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: posMs,
                    max: maxMs,
                    onChanged: (v) {
                      playerService.seek(Duration(milliseconds: v.toInt()));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(position),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _fmt(duration),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _fmt(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$min:$sec';
    return '$min:$sec';
  }
}

// ======================================================================
// Transport controls — shuffle | prev | play/pause | next | repeat
// ======================================================================

class _TransportControls extends StatelessWidget {
  final PlayerService playerService;
  final Color accentColor;

  const _TransportControls({
    required this.playerService,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shuffle
        StreamBuilder<bool>(
          stream: playerService.shuffleStream,
          initialData: playerService.shuffleEnabled,
          builder: (context, snap) {
            final enabled = snap.data ?? false;
            return IconButton(
              onPressed: () => playerService.toggleShuffle(),
              icon: Icon(
                Icons.shuffle,
                size: 22,
                color: enabled ? accentColor : const Color(0xFF888888),
              ),
              tooltip: 'Shuffle',
            );
          },
        ),

        const SizedBox(width: 12),

        // Previous
        IconButton(
          onPressed: () => playerService.previousTrack(),
          icon: const Icon(Icons.skip_previous_rounded, size: 32),
          tooltip: 'Previous',
        ),

        const SizedBox(width: 8),

        // Play / Pause (big center button)
        _PlayPauseButton(
          playerService: playerService,
          accentColor: accentColor,
        ),

        const SizedBox(width: 8),

        // Next
        IconButton(
          onPressed: () => playerService.nextTrack(),
          icon: const Icon(Icons.skip_next_rounded, size: 32),
          tooltip: 'Next',
        ),

        const SizedBox(width: 12),

        // Loop / repeat
        StreamBuilder<LoopMode>(
          stream: playerService.loopModeStream,
          initialData: playerService.loopMode,
          builder: (context, snap) {
            final mode = snap.data ?? LoopMode.off;
            return IconButton(
              onPressed: () => playerService.cycleLoopMode(),
              icon: Icon(
                _loopIcon(mode),
                size: 22,
                color: mode != LoopMode.off ? accentColor : const Color(0xFF888888),
              ),
              tooltip: 'Loop: ${_loopLabel(mode)}',
            );
          },
        ),
      ],
    );
  }

  IconData _loopIcon(LoopMode mode) => switch (mode) {
    LoopMode.off => Icons.repeat,
    LoopMode.one => Icons.repeat_one,
    LoopMode.all => Icons.repeat,
  };

  String _loopLabel(LoopMode mode) => switch (mode) {
    LoopMode.off => 'Off',
    LoopMode.one => 'One',
    LoopMode.all => 'All',
  };
}

// ======================================================================
// In-App Volume Control Row
// ======================================================================

class _PlayerVolumeRow extends StatefulWidget {
  final PlayerService playerService;
  final Color accentColor;

  const _PlayerVolumeRow({
    required this.playerService,
    required this.accentColor,
  });

  @override
  State<_PlayerVolumeRow> createState() => _PlayerVolumeRowState();
}

class _PlayerVolumeRowState extends State<_PlayerVolumeRow> {
  double? _dragVolume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<double>(
      stream: widget.playerService.volumeStream,
      initialData: widget.playerService.volume,
      builder: (context, snap) {
        final currentVol = (snap.data ?? widget.playerService.volume).clamp(0.0, 1.0);
        final volume = _dragVolume ?? currentVol;
        final percent = (volume * 100).round();

        final IconData icon = volume <= 0.01
            ? Icons.volume_off_rounded
            : volume < 0.5
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withAlpha(40),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => widget.playerService.toggleMute(),
                icon: Icon(
                  icon,
                  size: 20,
                  color: volume <= 0.01
                      ? theme.colorScheme.onSurfaceVariant.withAlpha(120)
                      : widget.accentColor,
                ),
                tooltip: volume <= 0.01 ? 'Unmute app audio' : 'Mute app audio',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: widget.accentColor,
                    inactiveTrackColor: theme.colorScheme.onSurface.withAlpha(30),
                    thumbColor: widget.accentColor,
                    overlayColor: widget.accentColor.withAlpha(40),
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) {
                      setState(() => _dragVolume = val);
                      widget.playerService.setVolume(val, persist: false);
                    },
                    onChangeEnd: (val) {
                      setState(() => _dragVolume = null);
                      widget.playerService.setVolume(val, persist: true);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 38,
                child: Text(
                  '$percent%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ======================================================================
// Play / Pause button (large, circular)
// ======================================================================

class _PlayPauseButton extends StatelessWidget {
  final PlayerService playerService;
  final Color accentColor;

  const _PlayPauseButton({
    required this.playerService,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: playerService.playingStream,
      initialData: playerService.isPlaying,
      builder: (context, snap) {
        final isPlaying = snap.data ?? false;
        return GestureDetector(
          onTap: () => playerService.togglePlayPause(),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accentColor.withAlpha(80),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 36,
              color: const Color(0xFFFFFFFF),
            ),
          ),
        );
      },
    );
  }
}

// ======================================================================
// Up next section (compact vertical list)
// ======================================================================

class _UpNextSection extends StatelessWidget {
  final Track? currentTrack;
  final List<Track> queue;
  final Color accentColor;
  final ValueChanged<String> onRemove;

  const _UpNextSection({
    required this.currentTrack,
    required this.queue,
    required this.accentColor,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nowPlaying = currentTrack;
    final upcoming = queue.where((t) => t.id != nowPlaying?.id).toList();

    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Up next (${upcoming.length})',
            style: theme.textTheme.labelLarge?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...upcoming.take(8).map((track) => _UpNextTile(
              track: track,
              accentColor: accentColor,
              onRemove: () => onRemove(track.id),
            )),
      ],
    );
  }
}

class _UpNextTile extends StatelessWidget {
  final Track track;
  final Color accentColor;
  final VoidCallback onRemove;

  const _UpNextTile({
    required this.track,
    required this.accentColor,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              'https://img.youtube.com/vi/${track.id}/hqdefault.jpg',
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 44,
                height: 44,
                color: accentColor.withAlpha(20),
                child: Icon(Icons.music_note, size: 20, color: accentColor.withAlpha(100)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFE6E6E6)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  track.author,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 16, color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Playlists Tab
// ======================================================================

// ======================================================================
// Search Tab — dedicated music search
// ======================================================================

class SearchTab extends StatefulWidget {
  final PlayerService playerService;
  final GoogleAuthService authService;
  final PlaylistService playlistService;
  final SettingsService settingsService;
  final Color accentColor;

  const SearchTab({
    super.key,
    required this.playerService,
    required this.authService,
    required this.playlistService,
    required this.settingsService,
    required this.accentColor,
  });

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  static const List<String> _categories = [
    'All',
    'Songs',
    'Videos',
    'Artists',
    'Albums',
    'Playlists',
  ];
  String _selectedCategory = 'All';

  UnifiedSearchResults _results = const UnifiedSearchResults();
  bool _loading = false;
  String? _error;

  static const String _kSearchHistoryKey = 'search_history_v1';
  List<String> _searchHistory = [];
  List<String> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    widget.playlistService.addListener(_onPlaylistUpdate);
    _loadSearchHistory();
  }

  @override
  void dispose() {
    widget.playlistService.removeListener(_onPlaylistUpdate);
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onPlaylistUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kSearchHistoryKey) ?? [];
      if (mounted) {
        setState(() {
          _searchHistory = list;
        });
      }
    } catch (e) {
      debugPrint('SearchTab: Failed to load search history ($e)');
    }
  }

  Future<void> _saveQueryToHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final updated = List<String>.from(_searchHistory);
      updated.removeWhere((item) => item.toLowerCase() == trimmed.toLowerCase());
      updated.insert(0, trimmed);
      if (updated.length > 25) {
        updated.removeRange(25, updated.length);
      }
      await prefs.setStringList(_kSearchHistoryKey, updated);
      if (mounted) {
        setState(() {
          _searchHistory = updated;
        });
      }
    } catch (e) {
      debugPrint('SearchTab: Failed to save search history ($e)');
    }
  }

  Future<void> _removeFromHistory(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updated = List<String>.from(_searchHistory)
        ..removeWhere((item) => item.toLowerCase() == query.toLowerCase());
      await prefs.setStringList(_kSearchHistoryKey, updated);
      if (mounted) {
        setState(() {
          _searchHistory = updated;
        });
      }
    } catch (e) {
      debugPrint('SearchTab: Failed to remove search history ($e)');
    }
  }

  Future<void> _clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSearchHistoryKey);
      if (mounted) {
        setState(() {
          _searchHistory = [];
        });
      }
    } catch (e) {
      debugPrint('SearchTab: Failed to clear search history ($e)');
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const UnifiedSearchResults();
        _suggestions = [];
        _showSuggestions = false;
        _loading = false;
        _error = null;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final sugg = await widget.playerService.youtubeService.getSearchSuggestions(query);
        if (mounted && _searchController.text.trim() == query) {
          setState(() {
            _suggestions = sugg;
            _showSuggestions = true;
          });
        }
      } catch (_) {}

      if (query.length >= 2) {
        _performSearch(query, saveToHistory: false);
      }
    });
  }

  void _selectSearchTerm(String term) {
    _searchController.text = term;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: term.length),
    );
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
    });
    _saveQueryToHistory(term);
    _performSearch(term, saveToHistory: true);
  }

  Future<void> _performSearch(String query, {String? category, bool saveToHistory = true}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    if (saveToHistory) {
      _saveQueryToHistory(trimmed);
    }

    final targetCategory = category ?? _selectedCategory;

    setState(() {
      _loading = true;
      _error = null;
      _showSuggestions = false;
    });

    try {
      UnifiedSearchResults results = await widget.authService.unifiedSearch(
        query: trimmed,
        category: targetCategory,
        limit: 25,
      );

      // Fallback if InnerTube returned empty
      if (results.isEmpty) {
        final yt = YoutubeService();
        final videos = await yt.search(trimmed);
        final songs = videos
            .map((v) => PlaylistVideo(
                  videoId: v.id.value,
                  title: v.title,
                  channelTitle: v.author,
                  thumbnailUrl: v.thumbnails.highResUrl,
                  duration: v.duration ?? Duration.zero,
                ))
            .toList();
        if (songs.isNotEmpty) {
          results = UnifiedSearchResults(
            topResult: TopSearchResult(type: 'song', data: songs.first),
            songs: songs,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Search failed: $e';
      });
    }
  }

  Future<void> _playSong(PlaylistVideo video) async {
    try {
      final index = _results.songs.indexOf(video);
      final playList = _results.songs.isNotEmpty ? _results.songs : [video];
      await widget.playerService.playVideos(
        playList.map((v) => (
          videoId: v.videoId,
          title: v.title,
          author: v.channelTitle,
          duration: v.duration,
        )).toList(),
        startIndex: index >= 0 ? index : 0,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Now playing: ${video.title}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to play: $e')),
      );
    }
  }

  Future<void> _playAllSongs() async {
    if (_results.songs.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing ${_results.songs.length} songs…'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      await widget.playerService.playVideos(
        _results.songs.map((v) => (
          videoId: v.videoId,
          title: v.title,
          author: v.channelTitle,
          duration: v.duration,
        )).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start playback: $e')),
      );
    }
  }

  void _openArtist(SearchArtist artist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistScreen(
          artistName: artist.name,
          channelId: artist.id,
          initialImageUrl: artist.thumbnailUrl,
          playerService: widget.playerService,
          authService: widget.authService,
          playlistService: widget.playlistService,
          settingsService: widget.settingsService,
        ),
      ),
    );
  }

  Future<void> _playAlbum(SearchAlbum album) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loading "${album.title}"…'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      final id = album.playlistId ?? album.browseId;
      final videos = await widget.authService.fetchPlaylistVideos(id);
      if (videos.isNotEmpty) {
        await widget.playerService.playVideos(
          videos.map((v) => (
            videoId: v.videoId,
            title: v.title,
            author: v.channelTitle,
            duration: v.duration,
          )).toList(),
        );
      } else {
        final yt = YoutubeService();
        final searchRes = await yt.search('${album.artist} ${album.title}');
        if (searchRes.isNotEmpty) {
          await widget.playerService.playVideos(
            searchRes.map((v) => (
              videoId: v.id.value,
              title: v.title,
              author: v.author,
              duration: v.duration ?? Duration.zero,
            )).toList(),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to play album: $e')),
      );
    }
  }

  Future<void> _playPlaylist(SearchPlaylist playlist) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loading "${playlist.title}"…'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      final videos = await widget.authService.fetchPlaylistVideos(playlist.id);
      if (videos.isNotEmpty) {
        await widget.playerService.playVideos(
          videos.map((v) => (
            videoId: v.videoId,
            title: v.title,
            author: v.channelTitle,
            duration: v.duration,
          )).toList(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to play playlist: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'Search',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Search text field
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums, playlists…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _results = const UnifiedSearchResults();
                            _error = null;
                          });
                        },
                      )
                    : null,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (q) => _performSearch(q),
              onChanged: _onSearchChanged,
            ),
          ),

          // Spotify-style Category Filter Pills
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () {
                    if (_selectedCategory == cat) return;
                    setState(() => _selectedCategory = cat);
                    if (_searchController.text.trim().isNotEmpty) {
                      _performSearch(_searchController.text, category: cat);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? widget.accentColor
                          : theme.colorScheme.surfaceContainerHighest.withAlpha(140),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? widget.accentColor
                            : theme.colorScheme.onSurface.withAlpha(30),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? Colors.black
                              : theme.colorScheme.onSurface.withAlpha(220),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Content body
          Expanded(
            child: _buildBody(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: widget.accentColor),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_searchController.text.trim().isEmpty) {
      if (_searchHistory.isNotEmpty) {
        return _buildSearchHistoryView(theme);
      }
      return _buildEmptyState(theme);
    }
    if (_showSuggestions && _suggestions.isNotEmpty) {
      return _buildSuggestionsView(theme);
    }
    if (_results.isEmpty) {
      if (_suggestions.isNotEmpty) {
        return _buildSuggestionsView(theme);
      }
      return _buildEmptyState(theme);
    }
    return _buildSearchResultsView(theme);
  }

  Widget _buildSearchHistoryView(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent searches',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            TextButton(
              onPressed: _clearHistory,
              child: Text(
                'Clear all',
                style: TextStyle(
                  color: widget.accentColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ..._searchHistory.map((item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded, size: 20),
              title: Text(
                item,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => _removeFromHistory(item),
                tooltip: 'Remove',
              ),
              onTap: () => _selectSearchTerm(item),
            )),
      ],
    );
  }

  Widget _buildSuggestionsView(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.search_rounded, size: 20),
          title: Text(
            suggestion,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.north_west_rounded, size: 18),
            onPressed: () {
              _searchController.text = suggestion;
              _searchController.selection = TextSelection.fromPosition(
                TextPosition(offset: suggestion.length),
              );
            },
            tooltip: 'Insert into search',
          ),
          onTap: () => _selectSearchTerm(suggestion),
        );
      },
    );
  }

  Widget _buildSearchResultsView(ThemeData theme) {
    switch (_selectedCategory) {
      case 'Songs':
        return _buildSongsCategoryView(theme);
      case 'Videos':
        return _buildVideosCategoryView(theme);
      case 'Artists':
        return _buildArtistsCategoryView(theme);
      case 'Albums':
        return _buildAlbumsCategoryView(theme);
      case 'Playlists':
        return _buildPlaylistsCategoryView(theme);
      case 'All':
      default:
        return _buildAllCategoryView(theme);
    }
  }

  Widget _buildVideosCategoryView(ThemeData theme) {
    if (_results.songs.isEmpty) {
      return Center(
        child: Text(
          'No videos found',
          style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(140)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        Row(
          children: [
            Text(
              'Videos (${_results.songs.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _playAllSongs,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Play all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._results.songs.map((song) => _buildSongTile(song, theme)),
      ],
    );
  }

  // ======================================================================
  // View: "All" Category (Spotify Multi-Section View with Top Result)
  // ======================================================================

  Widget _buildAllCategoryView(ThemeData theme) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (isDesktop && _results.topResult != null && _results.songs.isNotEmpty) ...[
          // Desktop: Top Result and Songs side-by-side
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top result',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildTopResultCard(_results.topResult!, theme),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Songs',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        if (_results.songs.length > 4)
                          TextButton(
                            onPressed: () {
                              setState(() => _selectedCategory = 'Songs');
                              _performSearch(_searchController.text, category: 'Songs');
                            },
                            child: Text(
                              'See all',
                              style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._results.songs.take(4).map((s) => _buildSongTile(s, theme)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ] else ...[
          // 1. Top Result Hero Card (Mobile or no songs)
          if (_results.topResult != null) ...[
            Text(
              'Top result',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 10),
            _buildTopResultCard(_results.topResult!, theme),
            const SizedBox(height: 24),
          ],

          // 2. Songs Section (top 4 songs)
          if (_results.songs.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Songs',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (_results.songs.length > 4)
                  TextButton(
                    onPressed: () {
                      setState(() => _selectedCategory = 'Songs');
                      _performSearch(_searchController.text, category: 'Songs');
                    },
                    child: Text(
                      'See all',
                      style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ..._results.songs.take(4).map((s) => _buildSongTile(s, theme)),
            const SizedBox(height: 24),
          ],
        ],

        // 3. Artists Carousel
        if (_results.artists.isNotEmpty) ...[
          Text(
            'Artists',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _results.artists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                return _buildArtistCarouselItem(_results.artists[index], theme);
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // 4. Albums Carousel
        if (_results.albums.isNotEmpty) ...[
          Text(
            'Albums',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 185,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _results.albums.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                return _buildAlbumCarouselItem(_results.albums[index], theme);
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // 5. Playlists Carousel
        if (_results.playlists.isNotEmpty) ...[
          Text(
            'Playlists',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 185,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _results.playlists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                return _buildPlaylistCarouselItem(_results.playlists[index], theme);
              },
            ),
          ),
        ],
      ],
    );
  }

  // ======================================================================
  // Top Result Card (Spotify Hero Card)
  // ======================================================================

  Widget _buildTopResultCard(TopSearchResult top, ThemeData theme) {
    if (top.isArtist && top.asArtist != null) {
      final artist = top.asArtist!;
      return InkWell(
        onTap: () => _openArtist(artist),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: widget.accentColor.withAlpha(40),
                backgroundImage: artist.thumbnailUrl.isNotEmpty
                    ? NetworkImage(artist.thumbnailUrl)
                    : null,
                child: artist.thumbnailUrl.isEmpty
                    ? Text(
                        artist.name.isNotEmpty ? artist.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: widget.accentColor,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      artist.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(120),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Artist${artist.subscribers != null ? " • ${artist.subscribers}" : ""}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withAlpha(200),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: Colors.black,
                  iconSize: 26,
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () => _openArtist(artist),
              ),
            ],
          ),
        ),
      );
    } else if (top.isSong && top.asSong != null) {
      final song = top.asSong!;
      return InkWell(
        onTap: () => _playSong(song),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  song.thumbnailUrl,
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 76,
                    height: 76,
                    color: Colors.black26,
                    child: const Icon(Icons.music_note),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.channelTitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withAlpha(160),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(120),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Song',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withAlpha(200),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: Colors.black,
                  iconSize: 26,
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () => _playSong(song),
              ),
            ],
          ),
        ),
      );
    } else if (top.isAlbum && top.asAlbum != null) {
      final album = top.asAlbum!;
      return InkWell(
        onTap: () => _playAlbum(album),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  album.thumbnailUrl,
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 76,
                    height: 76,
                    color: Colors.black26,
                    child: const Icon(Icons.album),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      album.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${album.artist}${album.year != null ? " • ${album.year}" : ""}',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withAlpha(160),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(120),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        album.type ?? 'Album',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withAlpha(200),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: Colors.black,
                  iconSize: 26,
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () => _playAlbum(album),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ======================================================================
  // Carousel & Tile Builders
  // ======================================================================

  Widget _buildSongTile(PlaylistVideo song, ThemeData theme) {
    return _MusicListTile(
      video: song,
      accentColor: widget.accentColor,
      playlistService: widget.playlistService,
      playerService: widget.playerService,
      onPlay: () => _playSong(song),
    );
  }

  Widget _buildArtistCarouselItem(SearchArtist artist, ThemeData theme) {
    return GestureDetector(
      onTap: () => _openArtist(artist),
      child: SizedBox(
        width: 86,
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: widget.accentColor.withAlpha(35),
              backgroundImage: artist.thumbnailUrl.isNotEmpty
                  ? NetworkImage(artist.thumbnailUrl)
                  : null,
              child: artist.thumbnailUrl.isEmpty
                  ? Text(
                      artist.name.isNotEmpty ? artist.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: widget.accentColor,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Artist',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withAlpha(130),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumCarouselItem(SearchAlbum album, ThemeData theme) {
    return GestureDetector(
      onTap: () => _playAlbum(album),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                album.thumbnailUrl,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 120,
                  height: 120,
                  color: Colors.black26,
                  child: const Icon(Icons.album),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${album.type ?? "Album"} • ${album.artist}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withAlpha(130),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistCarouselItem(SearchPlaylist playlist, ThemeData theme) {
    return GestureDetector(
      onTap: () => _playPlaylist(playlist),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                playlist.thumbnailUrl,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 120,
                  height: 120,
                  color: Colors.black26,
                  child: const Icon(Icons.queue_music_rounded),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              playlist.author ?? 'Playlist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withAlpha(130),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================================================================
  // Category-Specific Views (Songs, Artists, Albums, Playlists)
  // ======================================================================

  Widget _buildSongsCategoryView(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        Row(
          children: [
            Text(
              'Songs (${_results.songs.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _playAllSongs,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Play all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._results.songs.map((song) => _buildSongTile(song, theme)),
      ],
    );
  }

  Widget _buildArtistsCategoryView(ThemeData theme) {
    if (_results.artists.isEmpty) {
      return Center(
        child: Text(
          'No artists found',
          style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(140)),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: _results.artists.length,
      itemBuilder: (context, index) {
        final artist = _results.artists[index];
        return InkWell(
          onTap: () => _openArtist(artist),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh.withAlpha(120),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: widget.accentColor.withAlpha(35),
                  backgroundImage: artist.thumbnailUrl.isNotEmpty
                      ? NetworkImage(artist.thumbnailUrl)
                      : null,
                  child: artist.thumbnailUrl.isEmpty
                      ? Text(
                          artist.name.isNotEmpty ? artist.name[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: widget.accentColor,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  artist.subscribers ?? 'Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withAlpha(140),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumsCategoryView(ThemeData theme) {
    if (_results.albums.isEmpty) {
      return Center(
        child: Text(
          'No albums found',
          style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(140)),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.74,
      ),
      itemCount: _results.albums.length,
      itemBuilder: (context, index) {
        final album = _results.albums[index];
        return InkWell(
          onTap: () => _playAlbum(album),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    album.thumbnailUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: Colors.black26,
                      child: const Center(child: Icon(Icons.album, size: 40)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${album.artist}${album.year != null ? " • ${album.year}" : ""}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withAlpha(140),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaylistsCategoryView(ThemeData theme) {
    if (_results.playlists.isEmpty) {
      return Center(
        child: Text(
          'No playlists found',
          style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(140)),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.74,
      ),
      itemCount: _results.playlists.length,
      itemBuilder: (context, index) {
        final playlist = _results.playlists[index];
        return InkWell(
          onTap: () => _playPlaylist(playlist),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    playlist.thumbnailUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: Colors.black26,
                      child: const Center(child: Icon(Icons.queue_music_rounded, size: 40)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                playlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                playlist.author ?? 'Playlist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withAlpha(140),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            'Find Music',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Search songs, artists, albums, and playlists',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Playlists Tab — dedicated YouTube playlists
// ======================================================================

class PlaylistsTab extends StatefulWidget {
  final PlayerService playerService;
  final GoogleAuthService authService;
  final PlaylistService playlistService;
  final SettingsService settingsService;
  final VoidCallback onGoToSettings;
  final VoidCallback? onGoToPlayer;

  const PlaylistsTab({
    super.key,
    required this.playerService,
    required this.authService,
    required this.playlistService,
    required this.settingsService,
    required this.onGoToSettings,
    this.onGoToPlayer,
  });

  @override
  State<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<PlaylistsTab> {
  String? _syncingPlaylistId;

  @override
  void initState() {
    super.initState();
    widget.playlistService.addListener(_onStateUpdate);
  }

  @override
  void dispose() {
    widget.playlistService.removeListener(_onStateUpdate);
    super.dispose();
  }

  void _onStateUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PlaylistsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlistService != widget.playlistService) {
      oldWidget.playlistService.removeListener(_onStateUpdate);
      widget.playlistService.addListener(_onStateUpdate);
    }
  }

  Future<void> _syncLocalPlaylist(LocalPlaylist playlist) async {
    if (!playlist.isSpotify) return;
    setState(() => _syncingPlaylistId = playlist.id);
    try {
      final updated = await widget.playlistService.syncSpotifyPlaylist(
        playlist.id,
        clientId: widget.settingsService.spotifyClientId,
        clientSecret: widget.settingsService.spotifyClientSecret,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced "${updated.title}" (${updated.trackCount} songs)'),
          backgroundColor: const Color(0xFF1DB954),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _syncingPlaylistId = null);
      }
    }
  }


  void _openLocalPlaylist(LocalPlaylist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalPlaylistDetailScreen(
          playlist: playlist,
          playlistService: widget.playlistService,
          playerService: widget.playerService,
          settingsService: widget.settingsService,
          authService: widget.authService,
        ),
      ),
    );
  }

  Future<void> _showImportSpotifyDialog(BuildContext context) async {
    final controller = TextEditingController();
    bool loading = false;
    String? statusMessage;
    String? error;
    SpotifyImportResult? preview;
    bool showApiSetup = false;
    final idController = TextEditingController(text: widget.settingsService.spotifyClientId);
    final secretController = TextEditingController(text: widget.settingsService.spotifyClientSecret);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setSheetState) {
            Future<void> fetchPreview() async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              setSheetState(() {
                loading = true;
                error = null;
                preview = null;
                statusMessage = widget.settingsService.hasSpotifyCredentials
                    ? 'Connecting to Spotify Web API…'
                    : 'Extracting playlist metadata…';
              });
              try {
                final spotify = SpotifyService();
                final res = await spotify.fetch(
                  text,
                  clientId: widget.settingsService.spotifyClientId,
                  clientSecret: widget.settingsService.spotifyClientSecret,
                  onProgress: (current, total) {
                    if (!dialogCtx.mounted) return;
                    setSheetState(() {
                      statusMessage = 'Fetched $current of $total tracks…';
                    });
                  },
                );
                if (!dialogCtx.mounted) return;
                setSheetState(() {
                  preview = res;
                  loading = false;
                });
              } catch (e) {
                if (!dialogCtx.mounted) return;
                setSheetState(() {
                  error = e.toString().replaceFirst('Exception: ', '');
                  loading = false;
                });
              }
            }

            Future<void> pasteFromClipboard() async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null && data!.text!.isNotEmpty) {
                controller.text = data.text!.trim();
                fetchPreview();
              }
            }

            final hasApi = widget.settingsService.hasSpotifyCredentials;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(dialogCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1DB954).withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.queue_music_rounded,
                            color: Color(0xFF1DB954),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Import Spotify Playlist',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (hasApi ? const Color(0xFF1DB954) : Colors.grey).withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasApi ? Icons.bolt_rounded : Icons.info_outline,
                                size: 13,
                                color: hasApi ? const Color(0xFF1DB954) : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasApi ? 'Spotify API Active (1k+ tracks)' : 'Public Mode (100 tracks max)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: hasApi ? const Color(0xFF1DB954) : const Color(0xFFAAAAAA),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => setSheetState(() => showApiSetup = !showApiSetup),
                          child: Text(
                            showApiSetup ? 'Hide setup' : (hasApi ? 'Edit keys' : 'Enable 1k+ tracks'),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF1DB954),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showApiSetup) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252525),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF383838)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Free Spotify API Credentials',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1DB954)),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Create a free app at developer.spotify.com/dashboard to fetch 1,000+ tracks:',
                              style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: idController,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Client ID',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: secretController,
                              obscureText: true,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Client Secret',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (hasApi)
                                  TextButton(
                                    onPressed: () async {
                                      await widget.settingsService.clearSpotifyCredentials();
                                      idController.clear();
                                      secretController.clear();
                                      setSheetState(() => showApiSetup = false);
                                    },
                                    child: const Text('Clear', style: TextStyle(color: Color(0xFFCF6679), fontSize: 12)),
                                  ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF1DB954),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  onPressed: () async {
                                    final id = idController.text.trim();
                                    final sec = secretController.text.trim();
                                    if (id.isNotEmpty && sec.isNotEmpty) {
                                      await widget.settingsService.setSpotifyCredentials(id, sec);
                                      setSheetState(() => showApiSetup = false);
                                    }
                                  },
                                  child: const Text('Save Keys', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              hintText: 'https://open.spotify.com/playlist/...',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        controller.clear();
                                        setSheetState(() {
                                          preview = null;
                                          error = null;
                                        });
                                      },
                                    )
                                  : null,
                            ),
                            onSubmitted: (_) => fetchPreview(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.paste, size: 18),
                          tooltip: 'Paste',
                          onPressed: pasteFromClipboard,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            children: [
                              const CircularProgressIndicator(strokeWidth: 2.5),
                              const SizedBox(height: 12),
                              Text(
                                statusMessage ?? 'Extracting playlist metadata from Spotify…',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Color(0xFFCF6679), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (preview != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF282828),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF383838)),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: preview!.thumbnailUrl.isNotEmpty
                                  ? Image.network(
                                      preview!.thumbnailUrl,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        width: 56,
                                        height: 56,
                                        color: const Color(0xFF1DB954).withAlpha(40),
                                        child: const Icon(Icons.music_note, color: Color(0xFF1DB954)),
                                      ),
                                    )
                                  : Container(
                                      width: 56,
                                      height: 56,
                                      color: const Color(0xFF1DB954).withAlpha(40),
                                      child: const Icon(Icons.music_note, color: Color(0xFF1DB954)),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preview!.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${preview!.tracks.length} songs · Spotify ${preview!.type.name}',
                                    style: const TextStyle(color: Color(0xFF1DB954), fontSize: 13),
                                  ),
                                  if (preview!.description.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      preview!.description,
                                      style: const TextStyle(color: Color(0xFF999999), fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!hasApi && preview!.tracks.length == 100) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF332B00),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF665500)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 14, color: Color(0xFFFFD54F)),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Capped at 100 songs (public limit). Enable Spotify API keys above to load all 1,000+ tracks.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFFFFD54F)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.save_alt_rounded, size: 18),
                              label: const Text('Import & Save'),
                              onPressed: () async {
                                final saved = await widget.playlistService.createFromSpotify(preview!);
                                if (!dialogCtx.mounted) return;
                                Navigator.of(dialogCtx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Imported "${saved.title}" (${saved.trackCount} songs)'),
                                    backgroundColor: const Color(0xFF1DB954),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1DB954)),
                              icon: const Icon(Icons.play_arrow_rounded, size: 20),
                              label: const Text('Play Now'),
                              onPressed: () async {
                                final saved = await widget.playlistService.createFromSpotify(preview!);
                                await widget.playerService.playLocalTracks(saved.tracks);
                                if (!dialogCtx.mounted) return;
                                Navigator.of(dialogCtx).pop();
                                widget.onGoToPlayer?.call();
                              },
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      FilledButton.icon(
                        onPressed: fetchPreview,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Fetch Playlist'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showImportTextDialog(BuildContext context) async {
    final nameController = TextEditingController(text: 'My Playlist');
    final textController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Song List'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter playlist name and paste song lines or a Spotify CSV file (from Exportify / Soundiiz with 1,000+ songs):',
                style: TextStyle(fontSize: 13, color: Color(0xFFAAAAAA)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Playlist Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 7,
                decoration: const InputDecoration(
                  hintText: 'Queen - Bohemian Rhapsody\nEagles - Hotel California\n-- OR paste CSV from Exportify --\nTrack Name,Artist Name(s)\nBohemian Rhapsody,Queen',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = textController.text.trim();
              if (raw.isEmpty) return;
              final saved = await widget.playlistService.createFromText(
                title: nameController.text.trim(),
                rawText: raw,
              );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Imported "${saved.title}" (${saved.trackCount} songs)'),
                ),
              );
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _showSpotifyHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF1DB954)),
            SizedBox(width: 8),
            Text('Spotify Sync Guide'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How to Import from Spotify:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 6),
              Text(
                '1. Open Spotify (mobile app or web).\n'
                '2. Go to any playlist or album.\n'
                '3. Tap ••• (Options) → Share → Copy Link.\n'
                '4. In FinAudio, tap "Import Spotify" and paste the link.\n'
                '5. FinAudio extracts the songs and streams ad-free via YouTube/NewPipe!',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 14),
              Text(
                'Importing 1,000+ Songs:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 6),
              Text(
                '• Standard preview imports up to 100 songs without login.\n'
                '• For 1,000+ songs, get a free Client ID & Secret from developer.spotify.com/dashboard and save it in Settings → Spotify Integration.\n'
                '• Or export your playlist CSV from exportify.net and paste it into "Paste Song List"!',
                style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFFCCCCCC)),
              ),
              SizedBox(height: 14),
              Text(
                'How Sync Works:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 6),
              Text(
                '• Each imported Spotify playlist has a Sync button (↻).\n'
                '• Tap Sync anytime you add new songs to your Spotify playlist to instantly refresh FinAudio.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localPlaylists = widget.playlistService.playlists;
    final totalCount = localPlaylists.length;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Header Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Playlists',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Import Spotify'),
                    onPressed: () => _showImportSpotifyDialog(context),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (val) {
                      switch (val) {
                        case 'import_spotify':
                          _showImportSpotifyDialog(context);
                          break;
                        case 'import_text':
                          _showImportTextDialog(context);
                          break;
                        case 'help':
                          _showSpotifyHelpDialog(context);
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'import_spotify',
                        child: Row(
                          children: [
                            Icon(Icons.download_rounded, size: 18, color: Color(0xFF1DB954)),
                            SizedBox(width: 8),
                            Text('Import Spotify Playlist'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'import_text',
                        child: Row(
                          children: [
                            Icon(Icons.text_snippet_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Import Song List (Text)'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'help',
                        child: Row(
                          children: [
                            Icon(Icons.help_outline, size: 18),
                            SizedBox(width: 8),
                            Text('How Spotify Sync Works'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // If no playlists exist at all -> Onboarding / Empty State
          if (totalCount == 0)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954).withAlpha(25),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF1DB954).withAlpha(60)),
                        ),
                        child: const Icon(
                          Icons.queue_music_rounded,
                          size: 42,
                          color: Color(0xFF1DB954),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Import Your Spotify Playlists',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Paste any Spotify playlist, album, or track link to import and stream ad-free. Tap Sync anytime to pick up new songs!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1DB954)),
                        onPressed: () => _showImportSpotifyDialog(context),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Import Spotify Playlist'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _showImportTextDialog(context),
                        icon: const Icon(Icons.text_snippet_outlined, size: 18),
                        label: const Text('Import from Text / Notes'),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () => _showSpotifyHelpDialog(context),
                        icon: const Icon(Icons.help_outline, size: 16),
                        label: const Text('How does Spotify sync work?'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            // Playlists Grid
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = localPlaylists[index];
                    return _LocalPlaylistCard(
                      playlist: item,
                      isSyncing: _syncingPlaylistId == item.id,
                      onTap: () => _openLocalPlaylist(item),
                      onLongPress: () => _showPlaylistOptionsSheet(item),
                      onSync: () => _syncLocalPlaylist(item),
                      onDelete: () => widget.playlistService.deletePlaylist(item.id),
                    );
                  },
                  childCount: localPlaylists.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showPlaylistOptionsSheet(LocalPlaylist playlist) {
    final accent = widget.settingsService.accentColor;
    final surface = widget.settingsService.surfaceColor;
    final text = widget.settingsService.textColor;
    final isLiked = playlist.isLikedSongs;

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: text.withAlpha(50),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Header with artwork, title, count
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 52,
                          height: 52,
                          color: Colors.black26,
                          child: isLiked
                              ? Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.favorite_rounded, color: Colors.white, size: 28),
                                  ),
                                )
                              : (playlist.effectiveThumbnailUrl.isNotEmpty
                                  ? Image.network(
                                      playlist.effectiveThumbnailUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(Icons.queue_music, color: accent),
                                    )
                                  : Icon(Icons.queue_music, color: accent)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlist.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${playlist.trackCount} song${playlist.trackCount == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 13, color: text.withAlpha(140)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Divider(height: 1, color: text.withAlpha(20)),

                // 1. Play
                ListTile(
                  leading: Icon(Icons.play_arrow_rounded, color: accent, size: 26),
                  title: Text('Play', style: TextStyle(color: text, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    widget.playerService.playLocalTracks(playlist.tracks);
                  },
                ),

                // 2. Play Next
                ListTile(
                  leading: Icon(Icons.playlist_play_rounded, color: text, size: 26),
                  title: Text('Play next', style: TextStyle(color: text)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    final tracks = playlist.tracks.map(Track.fromLocalPlaylistTrack).toList();
                    widget.playerService.playNextTracks(tracks);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Playing "${playlist.title}" next')),
                    );
                  },
                ),

                // 3. Add to Queue
                ListTile(
                  leading: Icon(Icons.queue_music_rounded, color: text, size: 24),
                  title: Text('Add to queue', style: TextStyle(color: text)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    final tracks = playlist.tracks.map(Track.fromLocalPlaylistTrack).toList();
                    widget.playerService.addTracksToQueue(tracks);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Added ${tracks.length} tracks to queue')),
                    );
                  },
                ),

                // 4. Download Playlist
                ListTile(
                  leading: Icon(Icons.download_rounded, color: accent, size: 24),
                  title: Text('Download playlist', style: TextStyle(color: text)),
                  subtitle: Text(
                    'Save in space-saving Opus for offline listening',
                    style: TextStyle(fontSize: 11, color: text.withAlpha(120)),
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    final tracks = playlist.tracks.map(Track.fromLocalPlaylistTrack).toList();
                    DownloadService.instance.downloadTracks(tracks);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Downloading ${tracks.length} songs for offline listening…')),
                    );
                  },
                ),

                // 5. Add all to Liked Songs (if not liked songs)
                if (!isLiked)
                  ListTile(
                    leading: const Icon(Icons.favorite_rounded, color: Color(0xFFFF5252), size: 24),
                    title: Text('Add all to Liked Songs', style: TextStyle(color: text)),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      final count = await widget.playlistService.addAllToLikedSongs(playlist.tracks);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(count > 0 ? 'Added $count songs to Liked Songs!' : 'All songs are already in Liked Songs!'),
                          backgroundColor: const Color(0xFF1DB954),
                        ),
                      );
                    },
                  ),

                // 6. Open Playlist Detail
                ListTile(
                  leading: Icon(Icons.open_in_new_rounded, color: text, size: 24),
                  title: Text('Open playlist', style: TextStyle(color: text)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _openLocalPlaylist(playlist);
                  },
                ),

                // 7. Delete Playlist (if not liked songs)
                if (!isLiked)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
                    title: const Text('Delete playlist', style: TextStyle(color: Colors.redAccent)),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Playlist'),
                          content: Text('Delete "${playlist.title}"?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await widget.playlistService.deletePlaylist(playlist.id);
                      }
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ======================================================================
// Local / Spotify Playlist Card (grid item)
// ======================================================================

class _LocalPlaylistCard extends StatelessWidget {
  final LocalPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback onSync;
  final VoidCallback onDelete;
  final VoidCallback? onLongPress;
  final bool isSyncing;

  const _LocalPlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.onSync,
    required this.onDelete,
    this.onLongPress,
    this.isSyncing = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSpotify = playlist.isSpotify;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: playlist.effectiveThumbnailUrl.isNotEmpty
                      ? Image.network(
                          playlist.effectiveThumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _artPlaceholder(isSpotify),
                        )
                      : _artPlaceholder(isSpotify),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${playlist.trackCount} songs',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (isSpotify)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1DB954).withAlpha(40),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Spotify',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF1DB954),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isSpotify)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    shape: BoxShape.circle,
                  ),
                  child: isSyncing
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF1DB954),
                            ),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.sync, size: 18),
                          color: Colors.white,
                          tooltip: 'Sync with Spotify',
                          onPressed: onSync,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _artPlaceholder(bool isSpotify) {
    return Container(
      color: isSpotify ? const Color(0xFF0D2513) : const Color(0xFF1A1A2E),
      child: Center(
        child: Icon(
          isSpotify ? Icons.graphic_eq : Icons.queue_music_rounded,
          size: 40,
          color: isSpotify ? const Color(0xFF1DB954) : const Color(0xFF888888),
        ),
      ),
    );
  }
}

// ======================================================================
enum PlaylistSortOption {
  original,
  titleAsc,
  titleDesc,
  artistAsc,
  artistDesc,
  durationAsc,
  durationDesc,
}

class LocalPlaylistDetailScreen extends StatefulWidget {
  final LocalPlaylist playlist;
  final PlaylistService playlistService;
  final PlayerService playerService;
  final SettingsService? settingsService;
  final GoogleAuthService? authService;

  const LocalPlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.playlistService,
    required this.playerService,
    this.settingsService,
    this.authService,
  });

  @override
  State<LocalPlaylistDetailScreen> createState() => _LocalPlaylistDetailScreenState();
}

class _LocalPlaylistDetailScreenState extends State<LocalPlaylistDetailScreen> {
  late LocalPlaylist _playlist;
  bool _syncing = false;
  bool _fetchingArtworks = false;
  PlaylistSortOption _sortOption = PlaylistSortOption.original;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  StreamSubscription<Track?>? _nowPlayingSub;

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    if (_playlist.thumbnailUrl.isEmpty && _playlist.tracks.isNotEmpty) {
      _autoFetchCoverIfMissing();
    }
    _nowPlayingSub = widget.playerService.nowPlayingStream.listen((track) {
      if (track != null && mounted) {
        _onTrackNowPlaying(track);
      }
    });
  }

  @override
  void dispose() {
    _nowPlayingSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onTrackNowPlaying(Track track) {
    if (track.thumbnailUrl == null || track.thumbnailUrl!.isEmpty) return;
    final trackIndex = _playlist.tracks.indexWhere(
      (t) =>
          t.title.trim().toLowerCase() == track.title.trim().toLowerCase() &&
          (t.artist.trim().toLowerCase() == track.author.trim().toLowerCase() ||
           t.formattedArtist.trim().toLowerCase() == track.formattedArtist.trim().toLowerCase()),
    );
    if (trackIndex >= 0) {
      final current = _playlist.tracks[trackIndex];
      if (current.thumbnailUrl != track.thumbnailUrl ||
          current.youtubeVideoId != track.id) {
        final updatedTracks = List<LocalPlaylistTrack>.from(_playlist.tracks);
        updatedTracks[trackIndex] = current.copyWith(
          thumbnailUrl: track.thumbnailUrl,
          youtubeVideoId: track.id,
        );
        final updated = _playlist.copyWith(tracks: updatedTracks);
        // Only update local UI state; track resolution persistence is already
        // handled cooperatively by updateTrackResolvedVideoId without freezing playback frames.
        if (mounted) setState(() => _playlist = updated);
      }
    }
  }

  Future<void> _autoFetchCoverIfMissing({bool force = false}) async {
    if (!force && _playlist.thumbnailUrl.isNotEmpty) return;
    if (_playlist.tracks.isEmpty) return;
    try {
      final first = _playlist.tracks.first;
      final query = '${first.artist} ${first.title} audio';
      final results = await YoutubeService().search(query);
      if (results.isNotEmpty && mounted) {
        final thumb = 'https://img.youtube.com/vi/${results.first.id.value}/hqdefault.jpg';
        final updated = _playlist.copyWith(thumbnailUrl: thumb);
        await widget.playlistService.savePlaylist(updated);
        if (mounted) {
          setState(() => _playlist = updated);
          if (force) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cover art updated from first song!'),
                backgroundColor: Color(0xFF1DB954),
              ),
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchTrackArtworks() async {
    if (_fetchingArtworks) return;
    setState(() => _fetchingArtworks = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fetching track artworks in background…')),
    );
    int fetchedCount = 0;
    try {
      final updatedTracks = List<LocalPlaylistTrack>.from(_playlist.tracks);
      final yt = YoutubeService();
      for (int i = 0; i < updatedTracks.length && fetchedCount < 25; i++) {
        final t = updatedTracks[i];
        if (t.thumbnailUrl == null || t.thumbnailUrl!.isEmpty) {
          try {
            final query = '${t.artist} ${t.title} audio';
            final results = await yt.search(query);
            if (results.isNotEmpty) {
              final videoId = results.first.id.value;
              updatedTracks[i] = t.copyWith(
                thumbnailUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                youtubeVideoId: videoId,
              );
              fetchedCount++;
            }
          } catch (_) {}
        }
      }
      if (fetchedCount > 0) {
        final updated = _playlist.copyWith(tracks: updatedTracks);
        await widget.playlistService.savePlaylist(updated);
        if (!mounted) return;
        setState(() => _playlist = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fetched artworks for $fetchedCount tracks!'),
            backgroundColor: const Color(0xFF1DB954),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All checked tracks already have artwork.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch artworks: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingArtworks = false);
    }
  }

  Future<void> _sync() async {
    if (!_playlist.isSpotify) return;
    setState(() => _syncing = true);
    try {
      final updated = await widget.playlistService.syncSpotifyPlaylist(
        _playlist.id,
        clientId: widget.settingsService?.spotifyClientId,
        clientSecret: widget.settingsService?.spotifyClientSecret,
      );
      if (!mounted) return;
      setState(() {
        _playlist = updated;
        _syncing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced "${updated.title}" (${updated.trackCount} songs)'),
          backgroundColor: const Color(0xFF1DB954),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  List<LocalPlaylistTrack> _getSortedTracks() {
    final list = List<LocalPlaylistTrack>.from(_playlist.tracks);
    switch (_sortOption) {
      case PlaylistSortOption.titleAsc:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case PlaylistSortOption.titleDesc:
        list.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case PlaylistSortOption.artistAsc:
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case PlaylistSortOption.artistDesc:
        list.sort((a, b) => b.artist.toLowerCase().compareTo(a.artist.toLowerCase()));
        break;
      case PlaylistSortOption.durationAsc:
        list.sort((a, b) => a.duration.compareTo(b.duration));
        break;
      case PlaylistSortOption.durationDesc:
        list.sort((a, b) => b.duration.compareTo(a.duration));
        break;
      case PlaylistSortOption.original:
        break;
    }
    return list;
  }

  String _getSortButtonLabel() {
    switch (_sortOption) {
      case PlaylistSortOption.original:
        return 'Sort';
      case PlaylistSortOption.titleAsc:
        return 'Title (A-Z)';
      case PlaylistSortOption.titleDesc:
        return 'Title (Z-A)';
      case PlaylistSortOption.artistAsc:
        return 'Artist (A-Z)';
      case PlaylistSortOption.artistDesc:
        return 'Artist (Z-A)';
      case PlaylistSortOption.durationAsc:
        return 'Shortest';
      case PlaylistSortOption.durationDesc:
        return 'Longest';
    }
  }

  void _playAll({bool shuffle = false}) {
    final list = _getSortedTracks();
    if (list.isEmpty) return;
    final tracks = List<LocalPlaylistTrack>.from(list);
    if (shuffle) tracks.shuffle();
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing ${tracks.length} songs…'),
        duration: const Duration(seconds: 2),
      ),
    );
    widget.playerService.playLocalTracks(tracks).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback failed: $e')),
        );
      }
    });
  }

  void _playTrack(int sortedIndex) {
    final list = _getSortedTracks();
    if (sortedIndex < 0 || sortedIndex >= list.length) return;
    HapticFeedback.lightImpact();
    final track = list[sortedIndex];
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Now playing: ${track.title}'),
        duration: const Duration(seconds: 2),
      ),
    );
    widget.playerService.playLocalTracks(list, startIndex: sortedIndex).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback failed: $e')),
        );
      }
    });
  }

  void _openArtistPage(String artistName, {String? imageUrl}) {
    if (widget.authService == null || widget.settingsService == null) return;
    openArtistPage(
      context: context,
      artistName: artistName,
      playerService: widget.playerService,
      authService: widget.authService!,
      playlistService: widget.playlistService,
      settingsService: widget.settingsService!,
      initialImageUrl: imageUrl,
    );
  }

  void _showTrackOptions(LocalPlaylistTrack track) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isLiked = widget.playlistService.isTrackLiked(
      track.youtubeVideoId,
      track.title,
      track.artist,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
                      ? Image.network(
                          track.thumbnailUrl!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 44,
                            height: 44,
                            color: const Color(0xFF282828),
                            child: const Icon(Icons.music_note, color: Colors.white54),
                          ),
                        )
                      : Container(
                          width: 44,
                          height: 44,
                          color: const Color(0xFF282828),
                          child: const Icon(Icons.music_note, color: Colors.white54),
                        ),
                ),
                title: Text(
                  track.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.formattedArtist,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                title: const Text('Play next', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.playerService.playNext(Track.fromLocalPlaylistTrack(track));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added "${track.title}" to play next')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded, color: Colors.white),
                title: const Text('Add to playlist', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  showAddToPlaylistSheet(
                    context: context,
                    track: track,
                    playlistService: widget.playlistService,
                    accentColor: accent,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isLiked ? const Color(0xFFFF5252) : Colors.white,
                ),
                title: Text(
                  isLiked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.playlistService.toggleLikeTrack(track);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isLiked ? 'Removed from Liked Songs' : 'Added to Liked Songs',
                      ),
                    ),
                  );
                },
              ),
              if (widget.authService != null && widget.settingsService != null) ...[
                if (track.individualArtists.length > 1) ...[
                  for (final artist in track.individualArtists)
                    ListTile(
                      leading: const Icon(Icons.person_outline_rounded, color: Colors.white),
                      title: Text('Go to $artist', style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _openArtistPage(artist, imageUrl: track.thumbnailUrl);
                      },
                    ),
                ] else
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded, color: Colors.white),
                    title: Text(
                        'Go to ${track.individualArtists.firstOrNull ?? (track.artist.isNotEmpty ? track.artist : "artist")}',
                        style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      final aName = track.individualArtists.firstOrNull ?? track.artist;
                      if (aName.trim().isEmpty) return;
                      _openArtistPage(aName, imageUrl: track.thumbnailUrl);
                    },
                  ),
              ],
              if (!_playlist.isLikedSongs)
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline_rounded, color: Color(0xFFCF6679)),
                  title: const Text('Remove from this playlist', style: TextStyle(color: Color(0xFFCF6679))),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await widget.playlistService.removeTrackFromPlaylist(_playlist.id, track);
                    final updatedPlaylist = widget.playlistService.getPlaylist(_playlist.id);
                    if (updatedPlaylist != null && mounted) {
                      setState(() => _playlist = updatedPlaylist);
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deletePlaylist() async {
    if (_playlist.isLikedSongs) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Are you sure you want to delete "${_playlist.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFCF6679)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.playlistService.deletePlaylist(_playlist.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  void _showSortModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final options = [
              (PlaylistSortOption.original, 'Default (Original Order)', Icons.format_list_numbered_rounded),
              (PlaylistSortOption.titleAsc, 'Title (A → Z)', Icons.sort_by_alpha_rounded),
              (PlaylistSortOption.titleDesc, 'Title (Z → A)', Icons.sort_by_alpha_rounded),
              (PlaylistSortOption.artistAsc, 'Artist (A → Z)', Icons.person_rounded),
              (PlaylistSortOption.artistDesc, 'Artist (Z → A)', Icons.person_outline_rounded),
              (PlaylistSortOption.durationAsc, 'Duration (Shortest first)', Icons.timer_outlined),
              (PlaylistSortOption.durationDesc, 'Duration (Longest first)', Icons.timer_rounded),
            ];

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sort_rounded, color: Color(0xFF1DB954)),
                        const SizedBox(width: 8),
                        const Text(
                          'Sort Playlist Tracks',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...options.map((opt) {
                      final isSelected = _sortOption == opt.$1;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          opt.$3,
                          color: isSelected ? const Color(0xFF1DB954) : const Color(0xFF888888),
                          size: 20,
                        ),
                        title: Text(
                          opt.$2,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? const Color(0xFF1DB954) : Colors.white,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFF1DB954), size: 18)
                            : null,
                        onTap: () {
                          setState(() => _sortOption = opt.$1);
                          setSheetState(() {});
                        },
                      );
                    }),
                    const SizedBox(height: 12),
                    if (_sortOption != PlaylistSortOption.original)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                        ),
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Save Order Permanently'),
                        onPressed: () async {
                          final nav = Navigator.of(sheetCtx);
                          final messenger = ScaffoldMessenger.of(context);
                          final sorted = _getSortedTracks();
                          final updated = _playlist.copyWith(tracks: sorted);
                          await widget.playlistService.savePlaylist(updated);
                          if (!mounted) return;
                          setState(() {
                            _playlist = updated;
                            _sortOption = PlaylistSortOption.original;
                          });
                          nav.pop();
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Playlist order saved permanently!'),
                              backgroundColor: Color(0xFF1DB954),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditPlaylistDialog() async {
    final titleController = TextEditingController(text: _playlist.title);
    final urlController = TextEditingController(text: _playlist.thumbnailUrl);
    String previewUrl = _playlist.thumbnailUrl;

    final trackThumbs = <({String title, String url})>[];
    for (final t in _playlist.tracks) {
      final thumb = (t.thumbnailUrl?.isNotEmpty == true)
          ? t.thumbnailUrl!
          : (t.youtubeVideoId?.isNotEmpty == true)
              ? 'https://img.youtube.com/vi/${t.youtubeVideoId}/hqdefault.jpg'
              : '';
      if (thumb.isNotEmpty && !trackThumbs.any((item) => item.url == thumb)) {
        trackThumbs.add((title: t.title, url: thumb));
        if (trackThumbs.length >= 8) break;
      }
    }

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isLiked = _playlist.isLikedSongs;
          return AlertDialog(
            title: Text(isLiked ? 'Change Liked Songs Cover' : 'Edit Cover & Title'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF383838)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: previewUrl.isNotEmpty
                            ? Image.network(
                                previewUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.broken_image, color: Colors.grey, size: 36),
                                ),
                              )
                            : (isLiked
                                ? Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.favorite_rounded, color: Colors.white, size: 48),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.queue_music_rounded, color: Colors.grey, size: 48),
                                  )),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!isLiked) ...[
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Playlist Name',
                          prefixIcon: Icon(Icons.title, size: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: urlController,
                      decoration: InputDecoration(
                        labelText: 'Cover Image URL',
                        hintText: 'https://...',
                        prefixIcon: const Icon(Icons.image_outlined, size: 20),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (urlController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  urlController.clear();
                                  setDialogState(() => previewUrl = '');
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.paste, size: 18),
                              tooltip: 'Paste URL',
                              onPressed: () async {
                                final data = await Clipboard.getData(Clipboard.kTextPlain);
                                if (data?.text != null && data!.text!.isNotEmpty) {
                                  urlController.text = data.text!.trim();
                                  setDialogState(() => previewUrl = urlController.text);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      onChanged: (val) => setDialogState(() => previewUrl = val.trim()),
                    ),
                    const SizedBox(height: 10),
                    if (isLiked && previewUrl.isNotEmpty)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.restart_alt_rounded, size: 16),
                        label: const Text('Reset to Default Purple Heart'),
                        onPressed: () {
                          urlController.clear();
                          setDialogState(() => previewUrl = '');
                        },
                      )
                    else if (_playlist.tracks.isNotEmpty && !isLiked)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: const Text('Auto-detect from Track 1'),
                        onPressed: () async {
                          try {
                            final first = _playlist.tracks.first;
                            final query = '${first.artist} ${first.title} audio';
                            final res = await YoutubeService().search(query);
                            if (res.isNotEmpty) {
                              final thumb = 'https://img.youtube.com/vi/${res.first.id.value}/hqdefault.jpg';
                              urlController.text = thumb;
                              setDialogState(() => previewUrl = thumb);
                            }
                          } catch (_) {}
                        },
                      ),
                    if (trackThumbs.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Covers from Songs in Playlist:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFAAAAAA)),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 56,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: trackThumbs.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final p = trackThumbs[i];
                            final isSelected = previewUrl == p.url;
                            return GestureDetector(
                              onTap: () {
                                urlController.text = p.url;
                                setDialogState(() => previewUrl = p.url);
                              },
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF1DB954) : const Color(0xFF383838),
                                    width: isSelected ? 2.5 : 1,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(p.url, fit: BoxFit.cover),
                                    if (isSelected)
                                      Container(
                                        color: Colors.black45,
                                        child: const Icon(Icons.check, color: Color(0xFF1DB954), size: 20),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final nav = Navigator.of(dialogCtx);
                  final messenger = ScaffoldMessenger.of(context);
                  final newTitle = titleController.text.trim();
                  final newThumb = urlController.text.trim();
                  final updated = _playlist.copyWith(
                    title: isLiked ? 'Liked Songs' : (newTitle.isNotEmpty ? newTitle : _playlist.title),
                    thumbnailUrl: newThumb,
                  );
                  await widget.playlistService.savePlaylist(updated);
                  if (!mounted) return;
                  setState(() => _playlist = updated);
                  nav.pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Playlist cover updated!')),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _downloadAllTracks() async {
    final tracks = _playlist.tracks;
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks in playlist to download')),
      );
      return;
    }
    final converted = tracks.map(Track.fromLocalPlaylistTrack).toList();

    DownloadService.instance.downloadTracks(converted);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading ${tracks.length} songs for offline listening…'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DownloadsScreen(
                    playerService: widget.playerService,
                    settingsService: widget.settingsService ?? SettingsService.instance!,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> _addAllToLikedSongs() async {
    final count = await widget.playlistService.addAllToLikedSongs(_playlist.tracks);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0 ? 'Added $count songs to Liked Songs!' : 'All songs are already in Liked Songs!'),
          backgroundColor: const Color(0xFF1DB954),
        ),
      );
    }
  }

  String _fmtDuration(Duration d) {
    if (d == Duration.zero) return '';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _indexBox(int num) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          '$num',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF888888),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSpotify = _playlist.isSpotify;
    final sortedTracks = _getSortedTracks();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: const Color(0xFF121212),
            actions: [
              if (!_playlist.isLikedSongs)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit Cover & Title',
                  onPressed: _showEditPlaylistDialog,
                ),
              if (isSpotify)
                IconButton(
                  icon: _syncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1DB954)),
                        )
                      : const Icon(Icons.sync),
                  tooltip: 'Sync with Spotify',
                  onPressed: _syncing ? null : _sync,
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (val) {
                  switch (val) {
                    case 'sort':
                      _showSortModal();
                      break;
                    case 'edit':
                      _showEditPlaylistDialog();
                      break;
                    case 'download_all':
                      _downloadAllTracks();
                      break;
                    case 'add_to_liked':
                      _addAllToLikedSongs();
                      break;
                    case 'auto_cover':
                      _autoFetchCoverIfMissing(force: true);
                      break;
                    case 'fetch_artworks':
                      _fetchTrackArtworks();
                      break;
                    case 'delete':
                      _deletePlaylist();
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'sort',
                    child: Row(
                      children: [
                        Icon(Icons.sort_rounded, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text('Sort Tracks')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.image_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_playlist.isLikedSongs ? 'Change Cover Picture' : 'Edit Cover & Title')),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'download_all',
                    child: Row(
                      children: [
                        Icon(Icons.download_rounded, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text('Download Playlist')),
                      ],
                    ),
                  ),
                  if (!_playlist.isLikedSongs)
                    const PopupMenuItem(
                      value: 'add_to_liked',
                      child: Row(
                        children: [
                          Icon(Icons.favorite_rounded, color: Color(0xFFFF5252), size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Add All to Liked Songs')),
                        ],
                      ),
                    ),
                  if (!_playlist.isLikedSongs)
                    const PopupMenuItem(
                      value: 'auto_cover',
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Auto-fetch Cover Art')),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'fetch_artworks',
                    child: Row(
                      children: [
                        Icon(Icons.image_search_rounded, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text('Fetch Track Artworks')),
                      ],
                    ),
                  ),
                  if (!_playlist.isLikedSongs) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: Color(0xFFCF6679), size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Delete Playlist', style: TextStyle(color: Color(0xFFCF6679)))),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Text(
                _playlist.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: GestureDetector(
                onTap: _showEditPlaylistDialog,
                child: _playlist.thumbnailUrl.isNotEmpty
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            _playlist.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: isSpotify ? const Color(0xFF0D2513) : const Color(0xFF1A1A2E),
                            ),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0xFF121212)],
                              ),
                            ),
                          ),
                        ],
                      )
                    : (_playlist.isLikedSongs
                        ? Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.favorite_rounded, size: 68, color: Colors.white),
                                  SizedBox(height: 8),
                                  Text(
                                    'Liked Songs',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Tap to customize cover',
                                    style: TextStyle(color: Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Container(
                            color: isSpotify ? const Color(0xFF0D2513) : const Color(0xFF1A1A2E),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isSpotify ? Icons.graphic_eq : Icons.queue_music_rounded,
                                    size: 54,
                                    color: isSpotify ? const Color(0xFF1DB954) : const Color(0xFF555555),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.edit, size: 12, color: Color(0xFFAAAAAA)),
                                        SizedBox(width: 4),
                                        Text('Tap to customize cover', style: TextStyle(fontSize: 11, color: Color(0xFFAAAAAA))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _playAll,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text('Play all (${_playlist.trackCount})'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _playAll(shuffle: true),
                        icon: const Icon(Icons.shuffle, size: 16),
                        label: const Text('Shuffle'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _downloadAllTracks,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: Text('Download (${_playlist.trackCount})'),
                      ),
                      if (!_playlist.isLikedSongs)
                        OutlinedButton.icon(
                          onPressed: _addAllToLikedSongs,
                          icon: const Icon(Icons.favorite_rounded, size: 16, color: Color(0xFFFF5252)),
                          label: const Text('Add all to Liked'),
                        ),
                      OutlinedButton.icon(
                        onPressed: _showSortModal,
                        icon: const Icon(Icons.sort_rounded, size: 16),
                        label: Text(_getSortButtonLabel()),
                      ),
                      if (isSpotify)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1DB954).withAlpha(40),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.graphic_eq, size: 14, color: Color(0xFF1DB954)),
                              SizedBox(width: 4),
                              Text(
                                'Spotify',
                                style: TextStyle(
                                  color: Color(0xFF1DB954),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (_playlist.lastSyncedAt != null && isSpotify) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Last synced: ${_playlist.lastSyncedAt!.toLocal().toString().split('.').first}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF777777)),
                    ),
                  ],
                  if (_playlist.tracks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search songs or artists…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          () {
                            final count = sortedTracks.where((t) {
                              final q = _searchQuery.toLowerCase();
                              return t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q);
                            }).length;
                            return 'Found $count of ${_playlist.tracks.length} songs';
                          }(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1DB954),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          () {
            final displayedTracks = _searchQuery.isEmpty
                ? sortedTracks
                : sortedTracks.where((t) {
                    final q = _searchQuery.toLowerCase();
                    return t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q);
                  }).toList();

            if (_playlist.tracks.isEmpty) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text('No tracks in this playlist.', style: TextStyle(color: Color(0xFF707070))),
                  ),
                ),
              );
            }

            if (displayedTracks.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text('No songs matching "$_searchQuery"', style: const TextStyle(color: Color(0xFF707070))),
                  ),
                ),
              );
            }

            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final track = displayedTracks[index];
                    final sortedIndex = sortedTracks.indexOf(track);
                    final durStr = _fmtDuration(track.duration);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFF222222)),
                      ),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
                              ? Image.network(
                                  track.thumbnailUrl!,
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      _indexBox(sortedIndex >= 0 ? sortedIndex + 1 : index + 1),
                                )
                              : _indexBox(sortedIndex >= 0 ? sortedIndex + 1 : index + 1),
                        ),
                        title: Text(
                          track.title,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: GestureDetector(
                          onTap: (widget.authService != null && widget.settingsService != null)
                              ? () {
                                  navigateToArtistOrShowPicker(
                                    context: context,
                                    artists: track.individualArtists,
                                    playerService: widget.playerService,
                                    authService: widget.authService!,
                                    playlistService: widget.playlistService,
                                    settingsService: widget.settingsService!,
                                    trackTitle: track.title,
                                    initialImageUrl: track.thumbnailUrl,
                                  );
                                }
                              : null,
                          child: Text(
                            durStr.isNotEmpty ? '${track.formattedArtist} · $durStr' : track.formattedArtist,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onLongPress: () => _showTrackOptions(track),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Builder(
                              builder: (ctx) {
                                final isLiked = widget.playlistService.isTrackLiked(
                                  track.youtubeVideoId,
                                  track.title,
                                  track.artist,
                                );
                                return IconButton(
                                  icon: Icon(
                                    isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    color: isLiked ? const Color(0xFFFF5252) : const Color(0xFF888888),
                                    size: 20,
                                  ),
                                  tooltip: isLiked ? 'In Liked Songs' : 'Save to playlist',
                                  onPressed: () {
                                    showAddToPlaylistSheet(
                                      context: context,
                                      track: track,
                                      playlistService: widget.playlistService,
                                      accentColor: theme.colorScheme.primary,
                                    );
                                  },
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert_rounded, size: 20),
                              color: const Color(0xFF888888),
                              tooltip: 'More options',
                              onPressed: () => _showTrackOptions(track),
                            ),
                            IconButton(
                              icon: const Icon(Icons.play_arrow_rounded),
                              color: theme.colorScheme.primary,
                              onPressed: () => _playTrack(sortedIndex >= 0 ? sortedIndex : index),
                            ),
                          ],
                        ),
                        onTap: () => _playTrack(sortedIndex >= 0 ? sortedIndex : index),
                      ),
                    );
                  },
                  childCount: displayedTracks.length,
                ),
              ),
            );
          }(),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ======================================================================
// Music list tile
// ======================================================================

class _MusicListTile extends StatelessWidget {
  final PlaylistVideo video;
  final Color accentColor;
  final PlaylistService playlistService;
  final VoidCallback onPlay;
  final PlayerService? playerService;

  const _MusicListTile({
    required this.video,
    required this.accentColor,
    required this.playlistService,
    required this.onPlay,
    this.playerService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLiked = playlistService.isTrackLiked(
      video.videoId,
      video.title,
      video.channelTitle,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: video.thumbnailUrl.isNotEmpty
                    ? SizedBox(
                        width: 64,
                        height: 64,
                        child: Image.network(
                          video.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 64,
                            height: 64,
                            color: const Color(0xFF2A2A2A),
                            child: Icon(Icons.music_note, color: accentColor.withAlpha(120)),
                          ),
                        ),
                      )
                    : Container(
                        width: 64,
                        height: 64,
                        color: const Color(0xFF2A2A2A),
                        child: Icon(Icons.music_note, color: accentColor.withAlpha(120)),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFE6E6E6),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (video.channelTitle.isNotEmpty) video.channelTitle,
                        if (video.duration > Duration.zero) _fmtDuration(video.duration),
                      ].join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Heart / Save to Playlist Button
              IconButton(
                icon: Icon(
                  isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isLiked
                      ? const Color(0xFFFF5252)
                      : theme.colorScheme.onSurfaceVariant.withAlpha(180),
                  size: 22,
                ),
                tooltip: isLiked ? 'In Liked Songs' : 'Save to playlist',
                onPressed: () {
                  showAddToPlaylistSheet(
                    context: context,
                    track: LocalPlaylistTrack(
                      title: video.title,
                      artist: video.channelTitle,
                      youtubeVideoId: video.videoId,
                      thumbnailUrl: video.thumbnailUrl,
                      duration: video.duration,
                    ),
                    playlistService: playlistService,
                    accentColor: accentColor,
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: onPlay,
                color: accentColor,
                iconSize: 26,
              ),
              // 3-dots More Actions Menu (ArchiveTune style)
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                iconSize: 20,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(200),
                tooltip: 'More actions',
                onPressed: () {
                  final localTrack = LocalPlaylistTrack(
                    title: video.title,
                    artist: video.channelTitle,
                    youtubeVideoId: video.videoId,
                    thumbnailUrl: video.thumbnailUrl,
                    duration: video.duration,
                  );
                  final playerTrack = Track.fromPlaylistVideo(
                    videoId: video.videoId,
                    title: video.title,
                    author: video.channelTitle,
                    duration: video.duration,
                    thumbnailUrl: video.thumbnailUrl,
                  );

                  showModalBottomSheet(
                    context: context,
                    backgroundColor: theme.colorScheme.surface,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (sheetCtx) {
                      final sheetTheme = Theme.of(sheetCtx);
                      return SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 36,
                              height: 4,
                              margin: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: sheetTheme.colorScheme.onSurface.withAlpha(40),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: video.thumbnailUrl.isNotEmpty
                                    ? Image.network(
                                        video.thumbnailUrl,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          width: 44,
                                          height: 44,
                                          color: Colors.black26,
                                          child: const Icon(Icons.music_note, size: 20),
                                        ),
                                      )
                                    : Container(
                                        width: 44,
                                        height: 44,
                                        color: Colors.black26,
                                        child: const Icon(Icons.music_note, size: 20),
                                      ),
                              ),
                              title: Text(
                                video.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                video.channelTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Divider(height: 1),
                            if (playerService != null) ...[
                              ListTile(
                                leading: const Icon(Icons.playlist_play_rounded),
                                title: const Text('Play next'),
                                onTap: () {
                                  Navigator.pop(sheetCtx);
                                  playerService!.playNext(playerTrack);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Playing next: ${video.title}')),
                                  );
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.queue_music_rounded),
                                title: const Text('Add to queue'),
                                onTap: () {
                                  Navigator.pop(sheetCtx);
                                  playerService!.addTracksToQueue([playerTrack]);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Added to queue: ${video.title}')),
                                  );
                                },
                              ),
                            ],
                            ListTile(
                              leading: const Icon(Icons.download_rounded),
                              title: const Text('Download'),
                              onTap: () {
                                Navigator.pop(sheetCtx);
                                DownloadService.instance.startDownload(playerTrack);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Downloading "${video.title}"…')),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.playlist_add_rounded),
                              title: const Text('Add to playlist'),
                              onTap: () {
                                Navigator.pop(sheetCtx);
                                showAddToPlaylistSheet(
                                  context: context,
                                  track: localTrack,
                                  playlistService: playlistService,
                                  accentColor: accentColor,
                                );
                              },
                            ),
                            ListTile(
                              leading: Icon(
                                isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                color: isLiked ? const Color(0xFFFF5252) : null,
                              ),
                              title: Text(isLiked ? 'Remove from Liked Songs' : 'Like'),
                              onTap: () {
                                Navigator.pop(sheetCtx);
                                playlistService.toggleLikeTrack(localTrack);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isLiked
                                          ? 'Removed from Liked Songs'
                                          : 'Added to Liked Songs',
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDuration(Duration d) {
    if (d == Duration.zero) return '';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}


// ======================================================================
// Playlist Detail Screen
// ======================================================================

class PlaylistDetailScreen extends StatefulWidget {
  final UserPlaylist playlist;
  final PlayerService playerService;
  final GoogleAuthService authService;
  final PlaylistService playlistService;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.playerService,
    required this.authService,
    required this.playlistService,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<PlaylistVideo> _videos = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVideos() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final videos = await widget.authService.fetchPlaylistVideos(
        widget.playlist.id,
        maxResults: 200,
      );
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load playlist: $e';
      });
    }
  }

  Future<void> _playVideo(PlaylistVideo video) async {
    try {
      final index = _videos.indexOf(video);
      await widget.playerService.playVideos(
        _videos.map((v) => (
          videoId: v.videoId,
          title: v.title,
          author: v.channelTitle,
          duration: v.duration,
        )).toList(),
        startIndex: index >= 0 ? index : 0,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Now playing: ${video.title}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to play: $e')),
      );
    }
  }

  Future<void> _playAll() async {
    if (_videos.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing ${_videos.length} songs…'),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      await widget.playerService.playVideos(
        _videos.map((v) => (
          videoId: v.videoId,
          title: v.title,
          author: v.channelTitle,
          duration: v.duration,
        )).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start playback: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        slivers: [
          // ---- Collapsing header ----
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: const Color(0xFF121212),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Text(
                widget.playlist.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: widget.playlist.thumbnailUrl.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          widget.playlist.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                        // Gradient overlay for readability
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xFF121212)],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: const Color(0xFF1A1A2E),
                      child: const Center(
                        child: Icon(Icons.queue_music_rounded, size: 64, color: Color(0xFF444444)),
                      ),
                    ),
            ),
          ),
          // ---- Play all button and search ----
          if (_videos.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _playAll,
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: Text('Play all (${_videos.length})'),
                        ),
                        const Spacer(),
                        Text(
                          'Music only · ${_videos.length} songs',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search songs or channels…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          () {
                            final count = _videos.where((v) {
                              final q = _searchQuery.toLowerCase();
                              return v.title.toLowerCase().contains(q) || v.channelTitle.toLowerCase().contains(q);
                            }).length;
                            return 'Found $count of ${_videos.length} songs';
                          }(),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // ---- Loading / error / list ----
          () {
            if (_loading) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            if (_error != null) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Center(
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              );
            }
            if (_videos.isEmpty) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text('No music videos in this playlist.',
                        style: TextStyle(color: Color(0xFF707070))),
                  ),
                ),
              );
            }

            final displayedVideos = _searchQuery.isEmpty
                ? _videos
                : _videos.where((v) {
                    final q = _searchQuery.toLowerCase();
                    return v.title.toLowerCase().contains(q) || v.channelTitle.toLowerCase().contains(q);
                  }).toList();

            if (displayedVideos.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Center(
                    child: Text('No songs matching "$_searchQuery"',
                        style: const TextStyle(color: Color(0xFF707070))),
                  ),
                ),
              );
            }

            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final video = displayedVideos[index];
                    return _MusicListTile(
                      video: video,
                      accentColor: theme.colorScheme.primary,
                      playlistService: widget.playlistService,
                      playerService: widget.playerService,
                      onPlay: () => _playVideo(video),
                    );
                  },
                  childCount: displayedVideos.length,
                ),
              ),
            );
          }(),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}