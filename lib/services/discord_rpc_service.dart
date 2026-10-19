import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:finaudio/services/player_service.dart';
import 'package:finaudio/services/settings_service.dart';

/// User profile details returned by Discord REST API on authentication.
class DiscordUserSummary {
  final String id;
  final String username;
  final String? avatar;
  final String token;

  const DiscordUserSummary({
    required this.id,
    required this.username,
    this.avatar,
    required this.token,
  });

  String? get avatarUrl => avatar != null
      ? 'https://cdn.discordapp.com/avatars/$id/$avatar.png'
      : null;
}

/// Centralized Discord Rich Presence service for FinAudio.
/// Provides a unified dual-engine architecture:
/// 1. Desktop (Windows / macOS / Linux): Native local IPC pipe via [dart_discord_presence]. Zero-login required.
/// 2. Mobile (Android / iOS): Live WebSocket Gateway connection with encrypted local token.
class DiscordRpcService {
  DiscordRpcService._internal();
  static final DiscordRpcService instance = DiscordRpcService._internal();

  /// User-provided Discord Application ID from Discord Developer Portal.
  static const String defaultAppId = '1561283600908025947';

  /// Official FinAudio Discord application icon hash and CDN URL.
  static const String appIconHash = '72615f31d71977d9f493f011a85da63b';
  static const String appIconUrl =
      'https://cdn.discordapp.com/app-icons/1561283600908025947/72615f31d71977d9f493f011a85da63b.png';
  static const String appIconFallbackUrl =
      'https://raw.githubusercontent.com/SharkyBurger/FinAudio/main/assets/icons/ic_launcher.png';

  SettingsService? _settings;
  PlayerService? _playerService;

  _DiscordDesktopClient? _desktopClient;
  _DiscordGatewayClient? _gatewayClient;

  StreamSubscription? _nowPlayingSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  Timer? _keepAliveTimer;

  /// Global asset cache of external image URLs to Discord media proxy paths ("mp:external/...").
  /// Shared across Desktop IPC and Mobile Gateway engines.
  final Map<String, String> _assetCache = {};
  final Set<String> _pendingAssetFetches = {};

  /// Flag indicating that a track transition is in progress.
  /// When true, temporary isPlaying=false events (from audio stream resets)
  /// will NOT clear the Discord presence.
  bool _isSwitchingTrack = false;

  /// Debounce timer for pausing. When playback is paused (and not switching tracks),
  /// wait 2.5 seconds before clearing presence so brief pause/resumes don't flicker.
  Timer? _clearDebounceTimer;

  /// Coalescing throttle timer to respect Discord's SET_ACTIVITY rate-limit (~1 update per second).
  Timer? _throttleTimer;
  DateTime? _lastSendTime;

  Track? _pendingTrack;
  bool _pendingIsPlaying = false;
  Duration _pendingPosition = Duration.zero;
  Duration? _pendingDuration;

  Track? _lastTrack;
  bool _lastIsPlaying = false;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;

  bool _isDesktopConnected = false;
  bool _isGatewayConnected = false;

  bool get isDesktopConnected => _isDesktopConnected;
  bool get isGatewayConnected => _isGatewayConnected;
  bool get isConnected => _isDesktopConnected || _isGatewayConnected;

  /// Validates a Discord account token via Discord API v10 and retrieves user profile details.
  /// Supports both OAuth2 Bearer tokens and raw user account tokens.
  static Future<DiscordUserSummary?> validateAndFetchUser(String token) async {
    final clean = token.trim().replaceAll('"', '').replaceAll("'", '');
    if (clean.isEmpty) return null;

    final candidates = <String>[];
    if (clean.toLowerCase().startsWith('bearer ') || clean.toLowerCase().startsWith('bot ')) {
      candidates.add(clean);
    } else {
      candidates.add('Bearer $clean');
      candidates.add(clean);
    }

    for (final authHeader in candidates) {
      try {
        final res = await http.get(
          Uri.parse('https://discord.com/api/v10/users/@me'),
          headers: {
            'Authorization': authHeader,
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final id = data['id'] as String? ?? '';
          final username = (data['global_name'] as String?) ??
              (data['username'] as String?) ??
              'Discord User';
          final avatar = data['avatar'] as String?;
          return DiscordUserSummary(
            id: id,
            username: username,
            avatar: avatar,
            token: authHeader,
          );
        }
      } catch (_) {}
    }
    return null;
  }

  /// Resolves an external HTTP/HTTPS image URL into a Discord CDN proxy path ("mp:external/...").
  /// Works across both Windows Desktop and Mobile Gateway using the configured Discord token.
  Future<void> resolveAsset(String url) async {
    if (url.isEmpty || _pendingAssetFetches.contains(url) || _assetCache.containsKey(url)) return;
    _pendingAssetFetches.add(url);

    try {
      final token = _settings?.discordToken;
      final appId = _settings?.discordAppId.isNotEmpty == true
          ? _settings!.discordAppId
          : defaultAppId;

      if (token == null || token.isEmpty) return;

      final rawToken = token.startsWith('Bearer ')
          ? token.substring(7)
          : (token.startsWith('Bot ') ? token.substring(4) : token);

      final authCandidates = <String>[rawToken, 'Bearer $rawToken'];
      final apiUrl = Uri.parse('https://discord.com/api/v10/applications/$appId/external-assets');
      final requestBody = jsonEncode({'urls': [url]});

      for (final authHeader in authCandidates) {
        try {
          final res = await http.post(
            apiUrl,
            headers: {
              'Authorization': authHeader,
              'Content-Type': 'application/json',
            },
            body: requestBody,
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode == 200) {
            final list = jsonDecode(res.body) as List<dynamic>;
            if (list.isNotEmpty) {
              final item = list.first as Map<String, dynamic>;
              final path = item['external_asset_path'] as String?;
              if (path != null && path.isNotEmpty) {
                _assetCache[url] = 'mp:$path';
                if (kDebugMode) {
                  print('[DiscordRPC] Resolved asset: $url -> mp:$path');
                }
                // Refresh presence if this asset is for the currently playing track or app icon
                if (_lastIsPlaying && _lastTrack != null &&
                    (_lastTrack?.publicThumbnailUrl == url ||
                     url == appIconUrl ||
                     url == appIconFallbackUrl)) {
                  _schedulePresenceUpdate(
                    track: _lastTrack!,
                    isPlaying: true,
                    position: _lastPosition,
                    duration: _lastDuration,
                  );
                }
                return;
              }
            }
            break;
          } else if (res.statusCode == 401 || res.statusCode == 403) {
            continue;
          } else {
            break;
          }
        } on TimeoutException {
          break;
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DiscordRPC] resolveAsset error for $url: $e');
      }
    } finally {
      _pendingAssetFetches.remove(url);
    }
  }

  /// Attaches to the active [PlayerService] and [SettingsService] instances.
  void attach({
    required PlayerService playerService,
    required SettingsService settingsService,
  }) {
    _playerService = playerService;
    _settings = settingsService;

    _settings?.removeListener(_onSettingsChanged);
    _settings?.addListener(_onSettingsChanged);

    _initEngines();
    _subscribePlayer();
  }

  void _onSettingsChanged() {
    final enabled = _settings?.discordRpcEnabled ?? true;
    if (!enabled) {
      clearPresence();
      _desktopClient?.dispose();
      _gatewayClient?.disconnect();
      return;
    }

    _initEngines();

    if (_lastTrack != null && _lastIsPlaying) {
      _schedulePresenceUpdate(
        track: _lastTrack!,
        isPlaying: true,
        position: _lastPosition,
        duration: _lastDuration,
        immediate: true,
      );
    }
  }

  void _initEngines() {
    final enabled = _settings?.discordRpcEnabled ?? true;
    if (!enabled) return;

    final appId = _settings?.discordAppId.isNotEmpty == true
        ? _settings!.discordAppId
        : defaultAppId;

    // Pre-resolve FinAudio application icons
    resolveAsset(appIconUrl);
    resolveAsset(appIconFallbackUrl);

    // Desktop Native IPC Engine
    if (DiscordRPC.isAvailable) {
      _desktopClient ??= _DiscordDesktopClient(
        appId: appId,
        onConnectionChanged: (connected) {
          _isDesktopConnected = connected;
        },
      );
      _desktopClient?.connect();
    }

    // Mobile / Gateway WebSocket Engine
    final token = _settings?.discordToken;
    if (token != null && token.isNotEmpty) {
      if (_gatewayClient == null || _gatewayClient?.token != token) {
        _gatewayClient?.disconnect();
        _gatewayClient = _DiscordGatewayClient(
          token: token,
          appId: appId,
          onConnectionChanged: (connected) {
            _isGatewayConnected = connected;
          },
        );
        _gatewayClient?.connect();
      }
    } else {
      _gatewayClient?.disconnect();
      _gatewayClient = null;
      _isGatewayConnected = false;
    }
  }

  void _subscribePlayer() {
    _nowPlayingSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();

    _nowPlayingSub = _playerService?.nowPlayingStream.listen((track) {
      if (track == null) {
        _isSwitchingTrack = false;
        _lastTrack = null;
        _clearDebounceTimer?.cancel();
        _clearDebounceTimer = null;
        _throttleTimer?.cancel();
        _throttleTimer = null;
        clearPresence();
      } else {
        _clearDebounceTimer?.cancel();
        _clearDebounceTimer = null;
        _isSwitchingTrack = true;
        _lastTrack = track;

        final thumb = track.publicThumbnailUrl;
        if (thumb != null && thumb.isNotEmpty) {
          resolveAsset(thumb);
        }

        // Send an immediate optimistic update so Discord switches song instantly
        _schedulePresenceUpdate(
          track: track,
          isPlaying: true,
          position: Duration.zero,
          duration: _playerService?.duration ?? track.duration,
          immediate: true,
        );
      }
    });

    _playingSub = _playerService?.playingStream.listen((isPlaying) {
      _lastIsPlaying = isPlaying;
      if (!isPlaying) {
        // If we are currently transitioning to a new song, DO NOT clear presence!
        if (_isSwitchingTrack) return;

        // User paused playback: wait 2.5 seconds before removing from Discord (Spotify behavior)
        _clearDebounceTimer?.cancel();
        _clearDebounceTimer = Timer(const Duration(milliseconds: 2500), () {
          _clearDebounceTimer = null;
          if (!(_playerService?.isPlaying ?? false)) {
            _throttleTimer?.cancel();
            _throttleTimer = null;
            clearPresence();
          }
        });
      } else if (_lastTrack != null) {
        _isSwitchingTrack = false;
        _clearDebounceTimer?.cancel();
        _clearDebounceTimer = null;
        _schedulePresenceUpdate(
          track: _lastTrack!,
          isPlaying: true,
          position: _playerService?.position ?? Duration.zero,
          duration: _playerService?.duration ?? _lastDuration,
        );
      }
    });

    _durationSub = _playerService?.durationStream.listen((dur) {
      if (_lastTrack != null && dur > Duration.zero) {
        _lastDuration = dur;
        if (_lastIsPlaying || _isSwitchingTrack) {
          _schedulePresenceUpdate(
            track: _lastTrack!,
            isPlaying: true,
            position: _playerService?.position ?? Duration.zero,
            duration: dur,
          );
        }
      }
    });

    // Throttled position update for seeks or milestone sync
    _positionSub = _playerService?.positionStream.listen((pos) {
      final diff = (pos.inSeconds - _lastPosition.inSeconds).abs();
      _lastPosition = pos;
      if (diff >= 3 && _lastTrack != null && (_lastIsPlaying || _isSwitchingTrack)) {
        _schedulePresenceUpdate(
          track: _lastTrack!,
          isPlaying: true,
          position: pos,
          duration: _playerService?.duration ?? _lastDuration,
        );
      }
    });

    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_lastIsPlaying && _lastTrack != null && (_settings?.discordRpcEnabled ?? true)) {
        _schedulePresenceUpdate(
          track: _lastTrack!,
          isPlaying: true,
          position: _playerService?.position ?? _lastPosition,
          duration: _playerService?.duration ?? _lastDuration,
        );
      }
    });
  }

  /// Schedules a presence update, coalescing rapid calls to avoid Discord rate limits.
  void _schedulePresenceUpdate({
    required Track track,
    required bool isPlaying,
    required Duration position,
    Duration? duration,
    bool immediate = false,
  }) {
    final enabled = _settings?.discordRpcEnabled ?? true;
    if (!enabled) {
      clearPresence();
      return;
    }

    _pendingTrack = track;
    _pendingIsPlaying = isPlaying;
    _pendingPosition = position;
    if (duration != null && duration != Duration.zero) {
      _pendingDuration = duration;
    }

    final now = DateTime.now();
    final elapsed = _lastSendTime != null
        ? now.difference(_lastSendTime!)
        : const Duration(seconds: 10);

    // If immediate is requested (e.g. track switch) and cooldown passed, dispatch now.
    if (immediate && elapsed >= const Duration(milliseconds: 1000)) {
      _throttleTimer?.cancel();
      _throttleTimer = null;
      _dispatchPresenceNow();
      return;
    }

    // Otherwise coalesce rapid events so we don't spam faster than every 1.2s.
    if (_throttleTimer == null) {
      final remaining = const Duration(milliseconds: 1200) - elapsed;
      final delay = remaining.isNegative ? Duration.zero : remaining;
      _throttleTimer = Timer(delay, () {
        _throttleTimer = null;
        _dispatchPresenceNow();
      });
    }
  }

  void _dispatchPresenceNow() {
    _lastSendTime = DateTime.now();
    final track = _pendingTrack ?? _lastTrack;
    if (track == null || !_pendingIsPlaying) {
      clearPresence();
      return;
    }

    _lastTrack = track;
    _lastIsPlaying = true;
    _lastPosition = _pendingPosition;
    if (_pendingDuration != null && _pendingDuration != Duration.zero) {
      _lastDuration = _pendingDuration!;
    }

    final showButtons = _settings?.discordShowButtons ?? true;
    final showTimestamps = _settings?.discordShowTimestamps ?? true;

    // Desktop Native IPC
    if (DiscordRPC.isAvailable) {
      try {
        _desktopClient?.updatePresence(
          track: track,
          isPlaying: true,
          position: _lastPosition,
          duration: _lastDuration,
          showTimestamps: showTimestamps,
          showButtons: showButtons,
          assetCache: _assetCache,
        );
      } catch (_) {}
    }

    // Gateway WebSocket: only send if desktop native IPC is not available or disconnected
    // on the current machine (preventing dual-engine conflicts and rate-limit clobbering).
    final isDesktopPipeActive = DiscordRPC.isAvailable && (_desktopClient?.isConnected ?? false);
    if (_gatewayClient != null && !isDesktopPipeActive) {
      try {
        _gatewayClient?.updatePresence(
          track: track,
          isPlaying: true,
          position: _lastPosition,
          duration: _lastDuration,
          showTimestamps: showTimestamps,
          showButtons: showButtons,
          assetCache: _assetCache,
        );
      } catch (_) {}
    }
  }

  /// Updates Discord Rich Presence across active desktop and mobile gateway engines.
  Future<void> updatePresence({
    Track? track,
    bool isPlaying = false,
    Duration position = Duration.zero,
    Duration? duration,
  }) async {
    final enabled = _settings?.discordRpcEnabled ?? true;
    if (!enabled || track == null || !isPlaying) {
      _throttleTimer?.cancel();
      _throttleTimer = null;
      await clearPresence();
      return;
    }

    _schedulePresenceUpdate(
      track: track,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
      immediate: true,
    );
  }

  /// Clears presence on Discord.
  Future<void> clearPresence() async {
    _clearDebounceTimer?.cancel();
    _clearDebounceTimer = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _isSwitchingTrack = false;
    _lastIsPlaying = false;
    try {
      await _desktopClient?.clearPresence();
    } catch (_) {}
    try {
      _gatewayClient?.clearPresence();
    } catch (_) {}
  }

  /// Disposes background subscriptions and shuts down active engines.
  Future<void> dispose() async {
    _nowPlayingSub?.cancel();
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _clearDebounceTimer?.cancel();
    _clearDebounceTimer = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _settings?.removeListener(_onSettingsChanged);

    await clearPresence();
    await _desktopClient?.dispose();
    await _gatewayClient?.disconnect();

    _desktopClient = null;
    _gatewayClient = null;
    _isDesktopConnected = false;
    _isGatewayConnected = false;
  }
}

/// Desktop Discord RPC client utilizing native local IPC Named Pipes.
class _DiscordDesktopClient {
  final String appId;
  final ValueChanged<bool>? onConnectionChanged;

  DiscordRPC? _rpc;
  bool _connecting = false;
  Timer? _reconnectTimer;

  Track? _lastTrack;
  bool _lastIsPlaying = false;
  Duration _lastPosition = Duration.zero;
  Duration? _lastDuration;
  bool _lastShowTimestamps = true;
  bool _lastShowButtons = true;

  final Map<String, String> _assetCache = {};

  _DiscordDesktopClient({
    required this.appId,
    this.onConnectionChanged,
  });

  bool get isConnected => _rpc?.isConnected == true;

  Future<void> connect() async {
    if (!DiscordRPC.isAvailable || _connecting) return;
    if (_rpc != null && _rpc!.isConnected) return;

    _connecting = true;
    try {
      await _rpc?.dispose();
      _rpc = DiscordRPC();

      _rpc!.onReady.listen((_) {
        _connecting = false;
        onConnectionChanged?.call(true);
        if (_lastTrack != null && _lastIsPlaying) {
          _sendPresence();
        }
      });

      _rpc!.onDisconnected.listen((_) {
        _connecting = false;
        onConnectionChanged?.call(false);
        _scheduleReconnect();
      });

      _rpc!.onError.listen((event) {
        if (kDebugMode) {
          print('Discord RPC non-fatal event: ${event.message}');
        }
      });

      await _rpc!.initialize(appId);
    } catch (_) {
      _connecting = false;
      onConnectionChanged?.call(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 15), () {
      if (!isConnected && DiscordRPC.isAvailable) {
        connect();
      }
    });
  }

  Future<void> updatePresence({
    required Track track,
    required bool isPlaying,
    required Duration position,
    Duration? duration,
    bool showTimestamps = true,
    bool showButtons = true,
    Map<String, String>? assetCache,
  }) async {
    if (!DiscordRPC.isAvailable) return;

    _lastTrack = track;
    _lastIsPlaying = isPlaying;
    _lastPosition = position;
    _lastDuration = duration;
    _lastShowTimestamps = showTimestamps;
    _lastShowButtons = showButtons;
    if (assetCache != null) {
      _assetCache.addAll(assetCache);
    }

    if (!isPlaying) {
      await clearPresence();
      return;
    }

    if (!isConnected) {
      await connect();
    }

    if (isConnected) {
      await _sendPresence();
    }
  }

  Future<void> _sendPresence() async {
    if (!isConnected || _lastTrack == null || !_lastIsPlaying) return;
    final track = _lastTrack!;
    final totalDur = _lastDuration ?? track.duration;
    final now = DateTime.now();
    final start = now.subtract(_lastPosition);
    final end = start.add(totalDur);

    final publicThumb = track.publicThumbnailUrl;
    final hasThumbnail = publicThumb != null && publicThumb.isNotEmpty;
    final cachedProxy = hasThumbnail ? _assetCache[publicThumb] : null;

    final appIconProxy = _assetCache[DiscordRpcService.appIconUrl] ??
        _assetCache[DiscordRpcService.appIconFallbackUrl];
    final effectiveAppIcon = appIconProxy ?? DiscordRpcService.appIconFallbackUrl;

    // Trigger asynchronous proxy resolution if not cached yet
    if (hasThumbnail && cachedProxy == null) {
      DiscordRpcService.instance.resolveAsset(publicThumb);
    }

    // Windows Desktop IPC: use the cached mp:external/... path if available (same as mobile),
    // or fallback to publicThumb which Discord Desktop IPC proxies natively.
    final largeAsset = hasThumbnail
        ? DiscordAsset.fromUrl(cachedProxy ?? publicThumb, text: track.title)
        : DiscordAsset.fromUrl(effectiveAppIcon, text: 'FinAudio');

    final smallAsset = hasThumbnail
        ? DiscordAsset.fromUrl(effectiveAppIcon, text: 'FinAudio')
        : null;

    final presence = DiscordPresence(
      type: DiscordActivityType.listening,
      details: track.title,
      state: 'by ${track.formattedArtist}',
      timestamps: (_lastShowTimestamps && totalDur.inMilliseconds > 0)
          ? DiscordTimestamps.range(start, end)
          : null,
      largeAsset: largeAsset,
      smallAsset: smallAsset,
      statusDisplayType: DiscordStatusDisplayType.name,
      buttons: (_lastShowButtons && track.youtubeUrl.isNotEmpty)
          ? [DiscordButton(label: 'Listen on YouTube', url: track.youtubeUrl)]
          : null,
    );

    try {
      await _rpc!.setPresence(presence);
    } catch (_) {}
  }

  Future<void> clearPresence() async {
    if (!DiscordRPC.isAvailable || !isConnected) return;
    try {
      await _rpc!.clearPresence();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connecting = false;
    onConnectionChanged?.call(false);
    if (!DiscordRPC.isAvailable || _rpc == null) return;
    try {
      await _rpc!.dispose();
    } catch (_) {}
    _rpc = null;
  }
}

/// Mobile Gateway WebSocket client that connects directly to Discord Gateway servers.
class _DiscordGatewayClient {
  final String token;
  final String appId;
  final ValueChanged<bool>? onConnectionChanged;

  WebSocket? _ws;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _refreshTimer;
  int? _lastSeq;
  bool _authenticated = false;
  bool _connecting = false;
  bool _lastHeartbeatAckReceived = true;

  Track? _lastTrack;
  bool _lastIsPlaying = false;
  Duration _lastPosition = Duration.zero;
  Duration? _lastDuration;
  bool _lastShowTimestamps = true;
  bool _lastShowButtons = true;

  // Cache of external asset image URLs to Discord media proxy paths ("mp:external/...")
  final Map<String, String> _assetCache = {};
  final Set<String> _pendingAssetFetches = {};

  _DiscordGatewayClient({
    required this.token,
    required this.appId,
    this.onConnectionChanged,
  });

  bool get isAuthenticated => _authenticated && _ws != null && _ws!.readyState == WebSocket.open;

  Future<void> connect() async {
    if (_connecting) return;
    if (isAuthenticated) return;

    _connecting = true;
    await disconnect(notify: false);

    try {
      _ws = await WebSocket.connect('wss://gateway.discord.gg/?v=10&encoding=json')
          .timeout(const Duration(seconds: 10));

      _lastHeartbeatAckReceived = true;
      _ws!.listen(
        _onMessage,
        onError: (err) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      final op = map['op'] as int?;
      final d = map['d'];
      final seq = map['s'] as int?;
      if (seq != null) _lastSeq = seq;

      if (op == 10) {
        // HELLO
        final interval = (d as Map<String, dynamic>)['heartbeat_interval'] as int? ?? 41250;
        _startHeartbeat(interval);
        _identify();
      } else if (op == 11) {
        // HEARTBEAT_ACK
        _lastHeartbeatAckReceived = true;
      } else if (op == 0) {
        // DISPATCH
        final t = map['t'] as String?;
        if (t == 'READY' || t == 'RESUMED') {
          _authenticated = true;
          _connecting = false;
          onConnectionChanged?.call(true);
          // Pre-resolve app icon for mobile gateway badge
          _resolveAsset(DiscordRpcService.appIconUrl);
          _resolveAsset(DiscordRpcService.appIconFallbackUrl);
          // Restore presence immediately
          if (_lastTrack != null && _lastIsPlaying) {
            _sendPresencePayload();
          }
        }
      } else if (op == 9 || op == 7) {
        // INVALID_SESSION or RECONNECT
        _handleDisconnect();
      }
    } catch (_) {}
  }

  void _startHeartbeat(int intervalMs) {
    _heartbeatTimer?.cancel();
    _lastHeartbeatAckReceived = true;
    _heartbeatTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_ws != null && _ws!.readyState == WebSocket.open) {
        if (!_lastHeartbeatAckReceived) {
          // Missed heartbeat ACK - reconnect
          _handleDisconnect();
          return;
        }
        _lastHeartbeatAckReceived = false;
        _ws!.add(jsonEncode({'op': 1, 'd': _lastSeq}));
      }
    });

    // Also start a periodic presence refresh timer (every 25 seconds) to prevent activity timeout
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (isAuthenticated && _lastTrack != null && _lastIsPlaying) {
        _sendPresencePayload();
      }
    });
  }

  void _identify() {
    if (_ws != null && _ws!.readyState == WebSocket.open) {
      final initialActivity = (_lastTrack != null && _lastIsPlaying) ? _buildActivity() : null;
      final cleanToken = token.startsWith('Bearer ') ? token.substring(7) : token;
      _ws!.add(jsonEncode({
        'op': 2,
        'd': {
          'token': cleanToken,
          'properties': {
            'os': Platform.isAndroid ? 'Android' : (Platform.isWindows ? 'Windows' : 'FinAudio'),
            'browser': 'FinAudio',
            'device': 'FinAudio',
          },
          'presence': {
            'activities': initialActivity != null ? [initialActivity] : [],
            'status': 'online',
            'since': 0,
            'afk': false,
          },
        },
      }));
    }
  }

  Future<void> updatePresence({
    required Track track,
    required bool isPlaying,
    required Duration position,
    Duration? duration,
    bool showTimestamps = true,
    bool showButtons = true,
    Map<String, String>? assetCache,
  }) async {
    _lastTrack = track;
    _lastIsPlaying = isPlaying;
    _lastPosition = position;
    _lastDuration = duration;
    _lastShowTimestamps = showTimestamps;
    _lastShowButtons = showButtons;
    if (assetCache != null) {
      _assetCache.addAll(assetCache);
    }

    if (!isPlaying) {
      clearPresence();
      return;
    }

    // Check if public thumbnail URL needs proxy path resolution
    final publicThumb = track.publicThumbnailUrl;
    if (publicThumb != null &&
        publicThumb.isNotEmpty &&
        !_assetCache.containsKey(publicThumb)) {
      DiscordRpcService.instance.resolveAsset(publicThumb);
    }

    if (!_assetCache.containsKey(DiscordRpcService.appIconUrl)) {
      DiscordRpcService.instance.resolveAsset(DiscordRpcService.appIconUrl);
    }
    if (!_assetCache.containsKey(DiscordRpcService.appIconFallbackUrl)) {
      DiscordRpcService.instance.resolveAsset(DiscordRpcService.appIconFallbackUrl);
    }

    if (!isAuthenticated) {
      await connect();
      return;
    }

    _sendPresencePayload();
  }

  Future<void> _resolveAsset(String url) async {
    if (_pendingAssetFetches.contains(url)) return;
    _pendingAssetFetches.add(url);

    try {
      // Extract the raw token (strip any "Bearer " or "Bot " prefix).
      // Discord's external-assets endpoint requires the raw user account token
      // as the Authorization header — NOT prefixed with "Bearer".
      final rawToken = token.startsWith('Bearer ')
          ? token.substring(7)
          : (token.startsWith('Bot ') ? token.substring(4) : token);

      // Try auth header candidates: raw token first (user account tokens),
      // then Bearer prefix (OAuth2 tokens). The external-assets API rejects
      // Bearer-prefixed user account tokens with 401.
      final authCandidates = <String>[rawToken, 'Bearer $rawToken'];

      final apiUrl =
          Uri.parse('https://discord.com/api/v10/applications/$appId/external-assets');
      final requestBody = jsonEncode({'urls': [url]});

      for (final authHeader in authCandidates) {
        try {
          final res = await http.post(
            apiUrl,
            headers: {
              'Authorization': authHeader,
              'Content-Type': 'application/json',
            },
            body: requestBody,
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode == 200) {
            final list = jsonDecode(res.body) as List<dynamic>;
            if (list.isNotEmpty) {
              final item = list.first as Map<String, dynamic>;
              final path = item['external_asset_path'] as String?;
              if (path != null && path.isNotEmpty) {
                _assetCache[url] = 'mp:$path';
                if (kDebugMode) {
                  print('[DiscordRPC] Resolved asset: $url → mp:$path');
                }
                // Re-send presence if this is the active track or the application icon
                if (isAuthenticated &&
                    _lastIsPlaying &&
                    (_lastTrack?.publicThumbnailUrl == url ||
                     url == DiscordRpcService.appIconUrl ||
                     url == DiscordRpcService.appIconFallbackUrl)) {
                  _sendPresencePayload();
                }
                return; // Successfully resolved — stop trying other auth formats
              }
            }
            // 200 but no valid path — don't retry with next candidate
            break;
          } else if (res.statusCode == 401 || res.statusCode == 403) {
            // Auth format rejected — try the next candidate
            if (kDebugMode) {
              print('[DiscordRPC] external-assets ${res.statusCode} with auth '
                  '"${authHeader.substring(0, authHeader.length.clamp(0, 12))}…", retrying…');
            }
            continue;
          } else {
            if (kDebugMode) {
              print('[DiscordRPC] external-assets failed: ${res.statusCode} ${res.body}');
            }
            break;
          }
        } on TimeoutException {
          break;
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DiscordRPC] _resolveAsset error for $url: $e');
      }
    } finally {
      _pendingAssetFetches.remove(url);
    }
  }

  Map<String, dynamic> _buildActivity() {
    final track = _lastTrack!;
    final totalDur = _lastDuration ?? track.duration;
    final now = DateTime.now();
    final startMs = now.millisecondsSinceEpoch - _lastPosition.inMilliseconds;
    final endMs = startMs + totalDur.inMilliseconds;

    final publicThumb = track.publicThumbnailUrl;
    final hasThumbnail = publicThumb != null && publicThumb.isNotEmpty;
    final cachedProxy = hasThumbnail ? _assetCache[publicThumb] : null;

    final appIconProxy = _assetCache[DiscordRpcService.appIconUrl] ??
        _assetCache[DiscordRpcService.appIconFallbackUrl];

    // Gateway does NOT auto-proxy raw HTTPS URLs (only Desktop IPC does).
    // Only use mp:external/... proxy paths. If the cover art proxy isn't
    // resolved yet, fall back to the app icon and trigger async resolution.
    String largeImage;
    String? smallImage;
    String largeText = track.title;

    if (cachedProxy != null) {
      // Cover art proxy resolved → show cover as large, app icon as small badge
      largeImage = cachedProxy;
      smallImage = appIconProxy;
    } else {
      // Cover art not yet proxied → use app icon as large image (no badge)
      largeImage = appIconProxy ?? DiscordRpcService.appIconHash;
      largeText = 'FinAudio';
      // Trigger async resolution so next update will have the cover art
      if (hasThumbnail) {
        DiscordRpcService.instance.resolveAsset(publicThumb);
      }
    }

    final Map<String, dynamic> activity = {
      'name': 'FinAudio',
      'type': 2, // 2 = Listening to
      'details': track.title,
      'state': 'by ${track.formattedArtist}',
      'application_id': appId,
    };

    if (largeImage.isNotEmpty) {
      final assets = <String, dynamic>{
        'large_image': largeImage,
        'large_text': largeText,
      };
      if (smallImage != null && smallImage.isNotEmpty) {
        assets['small_image'] = smallImage;
        assets['small_text'] = 'FinAudio';
      }
      activity['assets'] = assets;
    }

    if (_lastShowTimestamps && totalDur.inMilliseconds > 0) {
      activity['timestamps'] = {
        'start': startMs,
        'end': endMs,
      };
    }

    if (_lastShowButtons && track.youtubeUrl.isNotEmpty) {
      activity['buttons'] = ['Listen on YouTube'];
      activity['metadata'] = {
        'button_urls': [track.youtubeUrl],
      };
    }

    return activity;
  }

  void _sendPresencePayload() {
    if (!isAuthenticated || _lastTrack == null || !_lastIsPlaying) return;
    try {
      final activity = _buildActivity();
      _ws!.add(jsonEncode({
        'op': 3,
        'd': {
          'since': 0,
          'activities': [activity],
          'status': 'online',
          'afk': false,
        },
      }));
    } catch (_) {}
  }

  void clearPresence() {
    if (isAuthenticated) {
      try {
        _ws!.add(jsonEncode({
          'op': 3,
          'd': {
            'since': 0,
            'activities': [],
            'status': 'online',
            'afk': false,
          },
        }));
      } catch (_) {}
    }
  }

  void _handleDisconnect() {
    _authenticated = false;
    _connecting = false;
    onConnectionChanged?.call(false);
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 15), () {
      connect();
    });
  }

  Future<void> disconnect({bool notify = true}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _authenticated = false;
    _connecting = false;
    if (_ws != null) {
      try {
        await _ws!.close(WebSocketStatus.normalClosure);
      } catch (_) {}
      _ws = null;
    }
    if (notify) onConnectionChanged?.call(false);
  }
}
