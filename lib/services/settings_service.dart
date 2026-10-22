import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preset theme containing coordinated background, surface, button/accent,
/// and text colors.
class ThemePreset {
  final String id;
  final String name;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color accentColor;
  final Color textColor;
  final Color? cardColor;
  final Color? playerBarColor;
  final Color? secondaryTextColor;
  final Color? secondaryAccentColor;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.accentColor,
    required this.textColor,
    this.cardColor,
    this.playerBarColor,
    this.secondaryTextColor,
    this.secondaryAccentColor,
  });
}

/// Persistent UI settings for FinAudio.
///
/// Supports full theme customization:
/// - [backgroundColor]: scaffold and app backdrop.
/// - [surfaceColor]: cards, sheets, containers, and navigation bars.
/// - [accentColor]: primary buttons, active playback sliders, highlights.
/// - [textColor]: titles, body text, with contrast-derived secondary shades.
/// - [darkIntensity]: backwards-compatible preset intensity level (0..2).
class SettingsService extends ChangeNotifier {
  static SettingsService? instance;

  static const String _keyBackgroundColor = 'theme_background_color';
  static const String _keySurfaceColor = 'theme_surface_color';
  static const String _keyAccentColor = 'theme_accent_color';
  static const String _keyTextColor = 'theme_text_color';
  static const String _keyCardColor = 'theme_card_color';
  static const String _keyPlayerBarColor = 'theme_player_bar_color';
  static const String _keySecondaryTextColor = 'theme_secondary_text_color';
  static const String _keySecondaryAccentColor = 'theme_secondary_accent_color';
  static const String _keyWallpaperPath = 'theme_wallpaper_path';
  static const String _keyWallpaperBrightness = 'theme_wallpaper_brightness';
  static const String _keyWallpaperContrast = 'theme_wallpaper_contrast';
  static const String _keyWallpaperVignette = 'theme_wallpaper_vignette';
  static const String _keyWallpaperBlur = 'theme_wallpaper_blur';
  static const String _keyWallpaperCardOpacity = 'theme_wallpaper_card_opacity';
  static const String _keyAppVolume = 'app_volume';
  static const String _keyFavoriteArtists = 'favorite_artists';
  static const String _keySpotifyClientId = 'spotify_client_id';
  static const String _keySpotifyClientSecret = 'spotify_client_secret';
  static const String _keyAudioQuality = 'audio_quality';

  // Legacy keys for backwards-compatibility
  static const String _legacyKeyAccentColor = 'accent_color';
  static const String _keyDarkIntensity = 'dark_intensity';

  // Default theme: Lemon Shark (Dark)
  static const Color defaultBackgroundColor = Color(0xFF14130A);
  static const Color defaultSurfaceColor = Color(0xFF262414);
  static const Color defaultAccentColor = Color(0xFFFFDE38);
  static const Color defaultTextColor = Color(0xFFFAF7E6);

  Color _backgroundColor = defaultBackgroundColor;
  Color _surfaceColor = defaultSurfaceColor;
  Color _accentColor = defaultAccentColor;
  Color _textColor = defaultTextColor;
  Color? _cardColor;
  Color? _playerBarColor;
  Color? _secondaryTextColor;
  Color? _secondaryAccentColor;
  String? _wallpaperPath;
  double _wallpaperBrightness = 0.0;
  double _wallpaperContrast = 1.0;
  double _wallpaperVignette = 0.0;
  double _wallpaperBlur = 0.0;
  double _wallpaperCardOpacity = 0.85;
  int _darkIntensity = 1;
  double _appVolume = 1.0;
  String _spotifyClientId = '';
  String _spotifyClientSecret = '';
  String _audioQuality = 'auto';

  // Lyrics Display Settings
  static const String _keyLyricsMode = 'lyrics_mode';
  static const String _keyLyricsAnimationStyle = 'lyrics_animation_style';
  static const String _keyChangeLyricsOnClick = 'lyrics_change_on_click';
  static const String _keyAutoScrollLyrics = 'lyrics_auto_scroll';
  static const String _keyBlurLyricsLines = 'lyrics_blur_lines';
  static const String _keyLyricsTextSize = 'lyrics_text_size';
  static const String _keyLyricsLineSpacing = 'lyrics_line_spacing';

  // Lyrics Providers Settings
  static const String _keyEnableBetterLyrics = 'lyrics_enable_betterlyrics';
  static const String _keyEnableBetterLyricsPortato = 'lyrics_enable_betterlyrics_portato';
  static const String _keyEnableYouLyPlus = 'lyrics_enable_youlyplus';
  static const String _keyEnableLrcLib = 'lyrics_enable_lrclib';
  static const String _keyEnableKuGou = 'lyrics_enable_kugou';
  static const String _keyEnableNetEase = 'lyrics_enable_netease';
  static const String _keyEnableUnison = 'lyrics_enable_unison';
  static const String _keyEnableSimpMusic = 'lyrics_enable_simpmusic';
  static const String _keyEnableMegalobiz = 'lyrics_enable_megalobiz';
  static const String _keyEnablePaxsenix = 'lyrics_enable_paxsenix';
  static const String _keyPaxsenixApiKey = 'lyrics_paxsenix_api_key';
  static const String _keyPaxsenixAppleMusic = 'lyrics_paxsenix_apple_music';
  static const String _keyPaxsenixSpotify = 'lyrics_paxsenix_spotify';
  static const String _keyPaxsenixMusixmatch = 'lyrics_paxsenix_musixmatch';
  static const String _keyPreferredLyricsProvider = 'lyrics_preferred_provider';

  // Lyrics Romanization Settings
  static const String _keyRomanizeJapanese = 'lyrics_romanize_japanese';
  static const String _keyRomanizeKorean = 'lyrics_romanize_korean';
  static const String _keyRomanizeChinese = 'lyrics_romanize_chinese';
  static const String _keyRomanizeHindi = 'lyrics_romanize_hindi';
  static const String _keyShowRomanizedLyrics = 'lyrics_show_romanized';
  static const String _keyShowTranslatedLyrics = 'lyrics_show_translated';
  static const String _keyAutoAlignLyricsOffset = 'lyrics_auto_align_offset';
  static const String _keyAutoSyncPlainLyrics = 'lyrics_auto_sync_plain';

  // Lyrics Color Settings
  static const String _keyLyricsActiveColor = 'lyrics_active_color';
  static const String _keyLyricsInactiveColor = 'lyrics_inactive_color';
  static const String _keyLyricsGlowColor = 'lyrics_glow_color';

  // Discord Rich Presence Settings
  static const String _keyDiscordRpcEnabled = 'discord_rpc_enabled';
  static const String _keyDiscordAppId = 'discord_app_id';
  static const String _keyDiscordToken = 'discord_token';
  static const String _keyDiscordUsername = 'discord_username';
  static const String _keyDiscordAvatar = 'discord_avatar';
  static const String _keyDiscordUserId = 'discord_user_id';
  static const String _keyDiscordShowButtons = 'discord_show_buttons';
  static const String _keyDiscordShowTimestamps = 'discord_show_timestamps';

  bool _discordRpcEnabled = true;
  String _discordAppId = '1561283600908025947';
  String? _discordToken;
  String? _discordUsername;
  String? _discordAvatar;
  String? _discordUserId;
  bool _discordShowButtons = true;
  bool _discordShowTimestamps = true;

  Color? _lyricsActiveColor;
  Color? _lyricsInactiveColor;
  Color? _lyricsGlowColor;

  String _lyricsMode = 'Enhanced';
  String _lyricsAnimationStyle = 'Fluid Apple Music';
  bool _changeLyricsOnClick = true;
  bool _autoScrollLyrics = true;
  bool _blurLyricsLines = true;
  double _lyricsTextSize = 26.0;
  double _lyricsLineSpacing = 1.3;
  bool _showRomanizedLyrics = true;
  bool _showTranslatedLyrics = true;
  bool _autoAlignLyricsOffset = true;
  bool _autoSyncPlainLyrics = true;

  bool _enableBetterLyrics = true;
  bool _enableBetterLyricsPortato = true;
  bool _enableYouLyPlus = true;
  bool _enableLrcLib = true;
  bool _enableKuGou = true;
  bool _enableNetEase = true;
  bool _enableUnison = true;
  bool _enableSimpMusic = true;
  bool _enableMegalobiz = true;
  bool _enablePaxsenix = true;
  String _paxsenixApiKey = '';
  bool _paxsenixAppleMusic = true;
  bool _paxsenixSpotify = true;
  bool _paxsenixMusixmatch = true;
  String _preferredLyricsProvider = 'BetterLyrics';

  bool _romanizeJapanese = true;
  bool _romanizeKorean = true;
  bool _romanizeChinese = true;
  bool _romanizeHindi = true;

  final Map<String, int> _lyricsOffsets = {};

  List<String> _favoriteArtists = [];

  Color get backgroundColor => _backgroundColor;
  Color get surfaceColor => _surfaceColor;
  Color get accentColor => _accentColor;
  Color get textColor => _textColor;
  Color? get customCardColor => _cardColor;
  Color get cardColor => _cardColor ?? _surfaceColor;
  Color? get customPlayerBarColor => _playerBarColor;
  Color get playerBarColor => _playerBarColor ?? _surfaceColor;
  Color? get customSecondaryTextColor => _secondaryTextColor;
  Color get secondaryTextColor => _secondaryTextColor ?? _textColor.withAlpha(170);
  Color? get customSecondaryAccentColor => _secondaryAccentColor;
  Color get secondaryAccentColor => _secondaryAccentColor ?? _accentColor;
  String? get wallpaperPath => _wallpaperPath;
  bool get hasWallpaper => _wallpaperPath != null && _wallpaperPath!.isNotEmpty;
  double get wallpaperBrightness => _wallpaperBrightness;
  double get wallpaperContrast => _wallpaperContrast;
  double get wallpaperVignette => _wallpaperVignette;
  double get wallpaperBlur => _wallpaperBlur;
  double get wallpaperCardOpacity => _wallpaperCardOpacity;
  int get darkIntensity => _darkIntensity;
  double get appVolume => _appVolume;
  double get volume => _appVolume;
  String get spotifyClientId => _spotifyClientId;
  String get spotifyClientSecret => _spotifyClientSecret;
  bool get hasSpotifyCredentials =>
      _spotifyClientId.isNotEmpty && _spotifyClientSecret.isNotEmpty;

  // Lyrics Display Getters
  String get lyricsMode => _lyricsMode;
  String get lyricsAnimationStyle => _lyricsAnimationStyle;
  bool get changeLyricsOnClick => _changeLyricsOnClick;
  bool get autoScrollLyrics => _autoScrollLyrics;
  bool get blurLyricsLines => _blurLyricsLines;
  double get lyricsTextSize => _lyricsTextSize;
  double get lyricsLineSpacing => _lyricsLineSpacing;

  // Lyrics Providers Getters
  bool get enableBetterLyrics => _enableBetterLyrics;
  bool get enableBetterLyricsPortato => _enableBetterLyricsPortato;
  bool get enableYouLyPlus => _enableYouLyPlus;
  bool get enableLrcLib => _enableLrcLib;
  bool get enableKuGou => _enableKuGou;
  bool get enableNetEase => _enableNetEase;
  bool get enableUnison => _enableUnison;
  bool get enableSimpMusic => _enableSimpMusic;
  bool get enableMegalobiz => _enableMegalobiz;
  bool get enablePaxsenix => _enablePaxsenix;
  String get paxsenixApiKey => _paxsenixApiKey;
  bool get paxsenixAppleMusic => _paxsenixAppleMusic;
  bool get paxsenixSpotify => _paxsenixSpotify;
  bool get paxsenixMusixmatch => _paxsenixMusixmatch;
  String get preferredLyricsProvider => _preferredLyricsProvider;

  // Lyrics Romanization Getters
  bool get romanizeJapanese => _romanizeJapanese;
  bool get romanizeKorean => _romanizeKorean;
  bool get romanizeChinese => _romanizeChinese;
  bool get romanizeHindi => _romanizeHindi;
  bool get showRomanizedLyrics => _showRomanizedLyrics;
  bool get showTranslatedLyrics => _showTranslatedLyrics;
  bool get autoAlignLyricsOffset => _autoAlignLyricsOffset;
  bool get autoSyncPlainLyrics => _autoSyncPlainLyrics;

  // Lyrics Color Getters
  Color get lyricsActiveColor => _lyricsActiveColor ?? _textColor;
  Color? get customLyricsActiveColor => _lyricsActiveColor;
  Color get lyricsInactiveColor => _lyricsInactiveColor ?? _textColor.withValues(alpha: 0.35);
  Color? get customLyricsInactiveColor => _lyricsInactiveColor;
  Color get lyricsGlowColor => _lyricsGlowColor ?? _accentColor;
  Color? get customLyricsGlowColor => _lyricsGlowColor;
  bool get hasCustomLyricsColors =>
      _lyricsActiveColor != null || _lyricsInactiveColor != null || _lyricsGlowColor != null;

  // Discord Rich Presence Getters
  bool get discordRpcEnabled => _discordRpcEnabled;
  String get discordAppId => _discordAppId;
  String? get discordToken => _discordToken;
  String? get discordUsername => _discordUsername;
  String? get discordAvatar => _discordAvatar;
  String? get discordUserId => _discordUserId;
  bool get isDiscordConnectedOnMobile => _discordToken != null && _discordToken!.isNotEmpty;
  bool get discordShowButtons => _discordShowButtons;
  bool get discordShowTimestamps => _discordShowTimestamps;

  /// Curated presets for one-tap aesthetic switching.
  static const List<ThemePreset> presets = [
    ThemePreset(
      id: 'lemon_dark',
      name: 'Lemon Shark (Dark)',
      backgroundColor: Color(0xFF14130A),
      surfaceColor: Color(0xFF262414),
      accentColor: Color(0xFFFFDE38),
      textColor: Color(0xFFFAF7E6),
    ),
    ThemePreset(
      id: 'lemon_light',
      name: 'Lemon Shark (Light)',
      backgroundColor: Color(0xFFF6EFC4),
      surfaceColor: Color(0xFFFFFCE0),
      accentColor: Color(0xFFC78500),
      textColor: Color(0xFF2B2408),
    ),
    ThemePreset(
      id: 'oled',
      name: 'Pure OLED',
      backgroundColor: Color(0xFF000000),
      surfaceColor: Color(0xFF0D0D0D),
      accentColor: Color(0xFFFFFFFF),
      textColor: Color(0xFFF5F5F5),
    ),
    ThemePreset(
      id: 'midnight',
      name: 'Midnight Ocean',
      backgroundColor: Color(0xFF0B111E),
      surfaceColor: Color(0xFF151F32),
      accentColor: Color(0xFF00B0FF),
      textColor: Color(0xFFE1E7F0),
    ),
    ThemePreset(
      id: 'emerald',
      name: 'Emerald Cyber',
      backgroundColor: Color(0xFF0E1712),
      surfaceColor: Color(0xFF17241D),
      accentColor: Color(0xFF1DB954),
      textColor: Color(0xFFE6F5EC),
    ),
    ThemePreset(
      id: 'sunset',
      name: 'Sunset Glow',
      backgroundColor: Color(0xFF170F14),
      surfaceColor: Color(0xFF241720),
      accentColor: Color(0xFFFF5722),
      textColor: Color(0xFFF5EBEB),
    ),
    ThemePreset(
      id: 'neon',
      name: 'Neon Pink',
      backgroundColor: Color(0xFF12081D),
      surfaceColor: Color(0xFF1F1032),
      accentColor: Color(0xFFE040FB),
      textColor: Color(0xFFF2E6FF),
    ),
    ThemePreset(
      id: 'slate',
      name: 'Monochrome Slate',
      backgroundColor: Color(0xFF181A1F),
      surfaceColor: Color(0xFF242730),
      accentColor: Color(0xFF8FA3BF),
      textColor: Color(0xFFF0F4F8),
    ),
    ThemePreset(
      id: 'classic',
      name: 'YouTube Classic',
      backgroundColor: Color(0xFF0A0A0A),
      surfaceColor: Color(0xFF161616),
      accentColor: Color(0xFFCC0000),
      textColor: Color(0xFFE6E6E6),
    ),
    ThemePreset(
      id: 'ellen_joe',
      name: 'Ellen Joe (ZZZ)',
      backgroundColor: Color(0xFF101216),
      surfaceColor: Color(0xFF1B1E26),
      accentColor: Color(0xFFFF2A4D),
      textColor: Color(0xFFF4F6FA),
      cardColor: Color(0xFF242833),
      playerBarColor: Color(0xFF161820),
      secondaryTextColor: Color(0xFFA5ADBF),
      secondaryAccentColor: Color(0xFF00E5FF),
    ),
  ];

  /// Initialize and load all persisted preferences into memory.
  Future<void> init() async {
    SettingsService.instance = this;
    final prefs = await SharedPreferences.getInstance();

    final bgInt = prefs.getInt(_keyBackgroundColor);
    if (bgInt != null) {
      _backgroundColor = Color(bgInt);
    }

    final surfaceInt = prefs.getInt(_keySurfaceColor);
    if (surfaceInt != null) {
      _surfaceColor = Color(surfaceInt);
    }

    final accentInt = prefs.getInt(_keyAccentColor);
    if (accentInt != null) {
      _accentColor = Color(accentInt);
    } else {
      final legacyHex = prefs.getString(_legacyKeyAccentColor);
      if (legacyHex != null) {
        _accentColor = _decodeLegacyHex(legacyHex);
      }
    }

    final textInt = prefs.getInt(_keyTextColor);
    if (textInt != null) {
      _textColor = Color(textInt);
    }

    final cardInt = prefs.getInt(_keyCardColor);
    if (cardInt != null) _cardColor = Color(cardInt);

    final playerBarInt = prefs.getInt(_keyPlayerBarColor);
    if (playerBarInt != null) _playerBarColor = Color(playerBarInt);

    final secondaryTextInt = prefs.getInt(_keySecondaryTextColor);
    if (secondaryTextInt != null) _secondaryTextColor = Color(secondaryTextInt);

    final secondaryAccentInt = prefs.getInt(_keySecondaryAccentColor);
    if (secondaryAccentInt != null) _secondaryAccentColor = Color(secondaryAccentInt);

    _wallpaperPath = prefs.getString(_keyWallpaperPath);
    _wallpaperBrightness = prefs.getDouble(_keyWallpaperBrightness) ?? 0.0;
    _wallpaperContrast = prefs.getDouble(_keyWallpaperContrast) ?? 1.0;
    _wallpaperVignette = prefs.getDouble(_keyWallpaperVignette) ?? 0.0;
    _wallpaperBlur = prefs.getDouble(_keyWallpaperBlur) ?? 0.0;
    _wallpaperCardOpacity = prefs.getDouble(_keyWallpaperCardOpacity) ?? 0.85;

    // If still on the legacy YouTube Classic default or the previous blue-tinted default,
    // migrate seamlessly to the true Lemon Shark (Dark) theme.
    final isLegacyOrBlueDefault = (_backgroundColor.toARGB32() == 0xFF0A0A0A &&
            _accentColor.toARGB32() == 0xFFCC0000) ||
        (_backgroundColor.toARGB32() == 0xFF0C131D &&
            _accentColor.toARGB32() == 0xFFF7D336);

    if (isLegacyOrBlueDefault) {
      _backgroundColor = defaultBackgroundColor;
      _surfaceColor = defaultSurfaceColor;
      _accentColor = defaultAccentColor;
      _textColor = defaultTextColor;
      await prefs.setInt(_keyBackgroundColor, defaultBackgroundColor.toARGB32());
      await prefs.setInt(_keySurfaceColor, defaultSurfaceColor.toARGB32());
      await prefs.setInt(_keyAccentColor, defaultAccentColor.toARGB32());
      await prefs.setString(_legacyKeyAccentColor, _encodeLegacyHex(defaultAccentColor));
      await prefs.setInt(_keyTextColor, defaultTextColor.toARGB32());
    }

    _darkIntensity = prefs.getInt(_keyDarkIntensity) ?? 1;
    _appVolume = prefs.getDouble(_keyAppVolume) ?? 1.0;
    _spotifyClientId = prefs.getString(_keySpotifyClientId) ?? '';
    _spotifyClientSecret = prefs.getString(_keySpotifyClientSecret) ?? '';
    _favoriteArtists = prefs.getStringList(_keyFavoriteArtists) ?? [];

    _lyricsMode = prefs.getString(_keyLyricsMode) ?? 'Enhanced';
    _lyricsAnimationStyle =
        prefs.getString(_keyLyricsAnimationStyle) ?? 'Fluid Apple Music';
    _changeLyricsOnClick = prefs.getBool(_keyChangeLyricsOnClick) ?? true;
    _autoScrollLyrics = prefs.getBool(_keyAutoScrollLyrics) ?? true;
    _blurLyricsLines = prefs.getBool(_keyBlurLyricsLines) ?? true;
    _lyricsTextSize = prefs.getDouble(_keyLyricsTextSize) ?? 26.0;
    _lyricsLineSpacing = prefs.getDouble(_keyLyricsLineSpacing) ?? 1.3;

    _enableBetterLyrics = prefs.getBool(_keyEnableBetterLyrics) ?? true;
    _enableBetterLyricsPortato =
        prefs.getBool(_keyEnableBetterLyricsPortato) ?? true;
    _enableYouLyPlus = prefs.getBool(_keyEnableYouLyPlus) ?? true;
    _enableLrcLib = prefs.getBool(_keyEnableLrcLib) ?? true;
    _enableKuGou = prefs.getBool(_keyEnableKuGou) ?? true;
    _enableNetEase = prefs.getBool(_keyEnableNetEase) ?? true;
    _enableUnison = prefs.getBool(_keyEnableUnison) ?? true;
    _enableSimpMusic = prefs.getBool(_keyEnableSimpMusic) ?? true;
    _enableMegalobiz = prefs.getBool(_keyEnableMegalobiz) ?? true;
    _enablePaxsenix = prefs.getBool(_keyEnablePaxsenix) ?? true;
    _paxsenixApiKey = prefs.getString(_keyPaxsenixApiKey) ?? '';
    _paxsenixAppleMusic = prefs.getBool(_keyPaxsenixAppleMusic) ?? true;
    _paxsenixSpotify = prefs.getBool(_keyPaxsenixSpotify) ?? true;
    _paxsenixMusixmatch = prefs.getBool(_keyPaxsenixMusixmatch) ?? true;
    _preferredLyricsProvider =
        prefs.getString(_keyPreferredLyricsProvider) ?? 'BetterLyrics';

    _romanizeJapanese = prefs.getBool(_keyRomanizeJapanese) ?? true;
    _romanizeKorean = prefs.getBool(_keyRomanizeKorean) ?? true;
    _romanizeChinese = prefs.getBool(_keyRomanizeChinese) ?? true;
    _romanizeHindi = prefs.getBool(_keyRomanizeHindi) ?? true;
    _showRomanizedLyrics = prefs.getBool(_keyShowRomanizedLyrics) ?? true;
    _showTranslatedLyrics = prefs.getBool(_keyShowTranslatedLyrics) ?? true;
    _autoAlignLyricsOffset = prefs.getBool(_keyAutoAlignLyricsOffset) ?? true;
    _autoSyncPlainLyrics = prefs.getBool(_keyAutoSyncPlainLyrics) ?? true;

    final activeColInt = prefs.getInt(_keyLyricsActiveColor);
    if (activeColInt != null) _lyricsActiveColor = Color(activeColInt);
    final inactiveColInt = prefs.getInt(_keyLyricsInactiveColor);
    if (inactiveColInt != null) _lyricsInactiveColor = Color(inactiveColInt);
    final glowColInt = prefs.getInt(_keyLyricsGlowColor);
    if (glowColInt != null) _lyricsGlowColor = Color(glowColInt);

    _discordRpcEnabled = prefs.getBool(_keyDiscordRpcEnabled) ?? true;
    _discordAppId = prefs.getString(_keyDiscordAppId) ?? '1561283600908025947';
    _discordToken = prefs.getString(_keyDiscordToken);
    _discordUsername = prefs.getString(_keyDiscordUsername);
    _discordAvatar = prefs.getString(_keyDiscordAvatar);
    _discordUserId = prefs.getString(_keyDiscordUserId);
    _discordShowButtons = prefs.getBool(_keyDiscordShowButtons) ?? true;
    _discordShowTimestamps = prefs.getBool(_keyDiscordShowTimestamps) ?? true;

    _audioQuality = prefs.getString(_keyAudioQuality) ?? 'auto';

    for (final key in prefs.getKeys()) {
      if (key.startsWith('lyrics_offset_')) {
        final trackId = key.substring('lyrics_offset_'.length);
        _lyricsOffsets[trackId] = prefs.getInt(key) ?? 0;
      }
    }

    notifyListeners();
  }

  /// Gets the stored timing offset in milliseconds for the given track.
  int getLyricsOffsetMs(String trackId) {
    if (trackId.isEmpty) return 0;
    return _lyricsOffsets[trackId] ?? 0;
  }

  /// Sets and persists the lyrics timing offset in milliseconds for the given track.
  Future<void> setLyricsOffsetMs(String trackId, int offsetMs) async {
    if (trackId.isEmpty) return;
    _lyricsOffsets[trackId] = offsetMs;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (offsetMs == 0) {
      await prefs.remove('lyrics_offset_$trackId');
    } else {
      await prefs.setInt('lyrics_offset_$trackId', offsetMs);
    }
  }

  // Audio Quality Setting: 'auto' | 'high' | 'medium' | 'low'
  String get audioQuality => _audioQuality;

  Future<void> setAudioQuality(String quality) async {
    if (_audioQuality == quality) return;
    _audioQuality = quality;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudioQuality, quality);
  }

  /// Evaluates effective quality level:
  /// - If 'auto', detects whether connected to Wi-Fi/Ethernet (High) or Mobile Cellular (Medium/Data Saver)
  /// - Otherwise returns the user's explicit preference ('high', 'medium', 'low')
  Future<String> getEffectiveAudioQuality() async {
    if (_audioQuality != 'auto') {
      return _audioQuality;
    }
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.mobile)) {
        return 'medium';
      }
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        return 'high';
      }
    } catch (e) {
      debugPrint('SettingsService: Failed to check connectivity ($e)');
    }
    return 'high';
  }

  /// List of favorite/followed artists.
  List<String> get favoriteArtists => List.unmodifiable(_favoriteArtists);

  /// Checks if the given artist is followed.
  bool isArtistFollowed(String artist) {
    final lower = artist.trim().toLowerCase();
    return _favoriteArtists.any((a) => a.toLowerCase() == lower);
  }

  /// Toggles follow status for an artist and persists it.
  Future<bool> toggleFollowArtist(String artist) async {
    final trimmed = artist.trim();
    if (trimmed.isEmpty) return false;
    final index = _favoriteArtists.indexWhere(
      (a) => a.toLowerCase() == trimmed.toLowerCase(),
    );
    final nowFollowed = index < 0;
    if (nowFollowed) {
      _favoriteArtists.add(trimmed);
    } else {
      _favoriteArtists.removeAt(index);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyFavoriteArtists, _favoriteArtists);
    return nowFollowed;
  }

  /// Sets the Spotify Client ID and Client Secret for 1k+ track imports.
  Future<void> setSpotifyCredentials(String clientId, String clientSecret) async {
    _spotifyClientId = clientId.trim();
    _spotifyClientSecret = clientSecret.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySpotifyClientId, _spotifyClientId);
    await prefs.setString(_keySpotifyClientSecret, _spotifyClientSecret);
  }

  /// Clears stored Spotify credentials.
  Future<void> clearSpotifyCredentials() async {
    _spotifyClientId = '';
    _spotifyClientSecret = '';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySpotifyClientId);
    await prefs.remove(_keySpotifyClientSecret);
  }

  // Lyrics Setters
  Future<void> setLyricsMode(String mode) async {
    _lyricsMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLyricsMode, mode);
  }

  Future<void> setLyricsAnimationStyle(String style) async {
    _lyricsAnimationStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLyricsAnimationStyle, style);
  }

  Future<void> setChangeLyricsOnClick(bool value) async {
    _changeLyricsOnClick = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyChangeLyricsOnClick, value);
  }

  Future<void> setAutoScrollLyrics(bool value) async {
    _autoScrollLyrics = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoScrollLyrics, value);
  }

  Future<void> setBlurLyricsLines(bool value) async {
    _blurLyricsLines = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBlurLyricsLines, value);
  }

  Future<void> setLyricsTextSize(double size) async {
    _lyricsTextSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLyricsTextSize, size);
  }

  Future<void> setLyricsLineSpacing(double spacing) async {
    _lyricsLineSpacing = spacing;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLyricsLineSpacing, spacing);
  }

  Future<void> setAutoAlignLyricsOffset(bool value) async {
    _autoAlignLyricsOffset = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoAlignLyricsOffset, value);
  }

  Future<void> setAutoSyncPlainLyrics(bool value) async {
    _autoSyncPlainLyrics = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSyncPlainLyrics, value);
  }

  Future<void> setLyricsProviderEnabled(String providerKey, bool value) async {
    switch (providerKey) {
      case 'betterlyrics':
        _enableBetterLyrics = value;
        break;
      case 'betterlyrics_portato':
        _enableBetterLyricsPortato = value;
        break;
      case 'youlyplus':
        _enableYouLyPlus = value;
        break;
      case 'lrclib':
        _enableLrcLib = value;
        break;
      case 'kugou':
        _enableKuGou = value;
        break;
      case 'netease':
        _enableNetEase = value;
        break;
      case 'unison':
        _enableUnison = value;
        break;
      case 'simpmusic':
        _enableSimpMusic = value;
        break;
      case 'megalobiz':
        _enableMegalobiz = value;
        break;
      case 'paxsenix':
        _enablePaxsenix = value;
        break;
      case 'paxsenix_apple_music':
        _paxsenixAppleMusic = value;
        break;
      case 'paxsenix_spotify':
        _paxsenixSpotify = value;
        break;
      case 'paxsenix_musixmatch':
        _paxsenixMusixmatch = value;
        break;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    switch (providerKey) {
      case 'betterlyrics':
        await prefs.setBool(_keyEnableBetterLyrics, value);
        break;
      case 'betterlyrics_portato':
        await prefs.setBool(_keyEnableBetterLyricsPortato, value);
        break;
      case 'youlyplus':
        await prefs.setBool(_keyEnableYouLyPlus, value);
        break;
      case 'lrclib':
        await prefs.setBool(_keyEnableLrcLib, value);
        break;
      case 'kugou':
        await prefs.setBool(_keyEnableKuGou, value);
        break;
      case 'netease':
        await prefs.setBool(_keyEnableNetEase, value);
        break;
      case 'unison':
        await prefs.setBool(_keyEnableUnison, value);
        break;
      case 'simpmusic':
        await prefs.setBool(_keyEnableSimpMusic, value);
        break;
      case 'megalobiz':
        await prefs.setBool(_keyEnableMegalobiz, value);
        break;
      case 'paxsenix':
        await prefs.setBool(_keyEnablePaxsenix, value);
        break;
      case 'paxsenix_apple_music':
        await prefs.setBool(_keyPaxsenixAppleMusic, value);
        break;
      case 'paxsenix_spotify':
        await prefs.setBool(_keyPaxsenixSpotify, value);
        break;
      case 'paxsenix_musixmatch':
        await prefs.setBool(_keyPaxsenixMusixmatch, value);
        break;
    }
  }

  Future<void> setPaxsenixApiKey(String key) async {
    _paxsenixApiKey = key.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPaxsenixApiKey, _paxsenixApiKey);
  }

  Future<void> setPreferredLyricsProvider(String provider) async {
    _preferredLyricsProvider = provider;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreferredLyricsProvider, provider);
  }

  Future<void> setRomanizeOption(String lang, bool value) async {
    switch (lang.toLowerCase()) {
      case 'japanese':
        _romanizeJapanese = value;
        break;
      case 'korean':
        _romanizeKorean = value;
        break;
      case 'chinese':
        _romanizeChinese = value;
        break;
      case 'hindi':
        _romanizeHindi = value;
        break;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    switch (lang.toLowerCase()) {
      case 'japanese':
        await prefs.setBool(_keyRomanizeJapanese, value);
        break;
      case 'korean':
        await prefs.setBool(_keyRomanizeKorean, value);
        break;
      case 'chinese':
        await prefs.setBool(_keyRomanizeChinese, value);
        break;
      case 'hindi':
        await prefs.setBool(_keyRomanizeHindi, value);
        break;
    }
  }

  Future<void> setShowRomanizedLyrics(bool value) async {
    if (_showRomanizedLyrics == value) return;
    _showRomanizedLyrics = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowRomanizedLyrics, value);
  }

  Future<void> setShowTranslatedLyrics(bool value) async {
    if (_showTranslatedLyrics == value) return;
    _showTranslatedLyrics = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowTranslatedLyrics, value);
  }

  Future<void> setLyricsActiveColor(Color color) async {
    _lyricsActiveColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLyricsActiveColor, color.toARGB32());
  }

  Future<void> setLyricsInactiveColor(Color color) async {
    _lyricsInactiveColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLyricsInactiveColor, color.toARGB32());
  }

  Future<void> setLyricsGlowColor(Color color) async {
    _lyricsGlowColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLyricsGlowColor, color.toARGB32());
  }

  Future<void> resetLyricsColors() async {
    _lyricsActiveColor = null;
    _lyricsInactiveColor = null;
    _lyricsGlowColor = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLyricsActiveColor);
    await prefs.remove(_keyLyricsInactiveColor);
    await prefs.remove(_keyLyricsGlowColor);
  }

  // Discord Rich Presence Setters
  Future<void> setDiscordRpcEnabled(bool value) async {
    if (_discordRpcEnabled == value) return;
    _discordRpcEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDiscordRpcEnabled, value);
  }

  Future<void> setDiscordAppId(String id) async {
    if (_discordAppId == id) return;
    _discordAppId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDiscordAppId, id);
  }

  Future<void> setDiscordAccount({
    required String token,
    required String username,
    String? avatar,
    String? userId,
  }) async {
    _discordToken = token;
    _discordUsername = username;
    _discordAvatar = avatar;
    _discordUserId = userId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDiscordToken, token);
    await prefs.setString(_keyDiscordUsername, username);
    if (avatar != null) {
      await prefs.setString(_keyDiscordAvatar, avatar);
    } else {
      await prefs.remove(_keyDiscordAvatar);
    }
    if (userId != null) {
      await prefs.setString(_keyDiscordUserId, userId);
    } else {
      await prefs.remove(_keyDiscordUserId);
    }
  }

  Future<void> disconnectDiscordAccount() async {
    _discordToken = null;
    _discordUsername = null;
    _discordAvatar = null;
    _discordUserId = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyDiscordToken);
    await prefs.remove(_keyDiscordUsername);
    await prefs.remove(_keyDiscordAvatar);
    await prefs.remove(_keyDiscordUserId);
  }

  Future<void> setDiscordShowButtons(bool value) async {
    if (_discordShowButtons == value) return;
    _discordShowButtons = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDiscordShowButtons, value);
  }

  Future<void> setDiscordShowTimestamps(bool value) async {
    if (_discordShowTimestamps == value) return;
    _discordShowTimestamps = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDiscordShowTimestamps, value);
  }

  /// Sets the in-app volume (0.0 to 1.0) and persists it.
  Future<void> setAppVolume(double volume) async {
    _appVolume = volume.clamp(0.0, 1.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyAppVolume, _appVolume);
  }

  /// Alias for setAppVolume
  Future<void> setVolume(double volume) => setAppVolume(volume);

  /// Sets the accent color and persists it.
  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAccentColor, color.toARGB32());
    await prefs.setString(_legacyKeyAccentColor, _encodeLegacyHex(color));
  }

  /// Sets the background color and persists it.
  Future<void> setBackgroundColor(Color color) async {
    _backgroundColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBackgroundColor, color.toARGB32());
  }

  /// Sets the surface/card color and persists it.
  Future<void> setSurfaceColor(Color color) async {
    _surfaceColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySurfaceColor, color.toARGB32());
  }

  /// Sets the text color and persists it.
  Future<void> setTextColor(Color color) async {
    _textColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTextColor, color.toARGB32());
  }

  /// Sets the card/tile surface color and persists it.
  Future<void> setCardColor(Color? color) async {
    _cardColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color != null) {
      await prefs.setInt(_keyCardColor, color.toARGB32());
    } else {
      await prefs.remove(_keyCardColor);
    }
  }

  /// Sets the player bar color and persists it.
  Future<void> setPlayerBarColor(Color? color) async {
    _playerBarColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color != null) {
      await prefs.setInt(_keyPlayerBarColor, color.toARGB32());
    } else {
      await prefs.remove(_keyPlayerBarColor);
    }
  }

  /// Sets the secondary text color and persists it.
  Future<void> setSecondaryTextColor(Color? color) async {
    _secondaryTextColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color != null) {
      await prefs.setInt(_keySecondaryTextColor, color.toARGB32());
    } else {
      await prefs.remove(_keySecondaryTextColor);
    }
  }

  /// Sets the secondary accent color and persists it.
  Future<void> setSecondaryAccentColor(Color? color) async {
    _secondaryAccentColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color != null) {
      await prefs.setInt(_keySecondaryAccentColor, color.toARGB32());
    } else {
      await prefs.remove(_keySecondaryAccentColor);
    }
  }

  /// Sets the custom wallpaper image file path and persists it.
  Future<void> setWallpaperPath(String? path) async {
    _wallpaperPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (path != null && path.isNotEmpty) {
      await prefs.setString(_keyWallpaperPath, path);
    } else {
      await prefs.remove(_keyWallpaperPath);
    }
  }

  /// Sets the wallpaper brightness (-1.0 to 1.0) and persists it.
  Future<void> setWallpaperBrightness(double value) async {
    _wallpaperBrightness = value.clamp(-1.0, 1.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyWallpaperBrightness, _wallpaperBrightness);
  }

  /// Sets the wallpaper contrast (0.5 to 2.0) and persists it.
  Future<void> setWallpaperContrast(double value) async {
    _wallpaperContrast = value.clamp(0.5, 2.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyWallpaperContrast, _wallpaperContrast);
  }

  /// Sets the wallpaper vignette overlay intensity (0.0 to 1.0) and persists it.
  Future<void> setWallpaperVignette(double value) async {
    _wallpaperVignette = value.clamp(0.0, 1.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyWallpaperVignette, _wallpaperVignette);
  }

  /// Sets the wallpaper blur intensity (0.0 to 20.0) and persists it.
  Future<void> setWallpaperBlur(double value) async {
    _wallpaperBlur = value.clamp(0.0, 20.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyWallpaperBlur, _wallpaperBlur);
  }

  /// Sets the island card opacity (0.1 to 1.0) when wallpaper is active and persists it.
  Future<void> setWallpaperCardOpacity(double value) async {
    _wallpaperCardOpacity = value.clamp(0.1, 1.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyWallpaperCardOpacity, _wallpaperCardOpacity);
  }

  /// Clears the active wallpaper.
  Future<void> clearWallpaper() async {
    _wallpaperPath = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyWallpaperPath);
  }

  /// Updates any subset of custom theme colors and persists them all.
  Future<void> setCustomTheme({
    Color? background,
    Color? surface,
    Color? accent,
    Color? text,
    Color? card,
    Color? playerBar,
    Color? secondaryText,
    Color? secondaryAccent,
    bool updateCard = false,
    bool updatePlayerBar = false,
    bool updateSecondaryText = false,
    bool updateSecondaryAccent = false,
  }) async {
    if (background != null) _backgroundColor = background;
    if (surface != null) _surfaceColor = surface;
    if (accent != null) _accentColor = accent;
    if (text != null) _textColor = text;
    if (updateCard || card != null) _cardColor = card;
    if (updatePlayerBar || playerBar != null) _playerBarColor = playerBar;
    if (updateSecondaryText || secondaryText != null) _secondaryTextColor = secondaryText;
    if (updateSecondaryAccent || secondaryAccent != null) _secondaryAccentColor = secondaryAccent;

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (background != null) {
      await prefs.setInt(_keyBackgroundColor, background.toARGB32());
    }
    if (surface != null) {
      await prefs.setInt(_keySurfaceColor, surface.toARGB32());
    }
    if (accent != null) {
      await prefs.setInt(_keyAccentColor, accent.toARGB32());
      await prefs.setString(_legacyKeyAccentColor, _encodeLegacyHex(accent));
    }
    if (text != null) {
      await prefs.setInt(_keyTextColor, text.toARGB32());
    }
    if (updateCard || card != null) {
      if (card != null) {
        await prefs.setInt(_keyCardColor, card.toARGB32());
      } else {
        await prefs.remove(_keyCardColor);
      }
    }
    if (updatePlayerBar || playerBar != null) {
      if (playerBar != null) {
        await prefs.setInt(_keyPlayerBarColor, playerBar.toARGB32());
      } else {
        await prefs.remove(_keyPlayerBarColor);
      }
    }
    if (updateSecondaryText || secondaryText != null) {
      if (secondaryText != null) {
        await prefs.setInt(_keySecondaryTextColor, secondaryText.toARGB32());
      } else {
        await prefs.remove(_keySecondaryTextColor);
      }
    }
    if (updateSecondaryAccent || secondaryAccent != null) {
      if (secondaryAccent != null) {
        await prefs.setInt(_keySecondaryAccentColor, secondaryAccent.toARGB32());
      } else {
        await prefs.remove(_keySecondaryAccentColor);
      }
    }
  }

  /// Applies an entire preset theme.
  Future<void> applyPreset(ThemePreset preset) async {
    await setCustomTheme(
      background: preset.backgroundColor,
      surface: preset.surfaceColor,
      accent: preset.accentColor,
      text: preset.textColor,
      card: preset.cardColor,
      playerBar: preset.playerBarColor,
      secondaryText: preset.secondaryTextColor,
      secondaryAccent: preset.secondaryAccentColor,
      updateCard: true,
      updatePlayerBar: true,
      updateSecondaryText: true,
      updateSecondaryAccent: true,
    );
  }

  /// Resets theme colors back to Lemon Shark (Dark) defaults.
  Future<void> resetToDefault() async {
    await setCustomTheme(
      background: defaultBackgroundColor,
      surface: defaultSurfaceColor,
      accent: defaultAccentColor,
      text: defaultTextColor,
      card: null,
      playerBar: null,
      secondaryText: null,
      secondaryAccent: null,
      updateCard: true,
      updatePlayerBar: true,
      updateSecondaryText: true,
      updateSecondaryAccent: true,
    );
  }

  /// Backwards-compatible setter for dark intensity.
  Future<void> setDarkIntensity(int value) async {
    _darkIntensity = value.clamp(0, 2);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDarkIntensity, _darkIntensity);
  }

  /// Legacy hex helper for migration and test compatibility.
  static String _encodeLegacyHex(Color color) {
    return color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  static Color _decodeLegacyHex(String? hex) {
    if (hex == null || hex.isEmpty) return defaultAccentColor;
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      } else if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      } else if (clean.length == 10 && clean.startsWith('FF')) {
        // Recover from previous malformed 10-char format: 'FFAARRGGBB'
        final r = int.parse(clean.substring(4, 6), radix: 16);
        final g = int.parse(clean.substring(6, 8), radix: 16);
        final b = int.parse(clean.substring(8, 10), radix: 16);
        return Color.fromARGB(255, r, g, b);
      }
    } catch (_) {}
    return defaultAccentColor;
  }

  /// Predefined dark-intensity presets (legacy).
  static const List<DarkIntensityPreset> darkIntensityPresets = [
    DarkIntensityPreset(label: 'Soft dark', value: 0),
    DarkIntensityPreset(label: 'Default', value: 1),
    DarkIntensityPreset(label: 'Deep black', value: 2),
  ];
}

class DarkIntensityPreset {
  final String label;
  final int value;
  const DarkIntensityPreset({required this.label, required this.value});
}
