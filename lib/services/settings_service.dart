
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent UI settings for FinAudio.
///
/// Current settings:
/// - [accentColor]: the accent/tap color used across the app.
/// - [darkIntensity]: a preset that controls how "deep" the dark surface
///   tones are (0..2). Stored as an int and interpreted by the theme builder.
class SettingsService {
  static const String _keyAccentColor = 'accent_color';
  static const String _keyDarkIntensity = 'dark_intensity';

  Color _accentColor = const Color(0xFFCC0000); // YouTube-Music-ish default.
  int _darkIntensity = 1; // 0 = lighter dark, 1 = default, 2 = deeper black.

  Color get accentColor => _accentColor;
  int get darkIntensity => _darkIntensity;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accentColor = _decodeColor(prefs.getString(_keyAccentColor));
    _darkIntensity = prefs.getInt(_keyDarkIntensity) ?? 1;
  }

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccentColor, _encodeColor(color));
  }

  Future<void> setDarkIntensity(int value) async {
    _darkIntensity = value.clamp(0, 2);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDarkIntensity, _darkIntensity);
  }

  /// Encodes a [Color] as a hex string for SharedPreferences.
  static String _encodeColor(Color color) {
    final a = color.alpha.toRadixString(16).padLeft(2, '0');
    final r = color.red.toRadixString(16).padLeft(2, '0');
    final g = color.green.toRadixString(16).padLeft(2, '0');
    final b = color.blue.toRadixString(16).padLeft(2, '0');
    return 'FF$a$r$g$b';
  }

  /// Decodes a hex string back into a [Color]. Returns the YouTube-red default
  /// if the stored value is missing or malformed.
  static Color _decodeColor(String? encoded) {
    if (encoded == null || encoded.length != 10 || !encoded.startsWith('FF')) {
      return const Color(0xFFCC0000);
    }
    try {
      final r = int.parse(encoded.substring(2, 4), radix: 16);
      final g = int.parse(encoded.substring(4, 6), radix: 16);
      final b = int.parse(encoded.substring(6, 8), radix: 16);
      return Color.fromARGB(255, r, g, b);
    } catch (_) {
      return const Color(0xFFCC0000);
    }
  }

  /// Predefined dark-intensity presets.
  static const List<_DarkIntensityPreset> darkIntensityPresets = [
    _DarkIntensityPreset(label: 'Soft dark', value: 0),
    _DarkIntensityPreset(label: 'Default', value: 1),
    _DarkIntensityPreset(label: 'Deep black', value: 2),
  ];
}

class _DarkIntensityPreset {
  final String label;
  final int value;
  const _DarkIntensityPreset({required this.label, required this.value});
}
