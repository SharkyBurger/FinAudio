import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../services/settings_service.dart';

/// Settings screen that lets the user customize the app's dark theme and
/// accent color. Changes are persisted immediately.
class SettingsScreen extends StatefulWidget {
  final SettingsService settingsService;
  final VoidCallback? onChanged;

  const SettingsScreen({
    super.key,
    required this.settingsService,
    this.onChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsService _settings = widget.settingsService;
  late Color _accentColor;
  late int _darkIntensity;

  @override
  void initState() {
    super.initState();
    _accentColor = _settings.accentColor;
    _darkIntensity = _settings.darkIntensity;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'Theme'),
          const SizedBox(height: 12),
          _DarkIntensitySection(
            currentValue: _darkIntensity,
            onChanged: (value) {
              setState(() => _darkIntensity = value);
              _settings.setDarkIntensity(value);
              widget.onChanged?.call();
            },
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Accent color'),
          const SizedBox(height: 12),
          _AccentColorSection(
            currentColor: _accentColor,
            onSelected: (color) {
              setState(() => _accentColor = color);
              _settings.setAccentColor(color);
              widget.onChanged?.call();
            },
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'About'),
          const SizedBox(height: 12),
          _AboutSection(),
        ],
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

class _DarkIntensitySection extends StatelessWidget {
  final int currentValue;
  final ValueChanged<int> onChanged;

  const _DarkIntensitySection({
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: SettingsService.darkIntensityPresets.map((preset) {
        final selected = preset.value == currentValue;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => onChanged(preset.value),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: selected
                    ? null
                    : Border.all(
                        color: theme.colorScheme.outline.withAlpha(60),
                      ),
              ),
              child: Row(
                children: [
                  Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CustomPaint(
                        painter: _RadioPainter(
                          isActive: selected,
                          activeColor:
                              theme.colorScheme.primary.withAlpha(255),
                          inactiveColor: theme.colorScheme.onSurface.withAlpha(80),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      preset.label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RadioPainter extends CustomPainter {
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;

  _RadioPainter({
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // Outer ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = inactiveColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    if (isActive) {
      canvas.drawCircle(
        center,
        4,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadioPainter oldDelegate) {
    return oldDelegate.isActive != isActive ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

class _AccentColorSection extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onSelected;

  const _AccentColorSection({
    required this.currentColor,
    required this.onSelected,
  });

  static const List<Color> _presets = [
    Color(0xFFCC0000), // YouTube red
    Color(0xFF00B0FF), // Bright blue
    Color(0xFF1DB954), // Spotify green
    Color(0xFFFF6B1A), // Orange
    Color(0xFF9B51E0), // Purple
    Color(0xFF00A86B), // Teal green
    Color(0xFFE1306C), // Pink
    Color(0xFF333333), // Near-black accent
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Preset chips.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _presets.map((color) {
            final selected = color.toARGB32() == currentColor.toARGB32();
            return GestureDetector(
              onTap: () => onSelected(color),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.outline.withAlpha(120),
                    width: selected ? 3 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: color.withAlpha(120),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        // Full picker.
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text(
                'Pick any color',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ColorPicker(
                pickerColor: currentColor,
                onColorChanged: onSelected,
                enableAlpha: false,
                displayThumbColor: true,
                labelTypes: const [],
                portraitOnly: true,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '#${currentColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(12),
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
            'Ad-free YouTube audio player with Google playlist sync.',
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
