import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:finaudio/services/settings_service.dart';

/// Screen that provides complete freedom to customize the app's theme:
/// - Background color
/// - Card / Surface color
/// - Button / Accent color
/// - Text color
/// Includes real-time live preview, curated presets, and fine-grained color pickers.
class AppearanceScreen extends StatefulWidget {
  final SettingsService settingsService;
  final VoidCallback? onChanged;

  const AppearanceScreen({
    super.key,
    required this.settingsService,
    this.onChanged,
  });

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late final SettingsService _settings = widget.settingsService;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
    widget.onChanged?.call();
  }

  Color _onColorFor(Color color) {
    return color.computeLuminance() > 0.5
        ? const Color(0xFF101010)
        : const Color(0xFFFFFFFF);
  }

  Future<void> _openColorDialog({
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
                side: BorderSide(color: _settings.textColor.withAlpha(30)),
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
                        color: _settings.textColor.withAlpha(80),
                        width: 1.5,
                      ),
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
                          color: _settings.textColor.withAlpha(180),
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
                                      : _settings.textColor.withAlpha(40),
                                  width: isSelected ? 2.5 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: color.withAlpha(160),
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
                                      color: _onColorFor(color),
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: _settings.textColor.withAlpha(30)),
                      const SizedBox(height: 8),
                      Text(
                        'Custom Spectrum',
                        style: TextStyle(
                          color: _settings.textColor.withAlpha(180),
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
                    foregroundColor: _settings.textColor.withAlpha(180),
                  ),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(selectedColor),
                  style: FilledButton.styleFrom(
                    backgroundColor: _settings.accentColor,
                    foregroundColor: _onColorFor(_settings.accentColor),
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

  @override
  Widget build(BuildContext context) {
    final bg = _settings.backgroundColor;
    final surface = _settings.surfaceColor;
    final accent = _settings.accentColor;
    final text = _settings.textColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Theme & Appearance',
          style: TextStyle(
            color: text,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        iconTheme: IconThemeData(color: text),
        actions: [
          IconButton(
            tooltip: 'Reset to default theme',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () async {
              await _settings.resetToDefault();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Theme reset to Lemon Shark (Dark).'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: surface,
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Section 1: Live Interactive Preview
          _buildPreviewHeader(text),
          const SizedBox(height: 10),
          _buildLivePreviewCard(bg, surface, accent, text),
          const SizedBox(height: 24),

          // Section 2: Curated Presets
          _buildSectionTitle('Theme Presets', text, accent),
          const SizedBox(height: 12),
          _buildPresetsCarousel(bg, surface, accent, text),
          const SizedBox(height: 24),

          // Section 3: Fine-Grained Custom Colors
          _buildSectionTitle('Customize Colors', text, accent),
          const SizedBox(height: 12),

          // Background Color Tile
          _buildColorTile(
            title: 'Background Color',
            subtitle: 'App backdrop and screen background',
            color: bg,
            icon: Icons.wallpaper_rounded,
            surfaceColor: surface,
            textColor: text,
            onTap: () => _openColorDialog(
              title: 'Pick Background Color',
              currentColor: bg,
              quickPalette: const [
                Color(0xFF14130A), // Lemon Shark Dark skin
                Color(0xFFF6EFC4), // Lemon Shark Light sand
                Color(0xFF000000), // Pure OLED
                Color(0xFF0A0A0A), // Dark
                Color(0xFF0B111E), // Midnight
                Color(0xFF0E1712), // Emerald
                Color(0xFF170F14), // Sunset
                Color(0xFF181A1F), // Slate
              ],
              onSelected: (color) => _settings.setBackgroundColor(color),
            ),
          ),
          const SizedBox(height: 10),

          // Surface & Cards Tile
          _buildColorTile(
            title: 'Cards & Surfaces',
            subtitle: 'Cards, bottom bar, and dialog surfaces',
            color: surface,
            icon: Icons.layers_rounded,
            surfaceColor: surface,
            textColor: text,
            onTap: () => _openColorDialog(
              title: 'Pick Surface Color',
              currentColor: surface,
              quickPalette: const [
                Color(0xFF262414), // Lemon Shark Dark surface
                Color(0xFFFFFCE0), // Lemon Shark Light surface
                Color(0xFF0D0D0D), // OLED surface
                Color(0xFF161616), // Dark surface
                Color(0xFF151F32), // Midnight surface
                Color(0xFF17241D), // Emerald surface
                Color(0xFF241720), // Sunset surface
                Color(0xFF242730), // Slate surface
              ],
              onSelected: (color) => _settings.setSurfaceColor(color),
            ),
          ),
          const SizedBox(height: 10),

          // Buttons & Accent Tile
          _buildColorTile(
            title: 'Buttons & Accent',
            subtitle: 'Primary buttons, active sliders, and focus highlights',
            color: accent,
            icon: Icons.touch_app_rounded,
            surfaceColor: surface,
            textColor: text,
            onTap: () => _openColorDialog(
              title: 'Pick Button & Accent Color',
              currentColor: accent,
              quickPalette: const [
                Color(0xFFFFDE38), // Lemon Shark Yellow
                Color(0xFFC78500), // Lemon Shark Amber Gold
                Color(0xFF1DB954), // Spotify Green
                Color(0xFF00B0FF), // Electric Blue
                Color(0xFFFF5722), // Vibrant Orange
                Color(0xFFE040FB), // Neon Purple
                Color(0xFFCC0000), // Red
                Color(0xFFFFFFFF), // Crisp White
              ],
              onSelected: (color) => _settings.setAccentColor(color),
            ),
          ),
          const SizedBox(height: 10),

          // Text Color Tile
          _buildColorTile(
            title: 'Text Color',
            subtitle: 'Primary headings and title text',
            color: text,
            icon: Icons.text_fields_rounded,
            surfaceColor: surface,
            textColor: text,
            onTap: () => _openColorDialog(
              title: 'Pick Text Color',
              currentColor: text,
              quickPalette: const [
                Color(0xFFFAF7E6), // Lemon Shark Cream White
                Color(0xFF2B2408), // Lemon Shark Dark Charcoal
                Color(0xFFFFFFFF), // Crisp White
                Color(0xFFE6E6E6), // Classic Gray
                Color(0xFFE1E7F0), // Midnight Ice
                Color(0xFFE6F5EC), // Emerald Ice
                Color(0xFFF5EBEB), // Sunset Ice
                Color(0xFFCFD8DC), // Slate Ice
              ],
              onSelected: (color) => _settings.setTextColor(color),
            ),
          ),

          const SizedBox(height: 28),

          // Reset to default button
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _settings.resetToDefault(),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Reset All to Defaults'),
              style: OutlinedButton.styleFrom(
                foregroundColor: text.withAlpha(200),
                side: BorderSide(color: text.withAlpha(60)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPreviewHeader(Color text) {
    return Row(
      children: [
        Icon(Icons.remove_red_eye_outlined, size: 18, color: text.withAlpha(180)),
        const SizedBox(width: 8),
        Text(
          'Live Preview',
          style: TextStyle(
            color: text.withAlpha(200),
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildLivePreviewCard(
    Color bg,
    Color surface,
    Color accent,
    Color text,
  ) {
    final onAccent = _onColorFor(accent);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: text.withAlpha(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(60),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mock track info row
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.music_note_rounded, color: accent, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Midnight Echoes',
                      style: TextStyle(
                        color: text,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'FinAudio Soundscapes • 3:42',
                      style: TextStyle(
                        color: text.withAlpha(160),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              Icon(Icons.favorite, color: accent, size: 20),
            ],
          ),
          const SizedBox(height: 14),

          // Mock progress bar
          Row(
            children: [
              Text(
                '1:24',
                style: TextStyle(color: text.withAlpha(140), fontSize: 11),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: text.withAlpha(30),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: 0.38,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '3:42',
                style: TextStyle(color: text.withAlpha(140), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Mock control buttons & action button
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.skip_previous_rounded, color: text),
                onPressed: () {},
                iconSize: 24,
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: onAccent,
                  size: 26,
                ),
              ),
              IconButton(
                icon: Icon(Icons.skip_next_rounded, color: text),
                onPressed: () {},
                iconSize: 24,
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {},
                icon: Icon(Icons.add, size: 16, color: onAccent),
                label: Text(
                  'Button Sample',
                  style: TextStyle(
                    color: onAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color text, Color accent) {
    return Text(
      title,
      style: TextStyle(
        color: text,
        fontSize: 16,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildPresetsCarousel(
    Color bg,
    Color surface,
    Color accent,
    Color text,
  ) {
    return SizedBox(
      height: 115,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: SettingsService.presets.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final preset = SettingsService.presets[index];
          final isSelected =
              preset.backgroundColor.toARGB32() == bg.toARGB32() &&
              preset.surfaceColor.toARGB32() == surface.toARGB32() &&
              preset.accentColor.toARGB32() == accent.toARGB32() &&
              preset.textColor.toARGB32() == text.toARGB32();

          return GestureDetector(
            onTap: () => _settings.applyPreset(preset),
            child: Container(
              width: 135,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: preset.surfaceColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? preset.accentColor
                      : text.withAlpha(40),
                  width: isSelected ? 2.5 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: preset.accentColor.withAlpha(80),
                          blurRadius: 8,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Preset mini dots
                      _miniDot(preset.backgroundColor),
                      const SizedBox(width: 4),
                      _miniDot(preset.surfaceColor),
                      const SizedBox(width: 4),
                      _miniDot(preset.accentColor),
                      const SizedBox(width: 4),
                      _miniDot(preset.textColor),
                      const Spacer(),
                      if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: preset.accentColor,
                        ),
                    ],
                  ),
                  Text(
                    preset.name,
                    style: TextStyle(
                      color: preset.textColor,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _miniDot(Color color) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withAlpha(60), width: 0.8),
      ),
    );
  }

  Widget _buildColorTile({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required Color surfaceColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    final hexString =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: textColor.withAlpha(30)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: textColor.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: textColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: textColor.withAlpha(150),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Hex badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: textColor.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                hexString,
                style: TextStyle(
                  color: textColor.withAlpha(200),
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Color circle preview
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: textColor.withAlpha(80),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: textColor.withAlpha(120),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Robust, native spectrum color picker that maintains persistent HSV state
/// and avoids jumping to red or getting trapped in black.
class SpectrumColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;
  final Color textColor;
  final Color surfaceColor;

  const SpectrumColorPicker({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
    required this.textColor,
    required this.surfaceColor,
  });

  @override
  State<SpectrumColorPicker> createState() => SpectrumColorPickerState();
}

class SpectrumColorPickerState extends State<SpectrumColorPicker> {
  late double _hue; // 0.0 .. 360.0
  late double _saturation; // 0.0 .. 1.0
  late double _value; // 0.0 .. 1.0
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _initFromColor(widget.initialColor);
    _hexController = TextEditingController(text: _formatHex(currentColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _initFromColor(Color color) {
    final hsv = HSVColor.fromColor(color);
    if (color.toARGB32() == 0xFF000000) {
      // Pure black: keep hue vibrant (50.0 = warm lemon yellow base)
      // with saturation = 1.0, value = 0.0 so moving hue or brightness unlocks colors immediately.
      _hue = 50.0;
      _saturation = 1.0;
      _value = 0.0;
    } else if (color.toARGB32() == 0xFFFFFFFF) {
      _hue = 50.0;
      _saturation = 0.0;
      _value = 1.0;
    } else {
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _value = hsv.value;
    }
  }

  /// Sets the color from an external trigger (like preset chips)
  void setColor(Color color) {
    setState(() {
      _initFromColor(color);
      _hexController.text = _formatHex(currentColor);
    });
  }

  Color get currentColor =>
      HSVColor.fromAHSV(1.0, _hue, _saturation, _value).toColor();

  static String _formatHex(Color c) {
    return c
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
  }

  void _applyHex(String text) {
    final clean = text.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final parsed = int.tryParse('FF$clean', radix: 16);
      if (parsed != null) {
        final col = Color(parsed);
        setState(() {
          _initFromColor(col);
        });
        widget.onColorChanged(currentColor);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final curColor = currentColor;
    final pureHue = HSVColor.fromAHSV(1.0, _hue, 1.0, 1.0).toColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 2D Saturation & Brightness Box
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            const h = 135.0;
            return GestureDetector(
              onPanDown: (details) => _handle2D(details.localPosition, Size(w, h)),
              onPanUpdate: (details) => _handle2D(details.localPosition, Size(w, h)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  size: Size(w, h),
                  painter: _SpectrumAreaPainter(
                    hue: _hue,
                    saturation: _saturation,
                    value: _value,
                    pointerColor: curColor,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // 2. Hue Rainbow Slider
        Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                'Hue',
                style: TextStyle(
                  color: widget.textColor.withAlpha(160),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  const h = 24.0;
                  return GestureDetector(
                    onPanDown: (details) => _handleHue(details.localPosition.dx, w),
                    onPanUpdate: (details) => _handleHue(details.localPosition.dx, w),
                    child: Container(
                      height: h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFF0000),
                            Color(0xFFFFFF00),
                            Color(0xFF00FF00),
                            Color(0xFF00FFFF),
                            Color(0xFF0000FF),
                            Color(0xFFFF00FF),
                            Color(0xFFFF0000),
                          ],
                        ),
                      ),
                      child: CustomPaint(
                        painter: _SliderThumbPainter(
                          fraction: (_hue / 360.0).clamp(0.0, 1.0),
                          thumbColor: pureHue,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 3. Brightness / Shade Slider
        Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                'Shade',
                style: TextStyle(
                  color: widget.textColor.withAlpha(160),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  const h = 24.0;
                  return GestureDetector(
                    onPanDown: (details) => _handleBrightness(details.localPosition.dx, w),
                    onPanUpdate: (details) => _handleBrightness(details.localPosition.dx, w),
                    child: Container(
                      height: h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            Colors.black,
                            HSVColor.fromAHSV(1.0, _hue, _saturation, 1.0).toColor(),
                          ],
                        ),
                      ),
                      child: CustomPaint(
                        painter: _SliderThumbPainter(
                          fraction: _value.clamp(0.0, 1.0),
                          thumbColor: curColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 4. Hex input & clipboard tools
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.textColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.textColor.withAlpha(30)),
                ),
                child: Row(
                  children: [
                    Text(
                      '#',
                      style: TextStyle(
                        color: widget.textColor.withAlpha(140),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _hexController,
                        style: TextStyle(
                          color: widget.textColor,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 6),
                        ),
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(6),
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                        ],
                        onSubmitted: _applyHex,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.paste_rounded, size: 18),
              tooltip: 'Paste Hex Code',
              color: widget.textColor.withAlpha(200),
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (!mounted) return;
                if (data?.text != null) {
                  final clean = data!.text!.replaceAll('#', '').trim();
                  if (clean.length == 6) {
                    _hexController.text = clean.toUpperCase();
                    _applyHex(clean);
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Copy Hex Code',
              color: widget.textColor.withAlpha(200),
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final messenger = ScaffoldMessenger.of(context);
                Clipboard.setData(ClipboardData(text: '#${_formatHex(curColor)}'));
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Copied #${_formatHex(curColor)} to clipboard'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  void _handle2D(Offset local, Size size) {
    final sat = (local.dx / size.width).clamp(0.0, 1.0);
    final val = (1.0 - (local.dy / size.height)).clamp(0.0, 1.0);
    setState(() {
      _saturation = sat;
      _value = val;
      _hexController.text = _formatHex(currentColor);
    });
    widget.onColorChanged(currentColor);
  }

  void _handleHue(double dx, double width) {
    final h = ((dx / width) * 360.0).clamp(0.0, 360.0);
    setState(() {
      _hue = h >= 360.0 ? 0.0 : h;
      // CRITICAL FIX: If brightness was near black, automatically restore brightness
      // so touching or sliding Hue immediately brings up the vibrant color!
      if (_value < 0.15) {
        _value = 1.0;
      }
      if (_saturation < 0.1) {
        _saturation = 1.0;
      }
      _hexController.text = _formatHex(currentColor);
    });
    widget.onColorChanged(currentColor);
  }

  void _handleBrightness(double dx, double width) {
    final v = (dx / width).clamp(0.0, 1.0);
    setState(() {
      _value = v;
      _hexController.text = _formatHex(currentColor);
    });
    widget.onColorChanged(currentColor);
  }
}

class _SpectrumAreaPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;
  final Color pointerColor;

  _SpectrumAreaPainter({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.pointerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Horizontal gradient: White (sat=0) -> Pure Hue (sat=1)
    final pureHue = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    final hGradient = LinearGradient(
      colors: [Colors.white, pureHue],
    );
    final paintH = Paint()..shader = hGradient.createShader(rect);
    canvas.drawRect(rect, paintH);

    // 2. Vertical gradient: Transparent (val=1) -> Black (val=0)
    final vGradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    );
    final paintV = Paint()..shader = vGradient.createShader(rect);
    canvas.drawRect(rect, paintV);

    // 3. Circular thumb indicator at (saturation, 1.0 - value)
    final thumbX = (saturation * size.width).clamp(0.0, size.width);
    final thumbY = ((1.0 - value) * size.height).clamp(0.0, size.height);
    final thumbCenter = Offset(thumbX, thumbY);

    // Outer shadow
    canvas.drawCircle(
      thumbCenter,
      10,
      Paint()
        ..color = Colors.black45
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // White outer ring
    canvas.drawCircle(
      thumbCenter,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Inner filled circle
    canvas.drawCircle(
      thumbCenter,
      7,
      Paint()
        ..color = pointerColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _SpectrumAreaPainter oldDelegate) {
    return oldDelegate.hue != hue ||
        oldDelegate.saturation != saturation ||
        oldDelegate.value != value ||
        oldDelegate.pointerColor != pointerColor;
  }
}

class _SliderThumbPainter extends CustomPainter {
  final double fraction;
  final Color thumbColor;

  _SliderThumbPainter({
    required this.fraction,
    required this.thumbColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = (fraction * size.width).clamp(10.0, size.width - 10.0);
    final center = Offset(x, size.height / 2);

    // Shadow
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..color = Colors.black45
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // White border ring
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Inner fill
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..color = thumbColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _SliderThumbPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.thumbColor != thumbColor;
  }
}

