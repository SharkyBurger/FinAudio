import 'package:flutter/material.dart';

import 'package:finaudio/services/settings_service.dart';
import 'package:finaudio/services/google_auth_service.dart';
import 'package:finaudio/ui/appearance_screen.dart';
import 'package:finaudio/ui/lyrics_settings_screen.dart';
import 'package:finaudio/widgets/google_sign_in_dialog.dart';
import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:finaudio/services/discord_rpc_service.dart';
import 'package:finaudio/widgets/discord_login_dialog.dart';
import 'package:finaudio/services/crash_log_service.dart';

/// Settings screen for FinAudio.
/// Provides:
/// - Google Account management (playlists and sync)
/// - Theme & Appearance navigation tile (opens AppearanceScreen)
/// - App Information
class SettingsScreen extends StatefulWidget {
  final SettingsService settingsService;
  final GoogleAuthService authService;
  final VoidCallback? onChanged;
  final VoidCallback? onAuthChanged;

  const SettingsScreen({
    super.key,
    required this.settingsService,
    required this.authService,
    this.onChanged,
    this.onAuthChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsService _settings = widget.settingsService;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsUpdated);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsUpdated);
    super.dispose();
  }

  void _onSettingsUpdated() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _settings.accentColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _SectionHeader(title: 'Google Account'),
          const SizedBox(height: 12),
          _GoogleAccountSection(
            authService: widget.authService,
            accentColor: accentColor,
            onAuthChanged: () {
              if (mounted) setState(() {});
              widget.onAuthChanged?.call();
            },
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Spotify Integration'),
          const SizedBox(height: 12),
          _SpotifySection(
            settingsService: _settings,
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Appearance'),
          const SizedBox(height: 12),
          _AppearanceNavigationTile(
            settingsService: _settings,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AppearanceScreen(
                    settingsService: _settings,
                    onChanged: widget.onChanged,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Lyrics'),
          const SizedBox(height: 12),
          _LyricsNavigationTile(
            settingsService: _settings,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LyricsSettingsScreen(
                    settingsService: _settings,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Discord Rich Presence'),
          const SizedBox(height: 12),
          _DiscordSection(
            settingsService: _settings,
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Audio Quality'),
          const SizedBox(height: 12),
          _AudioQualitySection(
            settingsService: _settings,
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'About'),
          const SizedBox(height: 12),
          _AboutSection(),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Diagnostics & Logs'),
          const SizedBox(height: 12),
          _CrashLogsTile(accentColor: accentColor),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _AppearanceNavigationTile extends StatelessWidget {
  final SettingsService settingsService;
  final VoidCallback onTap;

  const _AppearanceNavigationTile({
    required this.settingsService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = settingsService.backgroundColor;
    final surface = settingsService.surfaceColor;
    final accent = settingsService.accentColor;
    final text = settingsService.textColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(50),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withAlpha(35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.palette_outlined,
                color: accent,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme & Appearance',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Customize background, cards, buttons & text',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Preview mini palette dots
            Row(
              children: [
                _colorDot(bg),
                const SizedBox(width: 3),
                _colorDot(surface),
                const SizedBox(width: 3),
                _colorDot(accent),
                const SizedBox(width: 3),
                _colorDot(text),
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorDot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withAlpha(70),
          width: 0.8,
        ),
      ),
    );
  }
}

class _LyricsNavigationTile extends StatelessWidget {
  final SettingsService settingsService;
  final VoidCallback onTap;

  const _LyricsNavigationTile({
    required this.settingsService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(50),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFCEB2FF).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFFCEB2FF),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lyrics',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Mode (${settingsService.lyricsMode}), animations, providers, romanization',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscordSection extends StatelessWidget {
  final SettingsService settingsService;

  const _DiscordSection({required this.settingsService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = settingsService.discordRpcEnabled;
    const discordColor = Color(0xFF5865F2);
    final isDesktop = DiscordRPC.isAvailable;
    final isMobileConnected = settingsService.isDiscordConnectedOnMobile;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? discordColor.withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main toggle header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: discordColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.headset_mic_rounded,
                    color: discordColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Discord Rich Presence',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: discordColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: discordColor.withValues(alpha: 0.4), width: 0.5),
                            ),
                            child: Text(
                              isDesktop ? 'PC IPC' : 'Mobile Gateway',
                              style: const TextStyle(
                                color: discordColor,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        enabled
                            ? (isDesktop
                                ? 'Broadcasting to local Discord desktop client'
                                : (isMobileConnected
                                    ? 'Broadcasting as @${settingsService.discordUsername}'
                                    : 'Connect account to broadcast on mobile'))
                            : 'Status broadcasting disabled',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  activeThumbColor: discordColor,
                  activeTrackColor: discordColor.withValues(alpha: 0.35),
                  onChanged: (val) => settingsService.setDiscordRpcEnabled(val),
                ),
              ],
            ),
          ),

          if (enabled) ...[
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: theme.colorScheme.outlineVariant.withAlpha(50),
            ),

            // Platform Specific Status / Connection Card
            if (isDesktop) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: DiscordRpcService.instance.isDesktopConnected
                            ? const Color(0xFF23A55A) // Discord Green
                            : Colors.orangeAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        DiscordRpcService.instance.isDesktopConnected
                            ? 'Connected to Discord Desktop application'
                            : 'Waiting for Discord Desktop application to open...',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Mobile Gateway Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: isMobileConnected
                    ? Row(
                        children: [
                          if (settingsService.discordAvatar != null &&
                              settingsService.discordUserId != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.network(
                                'https://cdn.discordapp.com/avatars/${settingsService.discordUserId}/${settingsService.discordAvatar}.png',
                                width: 36,
                                height: 36,
                                errorBuilder: (_, _, _) => const CircleAvatar(
                                  radius: 18,
                                  backgroundColor: discordColor,
                                  child: Icon(Icons.person, color: Colors.white, size: 20),
                                ),
                              ),
                            )
                          else
                            const CircleAvatar(
                              radius: 18,
                              backgroundColor: discordColor,
                              child: Icon(Icons.person, color: Colors.white, size: 20),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        settingsService.discordUsername ?? 'Discord User',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF23A55A),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Connected to Discord Gateway',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => settingsService.disconnectDiscordAccount(),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Connect your Discord account to display your listening status on mobile.',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            icon: const Icon(Icons.login_rounded, size: 16),
                            label: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: FilledButton.styleFrom(
                              backgroundColor: discordColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            onPressed: () => showDiscordLoginDialog(
                              context: context,
                              settingsService: settingsService,
                            ),
                          ),
                        ],
                      ),
              ),
            ],

            Divider(
              height: 1,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: theme.colorScheme.outlineVariant.withAlpha(50),
            ),

            // Options: Show Timestamps
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show playback timer',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Displays elapsed & remaining time progress bar',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Checkbox(
                    value: settingsService.discordShowTimestamps,
                    activeColor: discordColor,
                    onChanged: (v) => settingsService.setDiscordShowTimestamps(v ?? true),
                  ),
                ],
              ),
            ),

            // Options: Show YouTube Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show "Listen on YouTube" button',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Allows others to open the song directly from your profile',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Checkbox(
                    value: settingsService.discordShowButtons,
                    activeColor: discordColor,
                    onChanged: (v) => settingsService.setDiscordShowButtons(v ?? true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _SpotifySection extends StatefulWidget {
  final SettingsService settingsService;

  const _SpotifySection({required this.settingsService});

  @override
  State<_SpotifySection> createState() => _SpotifySectionState();
}

class _SpotifySectionState extends State<_SpotifySection> {
  bool _expanded = false;
  late final TextEditingController _clientIdController;
  late final TextEditingController _clientSecretController;
  bool _obscureSecret = true;

  @override
  void initState() {
    super.initState();
    _clientIdController = TextEditingController(
      text: widget.settingsService.spotifyClientId,
    );
    _clientSecretController = TextEditingController(
      text: widget.settingsService.spotifyClientSecret,
    );
  }

  @override
  void didUpdateWidget(covariant _SpotifySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_clientIdController.text != widget.settingsService.spotifyClientId) {
      _clientIdController.text = widget.settingsService.spotifyClientId;
    }
    if (_clientSecretController.text != widget.settingsService.spotifyClientSecret) {
      _clientSecretController.text = widget.settingsService.spotifyClientSecret;
    }
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _clientIdController.text.trim();
    final secret = _clientSecretController.text.trim();
    if (id.isEmpty || secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both Client ID and Client Secret')),
      );
      return;
    }
    await widget.settingsService.setSpotifyCredentials(id, secret);
    if (!mounted) return;
    setState(() => _expanded = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Spotify API credentials saved! 1,000+ song import enabled.'),
        backgroundColor: Color(0xFF1DB954),
      ),
    );
  }

  Future<void> _clear() async {
    await widget.settingsService.clearSpotifyCredentials();
    _clientIdController.clear();
    _clientSecretController.clear();
    if (!mounted) return;
    setState(() => _expanded = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Spotify credentials removed (using 100-track public embed).')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCredentials = widget.settingsService.hasSpotifyCredentials;
    const spotifyGreen = Color(0xFF1DB954);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasCredentials
              ? spotifyGreen.withAlpha(90)
              : theme.colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: spotifyGreen.withAlpha(35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: spotifyGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Spotify Web API',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (hasCredentials ? spotifyGreen : Colors.grey).withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              hasCredentials ? '1k+ Songs' : '100 Max',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: hasCredentials ? spotifyGreen : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hasCredentials
                            ? 'Configured • Imports playlists up to 2,500+ tracks'
                            : 'Using public embed (capped at 100 tracks)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hasCredentials ? spotifyGreen : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: _expanded ? 'Collapse' : 'Configure API',
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: spotifyGreen.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: spotifyGreen.withAlpha(40)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to get free Spotify API keys (1 minute):',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: spotifyGreen,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '1. Log into developer.spotify.com/dashboard (free).\n'
                          '2. Click "Create app" (Name: FinAudio, Redirect URI: http://localhost).\n'
                          '3. Click Settings & copy Client ID and Client Secret.',
                          style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFFCCCCCC)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _clientIdController,
                    decoration: InputDecoration(
                      labelText: 'Client ID',
                      hintText: '32-character Spotify Client ID',
                      prefixIcon: const Icon(Icons.key, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _clientSecretController,
                    obscureText: _obscureSecret,
                    decoration: InputDecoration(
                      labelText: 'Client Secret',
                      hintText: '32-character Spotify Client Secret',
                      prefixIcon: const Icon(Icons.lock_outline, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureSecret ? Icons.visibility_off : Icons.visibility, size: 18),
                        onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (hasCredentials)
                        TextButton.icon(
                          onPressed: _clear,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Clear'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFFCF6679)),
                        ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Save Keys'),
                        style: FilledButton.styleFrom(
                          backgroundColor: spotifyGreen,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AudioQualitySection extends StatelessWidget {
  final SettingsService settingsService;

  const _AudioQualitySection({
    required this.settingsService,
  });

  String _getQualityTitle(String quality) {
    switch (quality) {
      case 'auto':
        return 'Automatic';
      case 'high':
        return 'High Quality';
      case 'medium':
        return 'Medium Quality';
      case 'low':
        return 'Low (Data Saver)';
      default:
        return 'Automatic';
    }
  }

  String _getQualitySubtitle(String quality) {
    switch (quality) {
      case 'auto':
        return 'Adapts dynamically: High on Wi-Fi/Ethernet, Medium on Mobile Data';
      case 'high':
        return 'Best audio fidelity (OPUS 160k / AAC ~140k). Uses more data';
      case 'medium':
        return 'Balanced quality (~128k). Saves substantial mobile data';
      case 'low':
        return 'Minimum data usage (~48–70k). Recommended for tight mobile data limits';
      default:
        return 'Adapts dynamically to save mobile cellular data';
    }
  }

  void _showQualityDialog(BuildContext context) {
    final theme = Theme.of(context);
    final currentQuality = settingsService.audioQuality;

    showDialog(
      context: context,
      builder: (dlgCtx) {
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: settingsService.accentColor, size: 22),
              const SizedBox(width: 10),
              const Text('Audio Streaming Quality', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOption(
                context: dlgCtx,
                title: 'Automatic (Recommended)',
                description: 'Streams High quality on Wi-Fi and Medium data-saving quality on Mobile Cellular data.',
                value: 'auto',
                selected: currentQuality == 'auto',
              ),
              const Divider(height: 16),
              _buildOption(
                context: dlgCtx,
                title: 'High',
                description: 'Up to 160 kbps OPUS / AAC. Crystal clear audio, recommended for unmetered Wi-Fi.',
                value: 'high',
                selected: currentQuality == 'high',
              ),
              const Divider(height: 16),
              _buildOption(
                context: dlgCtx,
                title: 'Medium',
                description: '~128 kbps (AAC / OPUS). Standard balance of quality and reduced mobile data consumption.',
                value: 'medium',
                selected: currentQuality == 'medium',
              ),
              const Divider(height: 16),
              _buildOption(
                context: dlgCtx,
                title: 'Low (Data Saver)',
                description: '~48–70 kbps. Maximum data conservation when on limited cellular data plans.',
                value: 'low',
                selected: currentQuality == 'low',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required String title,
    required String description,
    required String value,
    required bool selected,
  }) {
    return InkWell(
      onTap: () async {
        await settingsService.setAudioQuality(value);
        if (context.mounted) Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? settingsService.accentColor : Colors.white38,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5,
                      height: 1.25,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quality = settingsService.audioQuality;
    final accent = settingsService.accentColor;

    return InkWell(
      onTap: () => _showQualityDialog(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(50),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withAlpha(35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.graphic_eq_rounded,
                color: accent,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Audio Quality',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: accent.withAlpha(60), width: 0.5),
                        ),
                        child: Text(
                          _getQualityTitle(quality),
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getQualitySubtitle(quality),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FinAudio',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ad-free YouTube audio player with Google playlist sync, background playback & mobile data saving.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Version 1.0.0',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrashLogsTile extends StatelessWidget {
  final Color accentColor;

  const _CrashLogsTile({required this.accentColor});

  void _showLogsDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final primaryPath = await CrashLogService.instance.getPrimaryLogPath();
    final logs = await CrashLogService.instance.readLogs();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.terminal_rounded, color: accentColor, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Crash Logs',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  primaryPath,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy Logs'),
                              style: FilledButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                final ok = await CrashLogService.instance.copyToClipboard();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'Crash logs copied to clipboard!'
                                          : 'Failed to copy logs.'),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline_rounded, size: 16),
                            label: const Text('Clear'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: BorderSide(color: Colors.redAccent.withAlpha(80)),
                            ),
                            onPressed: () async {
                              await CrashLogService.instance.clearLogs();
                              if (context.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Crash logs cleared.')),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(120),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant.withAlpha(50),
                            ),
                          ),
                          child: SingleChildScrollView(
                            controller: scrollController,
                            child: SelectableText(
                              logs,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Color(0xFFE0E0E0),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => _showLogsDialog(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(50),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withAlpha(35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.bug_report_outlined,
                color: accentColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crash Logs',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Saved in Documents/FinAudioCrashLogs • Tap to view or copy',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleAccountSection extends StatefulWidget {
  final GoogleAuthService authService;
  final Color accentColor;
  final VoidCallback onAuthChanged;

  const _GoogleAccountSection({
    required this.authService,
    required this.accentColor,
    required this.onAuthChanged,
  });

  @override
  State<_GoogleAccountSection> createState() => _GoogleAccountSectionState();
}

class _GoogleAccountSectionState extends State<_GoogleAccountSection> {
  final TextEditingController _handleController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.authService.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    widget.authService.removeListener(_onAuthChanged);
    _handleController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _GoogleAccountSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authService != widget.authService) {
      oldWidget.authService.removeListener(_onAuthChanged);
      widget.authService.addListener(_onAuthChanged);
    }
  }

  Future<void> _handleSignIn() async {
    if (!widget.authService.isNativeGoogleSignInPluginSupported) {
      await showGoogleSignInDialog(
        context: context,
        authService: widget.authService,
        accentColor: widget.accentColor,
        onSignedIn: widget.onAuthChanged,
      );
      if (mounted) setState(() {});
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.authService.signIn();
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onAuthChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sign in failed: $e';
      });
    }
  }

  Future<void> _handleInnerTubeConnect() async {
    final text = _handleController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please enter your YouTube handle (e.g. @yourname) or Channel ID.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.authService.signInWithInnerTube(handleOrChannelId: text);
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onAuthChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'InnerTube connect failed: $e';
      });
    }
  }

  Future<void> _handleSignOut() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.authService.signOut();
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onAuthChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sign out failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSignedIn = widget.authService.isSignedIn;
    final user = widget.authService.currentUser;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSignedIn && user != null) ...[
            Row(
              children: [
                if (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                  CircleAvatar(
                    backgroundImage: NetworkImage(user.photoUrl!),
                    radius: 22,
                  )
                else
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: widget.accentColor.withAlpha(40),
                    child: Icon(Icons.person, color: widget.accentColor),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? 'YouTube User',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _handleSignOut,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout, size: 18),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(color: Colors.redAccent.withAlpha(80)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ] else ...[
            Text(
              'Sync YouTube Playlists (InnerTube)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Music playback, searches, and catalog access are powered directly by InnerTube without Google OAuth restrictions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _handleSignIn,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.login, size: 20),
                label: const Text('Sign in with Google'),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Divider(color: theme.colorScheme.outlineVariant.withAlpha(80))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'OR CONNECT VIA INNERTUBE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                    ),
                  ),
                ),
                Expanded(child: Divider(color: theme.colorScheme.outlineVariant.withAlpha(80))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _handleController,
                    decoration: InputDecoration(
                      hintText: '@handle or Channel ID',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loading ? null : _handleInnerTubeConnect,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  child: const Text('Connect'),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
