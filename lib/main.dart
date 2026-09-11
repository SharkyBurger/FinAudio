import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'services/settings_service.dart';
import 'services/player_service.dart';
import 'services/google_auth_service.dart';
import 'widgets/now_playing_bar.dart';
import 'ui/now_playing_screen.dart';
import 'ui/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const FinAudioApp());
}

// ======================================================================
// App root
// ======================================================================

class FinAudioApp extends StatefulWidget {
  const FinAudioApp({super.key});

  @override
  State<FinAudioApp> createState() => _FinAudioAppState();
}

class _FinAudioAppState extends State<FinAudioApp> {
  late final SettingsService _settings;
  late final PlayerService _playerService;
  late final GoogleAuthService _authService;

  Color _accentColor = const Color(0xFFCC0000);
  int _darkIntensity = 1;

  @override
  void initState() {
    super.initState();
    _settings = SettingsService();
    _playerService = PlayerService();
    _authService = GoogleAuthService();
    _init();
  }

  Future<void> _init() async {
    await _settings.init();
    await _authService.initialize();
    if (mounted) {
      setState(() {
        _accentColor = _settings.accentColor;
        _darkIntensity = _settings.darkIntensity;
      });
    }
  }

  ThemeData _buildTheme() {
    final base = _darkIntensityTheme();
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: _accentColor,
        onPrimary: _onPrimaryFor(_accentColor),
        primaryContainer: _accentColor.withAlpha(40),
        onPrimaryContainer: _accentColor,
        secondary: _accentColor.withAlpha(220),
        tertiary: _accentColor.withAlpha(160),
        outline: _accentColor.withAlpha(120),
        outlineVariant: _accentColor.withAlpha(60),
        surface: const Color(0xFF121212),
        onSurface: const Color(0xFFE6E6E6),
        surfaceContainerHighest:
            _darkIntensity == 2 ? const Color(0xFF1A1A1A) : const Color(0xFF242424),
        error: const Color(0xFFCF6679),
        shadow: Colors.transparent,
      ),
      textTheme: _textThemeFor(_darkIntensity),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A2A2A),
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _accentColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: const IconThemeData(
        color: Color(0xFFB0B0B0),
        size: 24,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF555555)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: Color(0xFF707070)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentColor,
          foregroundColor: _onPrimaryFor(_accentColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFCACACA),
          side: const BorderSide(color: Color(0xFF3A3A3A)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _accentColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: const Color(0xFFCACACA),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF121212),
        selectedItemColor: Color(0xFFE6E6E6),
        unselectedItemColor: Color(0xFF6E6E6E),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  ThemeData _darkIntensityTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      colorScheme: ColorScheme.dark(
        surface: const Color(0xFF0A0A0A),
        onSurface: const Color(0xFFE6E6E6),
      ),
    );
  }

  Color _onPrimaryFor(Color accent) {
    if (accent.computeLuminance() > 0.5) {
      return const Color(0xFF101010);
    }
    return const Color(0xFFFFFFFF);
  }

  TextTheme _textThemeFor(int intensity) {
    final base = ThemeData.dark().textTheme;
    const baseColor = Color(0xFFE6E6E6);
    const mutedColor = Color(0xFF9E9E9E);
    const dimColor = Color(0xFF6E6E6E);

    return base.apply(
      bodyColor: baseColor,
      displayColor: baseColor,
    ).copyWith(
      bodyLarge: base.bodyLarge?.copyWith(color: baseColor),
      bodyMedium: base.bodyMedium?.copyWith(color: baseColor),
      bodySmall: base.bodySmall?.copyWith(color: mutedColor),
      labelLarge: base.labelLarge?.copyWith(color: baseColor),
      labelMedium: base.labelMedium?.copyWith(color: mutedColor),
      labelSmall: base.labelSmall?.copyWith(color: dimColor),
      titleLarge: base.titleLarge?.copyWith(color: baseColor),
      titleMedium: base.titleMedium?.copyWith(color: baseColor),
      titleSmall: base.titleSmall?.copyWith(color: mutedColor),
      headlineMedium: base.headlineMedium?.copyWith(color: baseColor),
      headlineSmall: base.headlineSmall?.copyWith(color: baseColor),
    );
  }

  @override
  void dispose() {
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
        accentColor: _accentColor,
        playerService: _playerService,
        authService: _authService,
        settingsService: _settings,
        onSettingsChanged: () {
          if (mounted) {
            setState(() {
              _accentColor = _settings.accentColor;
              _darkIntensity = _settings.darkIntensity;
            });
          }
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
  final SettingsService settingsService;
  final VoidCallback onSettingsChanged;

  const _MainScaffold({
    required this.accentColor,
    required this.playerService,
    required this.authService,
    required this.settingsService,
    required this.onSettingsChanged,
  });

  @override
  State<_MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<_MainScaffold> {
  int _currentIndex = 0;
  Track? _nowPlaying;

  @override
  void initState() {
    super.initState();
    widget.playerService.nowPlayingStream.listen((track) {
      if (mounted) {
        setState(() => _nowPlaying = track);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex.clamp(0, 2),
        children: [
          PlayerTab(
            playerService: widget.playerService,
            accentColor: widget.accentColor,
          ),
          PlaylistsTab(
            playerService: widget.playerService,
            authService: widget.authService,
          ),
          SettingsScreen(
            key: const ValueKey('settings'),
            settingsService: widget.settingsService,
            onChanged: widget.onSettingsChanged,
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_nowPlaying != null) NowPlayingBar(
            track: _nowPlaying!,
            accentColor: widget.accentColor,
            playerService: widget.playerService,
          ),
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() => _currentIndex = i),
            elevation: 0,
            backgroundColor: const Color(0xFF121212),
            indicatorColor: widget.accentColor.withAlpha(80),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.music_note_outlined),
                selectedIcon: Icon(Icons.music_note),
                label: 'Player',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music_outlined),
                selectedIcon: Icon(Icons.queue_music),
                label: 'Playlists',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ],
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _errorSub = widget.playerService.errorStream.listen((msg) {
      if (mounted) {
        setState(() => _error = msg);
      }
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
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
                hintText: 'Paste a YouTube URL…',
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
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
            'Paste a YouTube URL above to start',
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
          const SizedBox(height: 16),

          // ---- Album art ----
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => NowPlayingScreen(
                    playerService: widget.playerService,
                    accentColor: widget.accentColor,
                  ),
                  transitionsBuilder: (_, anim, __, child) {
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
          const SizedBox(height: 24),

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
      child: track.id.isNotEmpty
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

class PlaylistsTab extends StatefulWidget {
  final PlayerService playerService;
  final GoogleAuthService authService;

  const PlaylistsTab({
    super.key,
    required this.playerService,
    required this.authService,
  });

  @override
  State<PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<PlaylistsTab> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<UserPlaylist> _playlists = [];
  List<PlaylistVideo> _searchResults = [];
  bool _loadingPlaylists = false;
  bool _loadingSearch = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.authService.isSignedIn) {
      _loadPlaylists();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _isSignedIn => widget.authService.isSignedIn;

  Future<void> _handleSignIn() async {
    setState(() {
      _loadingPlaylists = true;
      _error = null;
    });
    try {
      await widget.authService.signIn();
      if (!mounted) return;
      if (!widget.authService.isSignedIn) {
        setState(() {
          _loadingPlaylists = false;
          _error = 'Sign-in was cancelled or failed.';
        });
        return;
      }
      await _loadPlaylists();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPlaylists = false;
        _error = 'Sign-in or playlist fetch failed: $e';
      });
    }
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _loadingPlaylists = true;
      _error = null;
    });
    try {
      final playlists = await widget.authService.fetchPlaylists();
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _loadingPlaylists = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPlaylists = false;
        _error = 'Could not load playlists: $e';
      });
    }
  }

  Future<void> _handleSignOut() async {
    await widget.authService.signOut();
    if (mounted) {
      setState(() {
        _playlists = [];
        _searchResults = [];
      });
    }
  }

  void _openPlaylist(UserPlaylist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(
          playlist: playlist,
          playerService: widget.playerService,
          authService: widget.authService,
        ),
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchMusic(value.trim());
    });
  }

  Future<void> _searchMusic(String query) async {
    if (query.isEmpty) return;
    setState(() {
      _loadingSearch = true;
      _error = null;
    });
    try {
      final results = await widget.authService.searchMusic(query: query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _loadingSearch = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSearch = false;
        _error = 'Search failed: $e';
      });
    }
  }

  Future<void> _playVideo(PlaylistVideo video) async {
    try {
      await widget.playerService.play(video.youtubeUrl);
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

  Future<void> _playAllSearch(List<PlaylistVideo> videos) async {
    if (videos.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing ${videos.length} songs…'), duration: const Duration(seconds: 2)),
    );
    try {
      await widget.playerService.play(videos.first.youtubeUrl);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start playback: $e')),
      );
      return;
    }
    for (final video in videos.skip(1)) {
      try {
        await widget.playerService.play(video.youtubeUrl, replaceQueue: false);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Your Music',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // ---- Auth section ----
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _AuthSection(
                isSignedIn: _isSignedIn,
                onSignIn: _handleSignIn,
                onSignOut: _handleSignOut,
                authService: widget.authService,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          // ---- Search bar ----
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search music…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchResults = []);
                          },
                        )
                      : null,
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          // ---- Status / errors ----
          if (_loadingPlaylists || _loadingSearch)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            )
          else if (_isSignedIn && _playlists.isEmpty && _searchResults.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Text(
                  'No playlists found. Create a playlist on YouTube to get started.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          // ---- Playlists grid ----
          if (_playlists.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Playlists (${_playlists.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: _loadPlaylists,
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final playlist = _playlists[index];
                    return _PlaylistCard(
                      playlist: playlist,
                      onTap: () => _openPlaylist(playlist),
                    );
                  },
                  childCount: _playlists.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
          // ---- Search results section ----
          if (_searchResults.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Search results (${_searchResults.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: () => _playAllSearch(_searchResults),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Play all'),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchResults = []);
                      },
                      tooltip: 'Clear search',
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final video = _searchResults[index];
                    return _MusicListTile(
                      video: video,
                      accentColor: theme.colorScheme.primary,
                      onPlay: () => _playVideo(video),
                    );
                  },
                  childCount: _searchResults.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ======================================================================
// Auth section
// ======================================================================

class _AuthSection extends StatelessWidget {
  final bool isSignedIn;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  final GoogleAuthService authService;

  const _AuthSection({
    required this.isSignedIn,
    required this.onSignIn,
    required this.onSignOut,
    required this.authService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return isSignedIn
        ? Row(
            children: [
              if (authService.currentUser?.photoUrl != null)
                CircleAvatar(
                  backgroundImage: NetworkImage(authService.currentUser!.photoUrl!),
                  radius: 16,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authService.currentUser?.displayName ?? '',
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      authService.currentUser?.email ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onSignOut,
                child: const Text('Sign out'),
              ),
            ],
          )
        : FilledButton.icon(
            onPressed: onSignIn,
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          );
  }
}

// ======================================================================
// Music list tile
// ======================================================================

class _MusicListTile extends StatelessWidget {
  final PlaylistVideo video;
  final Color accentColor;
  final VoidCallback onPlay;

  const _MusicListTile({
    required this.video,
    required this.accentColor,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                      video.channelTitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: onPlay,
                color: accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// Playlist card (grid item)
// ======================================================================

class _PlaylistCard extends StatelessWidget {
  final UserPlaylist playlist;
  final VoidCallback onTap;

  const _PlaylistCard({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail
            Expanded(
              child: playlist.thumbnailUrl.isNotEmpty
                  ? Image.network(
                      playlist.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFF1A1A2E),
                        child: Icon(
                          Icons.queue_music_rounded,
                          size: 40,
                          color: theme.colorScheme.primary.withAlpha(100),
                        ),
                      ),
                    )
                  : Container(
                      color: const Color(0xFF1A1A2E),
                      child: Icon(
                        Icons.queue_music_rounded,
                        size: 40,
                        color: theme.colorScheme.primary.withAlpha(100),
                      ),
                    ),
            ),
            // Title + count
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
                  Text(
                    '${playlist.videoCount} songs',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Playlist Detail Screen
// ======================================================================

class PlaylistDetailScreen extends StatefulWidget {
  final UserPlaylist playlist;
  final PlayerService playerService;
  final GoogleAuthService authService;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.playerService,
    required this.authService,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<PlaylistVideo> _videos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVideos();
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
      await widget.playerService.play(video.youtubeUrl);
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
      await widget.playerService.play(_videos.first.youtubeUrl);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start playback: $e')),
      );
      return;
    }
    for (final video in _videos.skip(1)) {
      try {
        await widget.playerService.play(video.youtubeUrl, replaceQueue: false);
      } catch (_) {}
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
          // ---- Play all button ----
          if (_videos.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
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
              ),
            ),
          // ---- Loading / error ----
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Center(
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            )
          else if (_videos.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                  child: Text('No music videos in this playlist.',
                      style: TextStyle(color: Color(0xFF707070))),
                ),
              ),
            )
          else
            // ---- Song list ----
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final video = _videos[index];
                    return _MusicListTile(
                      video: video,
                      accentColor: theme.colorScheme.primary,
                      onPlay: () => _playVideo(video),
                    );
                  },
                  childCount: _videos.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
