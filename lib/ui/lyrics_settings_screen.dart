import 'package:flutter/material.dart';
import 'package:finaudio/services/settings_service.dart';
import 'package:finaudio/ui/appearance_screen.dart';

/// FinAudio Lyrics Settings screen.
/// Follows FinAudio's active user theme colors dynamically and provides:
/// - Timing & Synchronization: Auto-align timing offset, Auto-sync plain lyrics
/// - Providers: Preferred provider, NetEase Cloud Music, SimpMusic, BetterLyrics, KuGou, LRCLIB
/// - Display & Animation: Lyrics mode, Animation style, Change on click, Auto scroll, Blur lines, Text size, Line spacing, Romanization & Translation toggles
/// - Romanization: Japanese, Korean, Chinese, Hindi
class LyricsSettingsScreen extends StatefulWidget {
  final SettingsService settingsService;

  const LyricsSettingsScreen({
    super.key,
    required this.settingsService,
  });

  @override
  State<LyricsSettingsScreen> createState() => _LyricsSettingsScreenState();
}

class _LyricsSettingsScreenState extends State<LyricsSettingsScreen> {
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
    final bgColor = _settings.backgroundColor;
    final cardColor = _settings.surfaceColor;
    final accentColor = _settings.accentColor;
    final textColor = _settings.textColor;
    final subtextColor = textColor.withValues(alpha: 0.65);
    final dividerColor = textColor.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Lyrics',
          style: TextStyle(
            color: textColor,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Section 1: Timing & Synchronization
          _SectionTitle(title: 'Timing & Synchronization', color: accentColor),
          const SizedBox(height: 8),
          _SettingsCard(
            color: cardColor,
            children: [
              _SwitchTile(
                icon: Icons.timer_outlined,
                title: 'Auto-align timing offset',
                subtitle: 'Automatically corrects intro delay & sync discrepancies using speech timestamps',
                value: _settings.autoAlignLyricsOffset,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (val) => _settings.setAutoAlignLyricsOffset(val),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.sync_rounded,
                title: 'Auto-sync plain lyrics',
                subtitle: 'Synthesizes synced lyric lines from plain text using vocal speech markers',
                value: _settings.autoSyncPlainLyrics,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (val) => _settings.setAutoSyncPlainLyrics(val),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section 2: Active Lyrics Providers
          _SectionTitle(title: 'Active Lyrics Providers', color: accentColor),
          const SizedBox(height: 8),
          _SettingsCard(
            color: cardColor,
            children: [
              _NavigationTile(
                icon: Icons.star_outline_rounded,
                title: 'Preferred lyrics provider',
                subtitle: _settings.preferredLyricsProvider,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onTap: () => _showPreferredProviderPicker(cardColor, textColor, accentColor),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.music_note_rounded,
                title: 'NetEase Cloud Music',
                subtitle: 'Rich synchronized LRC database with translations',
                value: _settings.enableNetEase,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (v) => _settings.setLyricsProviderEnabled('netease', v),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.lyrics_rounded,
                title: 'SimpMusic',
                subtitle: 'Fast community synchronized lyrics provider',
                value: _settings.enableSimpMusic,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (v) => _settings.setLyricsProviderEnabled('simpmusic', v),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.auto_awesome_rounded,
                title: 'BetterLyrics',
                subtitle: 'High precision syllable and line-synced lyrics',
                value: _settings.enableBetterLyrics,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (v) => _settings.setLyricsProviderEnabled('betterlyrics', v),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.library_music_rounded,
                title: 'KuGou',
                subtitle: 'Extensive Asian and international catalog',
                value: _settings.enableKuGou,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (v) => _settings.setLyricsProviderEnabled('kugou', v),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.cloud_queue_rounded,
                title: 'LRCLIB',
                subtitle: 'Community-driven open lyrics database',
                value: _settings.enableLrcLib,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (v) => _settings.setLyricsProviderEnabled('lrclib', v),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section 3: Display & Animation
          _SectionTitle(title: 'Display & Animation', color: accentColor),
          const SizedBox(height: 8),
          _SettingsCard(
            color: cardColor,
            children: [
              _NavigationTile(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Lyrics mode',
                badgeText: _settings.lyricsMode,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onTap: () => _showLyricsModePicker(cardColor, textColor, accentColor),
              ),
              _TileDivider(color: dividerColor),
              _NavigationTile(
                icon: Icons.all_inclusive_rounded,
                title: 'Lyrics animation style',
                subtitle: _settings.lyricsMode == 'V2'
                    ? _settings.lyricsAnimationStyle
                    : 'Available only in V2 lyrics mode',
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onTap: _settings.lyricsMode == 'V2'
                    ? () => _showAnimationStylePicker(cardColor, textColor, accentColor)
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Switch Lyrics mode to V2 to customize animation style.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.touch_app_rounded,
                title: 'Change lyrics on click',
                subtitle: 'Seek song timestamp when tapping on a lyric line',
                value: _settings.changeLyricsOnClick,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (val) => _settings.setChangeLyricsOnClick(val),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.vertical_align_center_rounded,
                title: 'Auto scroll lyrics',
                subtitle: 'Keep current lyric line centered automatically',
                value: _settings.autoScrollLyrics,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (val) => _settings.setAutoScrollLyrics(val),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.blur_on_rounded,
                title: 'Blur lyrics lines',
                subtitle: 'Softly blur lines away from the current position',
                value: _settings.blurLyricsLines,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (val) => _settings.setBlurLyricsLines(val),
              ),
              _TileDivider(color: dividerColor),
              _NavigationTile(
                icon: Icons.text_fields_rounded,
                title: 'Lyrics text size',
                subtitle: '${_settings.lyricsTextSize.toInt()} sp',
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onTap: () => _showTextSizePicker(cardColor, textColor, accentColor),
              ),
              _TileDivider(color: dividerColor),
              _NavigationTile(
                icon: Icons.format_line_spacing_rounded,
                title: 'Lyrics line spacing',
                subtitle: '${_settings.lyricsLineSpacing}x',
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onTap: () => _showLineSpacingPicker(cardColor, textColor, accentColor),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.translate_rounded,
                title: 'Show Romanization (Romaji)',
                subtitle: 'Display pronunciation readings above original text',
                value: _settings.showRomanizedLyrics,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (val) => _settings.setShowRomanizedLyrics(val),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.g_translate_rounded,
                title: 'Show English translation',
                subtitle: 'Display translated lyrics below original text',
                value: _settings.showTranslatedLyrics,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (val) => _settings.setShowTranslatedLyrics(val),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section 4: Romanization
          _SectionTitle(title: 'Romanization Languages', color: accentColor),
          const SizedBox(height: 8),
          _SettingsCard(
            color: cardColor,
            children: [
              _SwitchTile(
                icon: Icons.language_rounded,
                title: 'Romanize Japanese lyrics',
                subtitle: 'Convert Kanji and Kana into Hepburn Romaji',
                value: _settings.romanizeJapanese,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (v) => _settings.setRomanizeOption('japanese', v),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.language_rounded,
                title: 'Romanize Korean lyrics',
                subtitle: 'Convert Hangul into Revised Romanization',
                value: _settings.romanizeKorean,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (v) => _settings.setRomanizeOption('korean', v),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.language_rounded,
                title: 'Romanize Chinese lyrics',
                subtitle: 'Convert Hanzi into Pinyin',
                value: _settings.romanizeChinese,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (v) => _settings.setRomanizeOption('chinese', v),
              ),
              _TileDivider(color: dividerColor),
              _SwitchTile(
                icon: Icons.language_rounded,
                title: 'Romanize Hindi lyrics',
                subtitle: 'Convert Devanagari script to Latin script',
                value: _settings.romanizeHindi,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onChanged: (v) => _settings.setRomanizeOption('hindi', v),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section 5: Lyric Colors & Glow
          _SectionTitle(title: 'Lyric Colors & Glow', color: accentColor),
          const SizedBox(height: 8),
          _SettingsCard(
            color: cardColor,
            children: [
              _ColorTile(
                color: _settings.lyricsActiveColor,
                title: 'Active lyric color',
                subtitle: _settings.customLyricsActiveColor != null
                    ? '#${_settings.customLyricsActiveColor!.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)} (Custom)'
                    : 'Default (Matches Theme text)',
                textColor: textColor,
                subtextColor: subtextColor,
                dividerColor: dividerColor,
                onTap: () => _openLyricsColorDialog(
                  title: 'Active Lyric Color',
                  currentColor: _settings.lyricsActiveColor,
                  quickPalette: const [
                    Colors.white,
                    Color(0xFFFFDE38), // Lemon Yellow
                    Color(0xFF00E5FF), // Electric Cyan
                    Color(0xFF1DB954), // Spotify Green
                    Color(0xFFFF4081), // Neon Pink
                    Color(0xFFE040FB), // Electric Purple
                    Color(0xFFFF9100), // Bright Orange
                    Color(0xFFFF5252), // Bright Red
                  ],
                  onSelected: (c) => _settings.setLyricsActiveColor(c),
                ),
              ),
              _TileDivider(color: dividerColor),
              _ColorTile(
                color: _settings.lyricsInactiveColor,
                title: 'Inactive lyric color',
                subtitle: _settings.customLyricsInactiveColor != null
                    ? '#${_settings.customLyricsInactiveColor!.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)} (Custom)'
                    : 'Default (Muted 35% text)',
                textColor: textColor,
                subtextColor: subtextColor,
                dividerColor: dividerColor,
                onTap: () => _openLyricsColorDialog(
                  title: 'Inactive Lyric Color',
                  currentColor: _settings.lyricsInactiveColor,
                  quickPalette: const [
                    Color(0x59FFFFFF), // 35% White
                    Color(0x80FFFFFF), // 50% White
                    Color(0x33FFFFFF), // 20% White
                    Color(0xFF757575), // Charcoal Gray
                    Color(0xFF546E7A), // Slate
                    Color(0xFF616161), // Medium Gray
                    Color(0xFF8D6E63), // Muted Amber
                    Color(0xFF455A64), // Deep Steel
                  ],
                  onSelected: (c) => _settings.setLyricsInactiveColor(c),
                ),
              ),
              _TileDivider(color: dividerColor),
              _ColorTile(
                color: _settings.lyricsGlowColor,
                hasGlow: true,
                title: 'Lyric glow & radiance',
                subtitle: _settings.customLyricsGlowColor != null
                    ? '#${_settings.customLyricsGlowColor!.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)} (Custom)'
                    : 'Default (Matches Theme Accent)',
                textColor: textColor,
                subtextColor: subtextColor,
                dividerColor: dividerColor,
                onTap: () => _openLyricsColorDialog(
                  title: 'Lyric Glow & Radiance',
                  currentColor: _settings.lyricsGlowColor,
                  quickPalette: [
                    accentColor,
                    const Color(0xFFFFDE38), // Yellow
                    const Color(0xFF00E5FF), // Cyan
                    const Color(0xFF1DB954), // Spotify Green
                    const Color(0xFFE040FB), // Magenta
                    const Color(0xFFFF5252), // Red
                    const Color(0xFFFF6D00), // Sunset Orange
                    Colors.white,
                  ],
                  onSelected: (c) => _settings.setLyricsGlowColor(c),
                ),
              ),
              if (_settings.hasCustomLyricsColors) ...[
                _TileDivider(color: dividerColor),
                InkWell(
                  onTap: () async {
                    await _settings.resetLyricsColors();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lyric colors reset to default theme.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.restart_alt_rounded, size: 22, color: accentColor),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Reset lyric colors to default',
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- Pickers ---

  Future<void> _openLyricsColorDialog({
    required String title,
    required Color currentColor,
    required List<Color> quickPalette,
    required ValueChanged<Color> onSelected,
  }) async {
    Color selectedColor = currentColor;
    final pickerKey = GlobalKey<SpectrumColorPickerState>();

    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _settings.surfaceColor,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: _settings.textColor.withValues(alpha: 0.12)),
              ),
              title: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: selectedColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _settings.textColor.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: selectedColor.withValues(alpha: 0.45),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: _settings.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick Presets',
                        style: TextStyle(
                          color: _settings.textColor.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: quickPalette.map((color) {
                          final isSelected =
                              color.toARGB32() == selectedColor.toARGB32();
                          final onColor = color.computeLuminance() > 0.5
                              ? const Color(0xFF101010)
                              : const Color(0xFFFFFFFF);
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() => selectedColor = color);
                              pickerKey.currentState?.setColor(color);
                            },
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? _settings.textColor
                                      : _settings.textColor.withValues(alpha: 0.15),
                                  width: isSelected ? 2.5 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.6),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : null,
                              ),
                              child: isSelected
                                  ? Icon(
                                      Icons.check,
                                      size: 18,
                                      color: onColor,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: _settings.textColor.withValues(alpha: 0.12)),
                      const SizedBox(height: 8),
                      Text(
                        'Custom Spectrum',
                        style: TextStyle(
                          color: _settings.textColor.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SpectrumColorPicker(
                        key: pickerKey,
                        initialColor: selectedColor,
                        textColor: _settings.textColor,
                        surfaceColor: _settings.surfaceColor,
                        onColorChanged: (c) {
                          setDialogState(() => selectedColor = c);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  style: TextButton.styleFrom(
                    foregroundColor: _settings.textColor.withValues(alpha: 0.7),
                  ),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(selectedColor),
                  style: FilledButton.styleFrom(
                    backgroundColor: _settings.accentColor,
                    foregroundColor: _settings.accentColor.computeLuminance() > 0.5
                        ? const Color(0xFF101010)
                        : const Color(0xFFFFFFFF),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null) {
      onSelected(picked);
    }
  }

  void _showLyricsModePicker(Color sheetBg, Color textColor, Color accentColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select Lyrics Mode',
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final mode in ['Enhanced', 'V2', 'Standard'])
                ListTile(
                  title: Text(mode, style: TextStyle(color: textColor)),
                  trailing: _settings.lyricsMode == mode
                      ? Icon(Icons.check, color: accentColor)
                      : null,
                  onTap: () {
                    _settings.setLyricsMode(mode);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showAnimationStylePicker(Color sheetBg, Color textColor, Color accentColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Lyrics Animation Style',
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final style in [
                'Fluid Apple Music',
                'Karaoke Glow',
                'Fade & Slide',
                'Classic'
              ])
                ListTile(
                  title: Text(style, style: TextStyle(color: textColor)),
                  trailing: _settings.lyricsAnimationStyle == style
                      ? Icon(Icons.check, color: accentColor)
                      : null,
                  onTap: () {
                    _settings.setLyricsAnimationStyle(style);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showTextSizePicker(Color sheetBg, Color textColor, Color accentColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Lyrics Text Size',
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final size in [20.0, 22.0, 24.0, 26.0, 28.0, 32.0])
                ListTile(
                  title: Text('${size.toInt()} sp', style: TextStyle(color: textColor)),
                  trailing: _settings.lyricsTextSize == size
                      ? Icon(Icons.check, color: accentColor)
                      : null,
                  onTap: () {
                    _settings.setLyricsTextSize(size);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showLineSpacingPicker(Color sheetBg, Color textColor, Color accentColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Lyrics Line Spacing',
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final spacing in [1.0, 1.2, 1.3, 1.5, 1.8])
                ListTile(
                  title: Text('${spacing}x', style: TextStyle(color: textColor)),
                  trailing: _settings.lyricsLineSpacing == spacing
                      ? Icon(Icons.check, color: accentColor)
                      : null,
                  onTap: () {
                    _settings.setLyricsLineSpacing(spacing);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showPreferredProviderPicker(Color sheetBg, Color textColor, Color accentColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Preferred Lyrics Provider',
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final prov in [
                'BetterLyrics',
                'SimpMusic',
                'NetEase',
                'LRCLIB',
                'KuGou',
                'YouTube Captions',
              ])
                ListTile(
                  title: Text(prov, style: TextStyle(color: textColor)),
                  trailing: _settings.preferredLyricsProvider.toLowerCase() == prov.toLowerCase() ||
                          (_settings.preferredLyricsProvider == 'LrcLib' && prov == 'LRCLIB')
                      ? Icon(Icons.check, color: accentColor)
                      : null,
                  onTap: () {
                    _settings.setPreferredLyricsProvider(prov);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

// ======================================================================
// Helper Widgets styled dynamically with User Theme
// ======================================================================

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionTitle({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Color color;
  final List<Widget> children;

  const _SettingsCard({required this.color, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }
}

class _TileDivider extends StatelessWidget {
  final Color color;

  const _TileDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 52,
      endIndent: 16,
      color: color,
    );
  }
}

class _NavigationTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badgeText;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final VoidCallback onTap;

  const _NavigationTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.badgeText,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: subtextColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: subtextColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (badgeText != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  badgeText!,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textColor.withValues(alpha: 0.35)),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onAccent = accentColor.computeLuminance() > 0.5 ? const Color(0xFF101010) : const Color(0xFFFFFFFF);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 22, color: subtextColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: subtextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: accentColor,
            activeTrackColor: accentColor.withValues(alpha: 0.4),
            inactiveThumbColor: textColor.withValues(alpha: 0.5),
            inactiveTrackColor: textColor.withValues(alpha: 0.12),
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
              if (states.contains(WidgetState.selected)) {
                return Icon(Icons.check, size: 14, color: onAccent);
              }
              return null;
            }),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ColorTile extends StatelessWidget {
  final Color color;
  final bool hasGlow;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color subtextColor;
  final Color dividerColor;
  final VoidCallback onTap;

  const _ColorTile({
    required this.color,
    this.hasGlow = false,
    required this.title,
    required this.subtitle,
    required this.textColor,
    required this.subtextColor,
    required this.dividerColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: textColor.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: hasGlow
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.8),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subtextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: textColor.withValues(alpha: 0.35)),
          ],
        ),
      ),
    );
  }
}
