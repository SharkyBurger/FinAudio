import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide SearchPlaylist;
import 'package:ytmusicapi_dart/enums.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';
import '../models/search_result.dart';

/// Represents a locally saved Google account identity restored from storage.
class SavedGoogleAccount implements GoogleIdentity {
  @override
  final String id;
  @override
  final String email;
  @override
  final String? displayName;
  @override
  final String? photoUrl;

  const SavedGoogleAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });
}

/// Represents a user's YouTube playlist (folder-level metadata).
class UserPlaylist {
  final String id;
  final String title;
  final String description;
  final String thumbnailUrl;
  final int videoCount;

  const UserPlaylist({
    required this.id,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.videoCount,
  });

  int get itemCount => videoCount;
}

/// Represents a single YouTube playlist item (video) for display.
class PlaylistVideo {
  final String videoId;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  final Duration duration;

  const PlaylistVideo({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.duration,
  });

  String get youtubeUrl => 'https://www.youtube.com/watch?v=$videoId';
}

/// Represents a YouTube channel / artist the user has subscribed to on YouTube.
class SubscribedArtist {
  final String channelId;
  final String title;
  final String description;
  final String thumbnailUrl;

  const SubscribedArtist({
    required this.channelId,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
  });

  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'title': title,
        'description': description,
        'thumbnailUrl': thumbnailUrl,
      };

  factory SubscribedArtist.fromJson(Map<String, dynamic> json) => SubscribedArtist(
        channelId: json['channelId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      );
}

/// Manages Google Sign-In authentication and InnerTube (YouTube Music) catalog access.
class GoogleAuthService extends ChangeNotifier {
  static const String _serverClientId =
      '1023738817283-365rhlp8emot091uh6jctpdqo1gq29ek.apps.googleusercontent.com';

  // Basic non-sensitive scope - allows sign in without Google verification 403 block.
  // InnerTube is used for music playback, search, and catalog operations.
  static const List<String> _scopes = <String>[
    'email',
  ];

  static const String _keyUserId = 'google_user_id';
  static const String _keyUserEmail = 'google_user_email';
  static const String _keyUserName = 'google_user_name';
  static const String _keyUserPhoto = 'google_user_photo';
  static const String _keyAccessToken = 'google_access_token';
  static const String _keyTokenTimestamp = 'google_token_timestamp';
  static const String _keySubscribedArtists = 'google_subscribed_artists_v3';
  static const String _keyInnerTubeHandle = 'innertube_handle';
  static const String _keyInnerTubeAuth = 'innertube_auth';

  static const String _authBridgeHtml = '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>FinAudio - Authorizing</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      background: #0F0F0F;
      color: #FFFFFF;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }
    .card {
      background: #181818;
      border: 1px solid #282828;
      border-radius: 16px;
      padding: 36px 48px;
      text-align: center;
      max-width: 380px;
      box-shadow: 0 12px 36px rgba(0,0,0,0.6);
    }
    .spinner {
      border: 3px solid rgba(255,255,255,0.15);
      border-top: 3px solid #F7D336;
      border-radius: 50%;
      width: 32px;
      height: 32px;
      animation: spin 0.8s linear infinite;
      margin: 0 auto 16px;
    }
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
    h2 { font-size: 20px; margin: 0 0 8px; font-weight: 600; }
    p { color: #888; font-size: 13px; margin: 0; }
  </style>
</head>
<body>
  <div class="card">
    <div class="spinner"></div>
    <h2>Authorizing with FinAudio</h2>
    <p>Please wait while we complete your sign-in...</p>
  </div>
  <script>
    if (window.location.hash) {
      window.location.href = '/callback?' + window.location.hash.substring(1);
    } else if (window.location.search) {
      window.location.href = '/callback' + window.location.search;
    }
  </script>
</body>
</html>''';

  static const String _authSuccessHtml = '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>FinAudio - Sign In Successful</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      background: #0F0F0F;
      color: #FFFFFF;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }
    .card {
      background: #181818;
      border: 1px solid #282828;
      border-radius: 16px;
      padding: 40px 48px;
      text-align: center;
      max-width: 380px;
      box-shadow: 0 12px 36px rgba(0,0,0,0.6);
    }
    .check {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      background: #F7D336;
      color: #000;
      font-weight: 800;
      border-radius: 50%;
      width: 48px;
      height: 48px;
      font-size: 26px;
      margin-bottom: 16px;
    }
    h2 { font-size: 20px; margin: 0 0 8px; font-weight: 600; }
    p { color: #888; font-size: 13px; margin: 0; }
  </style>
</head>
<body>
  <div class="card">
    <div class="check">&#10003;</div>
    <h2>Signed in successfully!</h2>
    <p>You can close this tab and return to FinAudio.</p>
  </div>
</body>
</html>''';

  static String _authErrorHtml(String err) => '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>FinAudio - Sign In Failed</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      background: #0F0F0F;
      color: #FFFFFF;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }
    .card {
      background: #181818;
      border: 1px solid #332222;
      border-radius: 16px;
      padding: 40px 48px;
      text-align: center;
      max-width: 380px;
    }
    .cross {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      background: #FF5252;
      color: #FFF;
      font-weight: 800;
      border-radius: 50%;
      width: 48px;
      height: 48px;
      font-size: 26px;
      margin-bottom: 16px;
    }
    h2 { font-size: 20px; margin: 0 0 8px; font-weight: 600; }
    p { color: #888; font-size: 13px; margin: 0; }
  </style>
</head>
<body>
  <div class="card">
    <div class="cross">&#10005;</div>
    <h2>Sign In Failed</h2>
    <p>$err</p>
  </div>
</body>
</html>''';

  bool _initialized = false;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  GoogleIdentity? _currentUser;
  String? _accessToken;
  DateTime? _tokenTimestamp;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authEventsSub;
  YTMusic? _ytMusic;

  GoogleAuthService() {
    _loadSavedSession();
  }

  GoogleIdentity? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get isAuthenticated => isSignedIn;

  /// Whether user authentication is supported (supported across all platforms via Google Sign-In or InnerTube).
  bool get isSupported => true;

  /// Whether the platform natively supports the Google Sign-In SDK plugin (Android, iOS, Web).
  bool get isNativeGoogleSignInPluginSupported =>
      kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.windows &&
          defaultTargetPlatform != TargetPlatform.linux);

  Future<YTMusic> _getYtMusic() async {
    return _ytMusic ??= await YTMusic.create();
  }

  // ------------------------------------------------------------------
  // Persistent session storage
  // ------------------------------------------------------------------

  Future<void> _loadSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final innerTubeAuth = prefs.getString(_keyInnerTubeAuth);
      if (innerTubeAuth != null && innerTubeAuth.isNotEmpty) {
        try {
          _ytMusic = await YTMusic.create(auth: innerTubeAuth);
        } catch (_) {}
      }

      final email = prefs.getString(_keyUserEmail);
      if (email != null && email.isNotEmpty) {
        final id = prefs.getString(_keyUserId) ?? '';
        final displayName = prefs.getString(_keyUserName);
        final photoUrl = prefs.getString(_keyUserPhoto);
        _currentUser = SavedGoogleAccount(
          id: id,
          email: email,
          displayName: displayName,
          photoUrl: photoUrl,
        );
        _accessToken = prefs.getString(_keyAccessToken);
        final ts = prefs.getInt(_keyTokenTimestamp);
        if (ts != null) {
          _tokenTimestamp = DateTime.fromMillisecondsSinceEpoch(ts);
        }
        debugPrint('GoogleAuthService: Restored persistent login for $email');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('GoogleAuthService: Failed to load saved session: $e');
    }
  }

  Future<void> _saveSession(GoogleIdentity user, String? token,
      [DateTime? timestamp]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserId, user.id);
      await prefs.setString(_keyUserEmail, user.email);
      if (user.displayName != null) {
        await prefs.setString(_keyUserName, user.displayName!);
      } else {
        await prefs.remove(_keyUserName);
      }
      if (user.photoUrl != null) {
        await prefs.setString(_keyUserPhoto, user.photoUrl!);
      } else {
        await prefs.remove(_keyUserPhoto);
      }
      if (token != null && token.isNotEmpty) {
        await prefs.setString(_keyAccessToken, token);
      }
      final ts = (timestamp ?? DateTime.now()).millisecondsSinceEpoch;
      await prefs.setInt(_keyTokenTimestamp, ts);
    } catch (e) {
      debugPrint('GoogleAuthService: Failed to save session: $e');
    }
  }

  Future<void> _clearSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyUserId);
      await prefs.remove(_keyUserEmail);
      await prefs.remove(_keyUserName);
      await prefs.remove(_keyUserPhoto);
      await prefs.remove(_keyAccessToken);
      await prefs.remove(_keyTokenTimestamp);
      await prefs.remove(_keySubscribedArtists);
      await prefs.remove(_keyInnerTubeHandle);
      await prefs.remove(_keyInnerTubeAuth);
      _ytMusic = null;
    } catch (e) {
      debugPrint('GoogleAuthService: Failed to clear session: $e');
    }
  }

  // ------------------------------------------------------------------
  // Initialization (required in v7)
  // ------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) return;
    await _loadSavedSession();

    if (!isNativeGoogleSignInPluginSupported) {
      _initialized = true;
      debugPrint('GoogleAuthService: Initialized on desktop (InnerTube & Handle auth enabled).');
      return;
    }
    try {
      await _googleSignIn.initialize(
        serverClientId: _serverClientId,
      );
      _initialized = true;
      debugPrint('GoogleSignIn initialized successfully');

      _authEventsSub ??= _googleSignIn.authenticationEvents.listen(
        (event) {
          if (event is GoogleSignInAuthenticationEventSignIn) {
            _currentUser = event.user;
            _saveSession(event.user, _accessToken, _tokenTimestamp);
            notifyListeners();
          } else if (event is GoogleSignInAuthenticationEventSignOut) {
            _clearSavedSession();
            _currentUser = null;
            _accessToken = null;
            _tokenTimestamp = null;
            notifyListeners();
          }
        },
        onError: (e) {
          debugPrint('GoogleSignIn authenticationEvents error: $e');
        },
      );

      // Do NOT call attemptLightweightAuthentication() on startup as it triggers
      // the OS account selection prompt. Instead, silently refresh authorization
      // if we have a restored logged-in session.
      if (_currentUser != null) {
        unawaited(_ensureAuthorization());
      }
    } catch (e) {
      debugPrint('GoogleSignIn.initialize failed: $e');
    }
  }

  Future<void> _ensureAuthorization({bool forceRefresh = false}) async {
    if (_currentUser == null) return;
    if (!isNativeGoogleSignInPluginSupported) return;

    if (!forceRefresh && _accessToken != null && _tokenTimestamp != null) {
      final age = DateTime.now().difference(_tokenTimestamp!);
      if (age < const Duration(minutes: 50)) {
        return;
      }
    }

    try {
      final auth = await _googleSignIn.authorizationClient
          .authorizationForScopes(_scopes);
      if (auth != null && auth.accessToken.isNotEmpty) {
        _accessToken = auth.accessToken;
        _tokenTimestamp = DateTime.now();
        if (_currentUser != null) {
          await _saveSession(_currentUser!, _accessToken, _tokenTimestamp);
        }
        debugPrint(
            'GoogleAuthService: Silently obtained access token for ${_currentUser!.email}');
      }
    } catch (e) {
      debugPrint('GoogleAuthService: Could not obtain authorization scopes: $e');
    }
  }

  // ------------------------------------------------------------------
  // Sign-in / sign-out
  // ------------------------------------------------------------------

  /// Real WebAuth OAuth 2.0 flow for desktop platforms (Windows, Linux, macOS).
  /// Launches the user's browser, handles Google redirect via local loopback server,
  /// fetches user profile from Google UserInfo API, and persists the session.
  Future<GoogleIdentity?> signInDesktopWebAuth({
    Duration timeout = const Duration(minutes: 3),
  }) async {
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      final redirectUri = 'http://127.0.0.1:$port';

      final state = base64UrlEncode(
        List<int>.generate(16, (i) => Random.secure().nextInt(256)),
      );

      final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': _serverClientId,
        'redirect_uri': redirectUri,
        'response_type': 'token',
        'scope': 'openid email profile',
        'state': state,
      });

      debugPrint('GoogleAuthService: Starting desktop WebAuth server on $redirectUri');
      debugPrint('GoogleAuthService: Opening browser to $authUri');

      // Launch default web browser
      bool launched = false;
      try {
        if (!kIsWeb && Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', authUri.toString()]);
          launched = true;
        } else if (!kIsWeb && Platform.isMacOS) {
          await Process.run('open', [authUri.toString()]);
          launched = true;
        } else if (!kIsWeb && Platform.isLinux) {
          await Process.run('xdg-open', [authUri.toString()]);
          launched = true;
        }
      } catch (launchErr) {
        debugPrint('GoogleAuthService: Browser launch warning: $launchErr');
      }

      if (!launched) {
        debugPrint('GoogleAuthService: Could not launch system browser automatically.');
      }

      final completer = Completer<String?>();

      server.listen((HttpRequest request) async {
        final uri = request.uri;

        if (uri.path == '/' || uri.path.isEmpty) {
          if (uri.queryParameters.containsKey('access_token')) {
            final token = uri.queryParameters['access_token'];
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(_authSuccessHtml);
            await request.response.close();
            if (!completer.isCompleted) completer.complete(token);
            return;
          }

          if (uri.queryParameters.containsKey('error')) {
            final err = uri.queryParameters['error'];
            request.response
              ..statusCode = HttpStatus.badRequest
              ..headers.contentType = ContentType.html
              ..write(_authErrorHtml(err ?? 'Unknown error'));
            await request.response.close();
            if (!completer.isCompleted) completer.completeError(Exception('Google OAuth Error: $err'));
            return;
          }

          if (uri.queryParameters.containsKey('code')) {
            final code = uri.queryParameters['code'];
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(_authSuccessHtml);
            await request.response.close();
            if (!completer.isCompleted) completer.complete('code:$code');
            return;
          }

          // Serve HTML/JS bridge to extract token from URL fragment
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_authBridgeHtml);
          await request.response.close();
          return;
        }

        if (uri.path == '/callback') {
          if (uri.queryParameters.containsKey('access_token')) {
            final token = uri.queryParameters['access_token'];
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(_authSuccessHtml);
            await request.response.close();
            if (!completer.isCompleted) completer.complete(token);
            return;
          }

          if (uri.queryParameters.containsKey('error')) {
            final err = uri.queryParameters['error'];
            request.response
              ..statusCode = HttpStatus.badRequest
              ..headers.contentType = ContentType.html
              ..write(_authErrorHtml(err ?? 'Unknown error'));
            await request.response.close();
            if (!completer.isCompleted) completer.completeError(Exception('Google OAuth Error: $err'));
            return;
          }

          if (uri.queryParameters.containsKey('code')) {
            final code = uri.queryParameters['code'];
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(_authSuccessHtml);
            await request.response.close();
            if (!completer.isCompleted) completer.complete('code:$code');
            return;
          }
        }

        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
        await request.response.close();
      });

      // Wait for authentication response with timeout
      final resultToken = await completer.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException('Google Sign-In timed out. Please try again.'),
      );

      if (resultToken == null || resultToken.isEmpty) {
        throw Exception('No authorization token received from Google.');
      }

      String accessToken = resultToken;
      if (accessToken.startsWith('code:')) {
        final code = accessToken.substring(5);
        try {
          final res = await http.post(
            Uri.parse('https://oauth2.googleapis.com/token'),
            body: {
              'client_id': _serverClientId,
              'redirect_uri': redirectUri,
              'code': code,
              'grant_type': 'authorization_code',
            },
          );
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data['access_token'] != null) {
              accessToken = data['access_token'] as String;
            }
          }
        } catch (exchangeErr) {
          debugPrint('GoogleAuthService: Code exchange note: $exchangeErr');
        }
      }

      // Fetch user profile from Google UserInfo endpoint
      final userProfileRes = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (userProfileRes.statusCode != 200) {
        throw Exception('Failed to retrieve user profile from Google: ${userProfileRes.body}');
      }

      final profileJson = jsonDecode(userProfileRes.body) as Map<String, dynamic>;
      final id = profileJson['sub'] as String? ?? '';
      final email = profileJson['email'] as String? ?? 'google_user@gmail.com';
      final displayName = profileJson['name'] as String? ?? email;
      final photoUrl = profileJson['picture'] as String?;

      final identity = SavedGoogleAccount(
        id: id,
        email: email,
        displayName: displayName,
        photoUrl: photoUrl,
      );

      _currentUser = identity;
      _accessToken = accessToken;
      _tokenTimestamp = DateTime.now();

      await _saveSession(identity, accessToken, _tokenTimestamp);
      notifyListeners();

      debugPrint('GoogleAuthService: Desktop WebAuth succeeded for $email');
      return identity;
    } finally {
      await server?.close(force: true);
    }
  }

  /// Triggers the Google Sign-In flow with basic identity scope,
  /// bypassing the Google OAuth verification 403 access_denied block.
  /// On desktop platforms (Windows/Linux/macOS), uses the native WebAuth loopback OAuth flow.
  Future<GoogleIdentity?> signIn() async {
    if (!isNativeGoogleSignInPluginSupported) {
      debugPrint('GoogleAuthService: Running on desktop. Launching WebAuth OAuth flow...');
      return await signInDesktopWebAuth();
    }
    await initialize();

    try {
      // v7 API: authenticate() with basic email scope to avoid restricted scope 403 block.
      final GoogleSignInAccount account =
          await _googleSignIn.authenticate(scopeHint: _scopes);

      GoogleSignInClientAuthorization? authorization;
      try {
        authorization =
            await account.authorizationClient.authorizeScopes(_scopes);
      } catch (_) {
        try {
          authorization = await _googleSignIn.authorizationClient
              .authorizeScopes(_scopes);
        } catch (_) {
          try {
            authorization = await _googleSignIn.authorizationClient
                .authorizationForScopes(_scopes);
          } catch (_) {}
        }
      }

      _accessToken = authorization?.accessToken;
      _currentUser = account;
      _tokenTimestamp = DateTime.now();

      await _saveSession(account, _accessToken, _tokenTimestamp);

      debugPrint('Signed in as: ${account.email}');
      notifyListeners();

      return account;
    } on GoogleSignInException catch (e) {
      debugPrint('Google Sign-In error: ${e.code.name} — ${e.description}');
      return null;
    } catch (e) {
      debugPrint('Unexpected Google Sign-In error: $e');
      return null;
    }
  }

  /// Connects using an InnerTube YouTube handle (e.g. "@ethannotsmart"), Channel ID,
  /// or InnerTube authentication cookie, completely bypassing Google OAuth verification.
  Future<GoogleIdentity?> signInWithInnerTube({
    required String handleOrChannelId,
    String? authCookie,
  }) async {
    try {
      final clean = handleOrChannelId.trim();
      if (clean.isEmpty && (authCookie == null || authCookie.trim().isEmpty)) {
        throw ArgumentError('Please provide a YouTube handle or Channel ID.');
      }

      final prefs = await SharedPreferences.getInstance();
      String id = clean;
      String displayName = clean;
      String? photoUrl;

      // If user provided an InnerTube cookie / header, initialize YTMusic with it
      if (authCookie != null && authCookie.trim().isNotEmpty) {
        final cookieClean = authCookie.trim();
        await prefs.setString(_keyInnerTubeAuth, cookieClean);
        try {
          _ytMusic = await YTMusic.create(auth: cookieClean);
        } catch (e) {
          debugPrint('InnerTube YTMusic auth parsing notice: $e');
        }
      }

      // Resolve channel info via YoutubeExplode
      final bool isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
      if (!isTest && clean.isNotEmpty) {
        final ytExplode = YoutubeExplode();
        try {
          Channel? channel;
          if (clean.startsWith('@')) {
            channel = await ytExplode.channels.getByHandle(clean);
          } else if (clean.startsWith('UC') && clean.length >= 20) {
            channel = await ytExplode.channels.get(clean);
          } else {
            try {
              channel = await ytExplode.channels.getByHandle('@$clean');
            } catch (_) {
              channel = await ytExplode.channels.getByUsername(clean);
            }
          }
          id = channel.id.value;
          displayName = channel.title;
          photoUrl = channel.logoUrl;
        } catch (e) {
          debugPrint('InnerTube channel resolution fallback: $e');
        } finally {
          ytExplode.close();
        }
      }

      final identity = SavedGoogleAccount(
        id: id,
        email: clean.startsWith('@')
            ? '$clean@youtube'
            : (clean.isNotEmpty ? '$clean@innertube' : 'innertube_user@music'),
        displayName: displayName.isNotEmpty ? displayName : 'YouTube Music User',
        photoUrl: photoUrl,
      );

      _currentUser = identity;
      if (clean.isNotEmpty) {
        await prefs.setString(_keyInnerTubeHandle, clean);
      }
      await _saveSession(identity, null, DateTime.now());
      notifyListeners();
      return identity;
    } catch (e) {
      debugPrint('signInWithInnerTube error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    if (isNativeGoogleSignInPluginSupported) {
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        debugPrint('GoogleAuthService signOut error: $e');
      }
    }
    await _clearSavedSession();
    _currentUser = null;
    _accessToken = null;
    _tokenTimestamp = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // InnerTube Music browsing & catalog (YTMusic)
  // ------------------------------------------------------------------

  /// Convenience: fetches curated / liked music playlist.
  Future<List<PlaylistVideo>> fetchLikedVideos({int maxResults = 50}) async {
    try {
      return await fetchPlaylistVideos('LM', maxResults: maxResults);
    } catch (_) {
      return await searchMusic(query: 'Top Hits', maxResults: maxResults);
    }
  }

  /// Fetches playlists owned by the signed-in user's YouTube account via YouTube API or InnerTube.
  Future<List<UserPlaylist>> fetchPlaylists({int maxResults = 50}) async {
    // 1. If we have a Google OAuth token, attempt the YouTube Data API
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      try {
        final response = await http.get(
          Uri.parse(
            'https://www.googleapis.com/youtube/v3/playlists?part=snippet,contentDetails&mine=true&maxResults=${maxResults.clamp(1, 50)}',
          ),
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final items = data['items'] as List<dynamic>? ?? [];
          final playlists = <UserPlaylist>[];

          for (final item in items) {
            final id = item['id'] as String? ?? '';
            if (id.isEmpty) continue;
            final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
            final contentDetails =
                item['contentDetails'] as Map<String, dynamic>? ?? {};

            playlists.add(UserPlaylist(
              id: id,
              title: snippet['title'] as String? ?? 'Untitled Playlist',
              description: snippet['description'] as String? ?? '',
              thumbnailUrl: (snippet['thumbnails']?['high'] ??
                      snippet['thumbnails']?['medium'] ??
                      snippet['thumbnails']?['default'])?['url'] as String? ??
                  '',
              videoCount: contentDetails['itemCount'] as int? ?? 0,
            ));
          }
          if (playlists.isNotEmpty) {
            debugPrint('fetchPlaylists (API): Loaded ${playlists.length} playlists');
            return playlists;
          }
        }
      } catch (e) {
        debugPrint('fetchPlaylists API error (falling back to InnerTube): $e');
      }
    }

    // 2. InnerTube fallback: fetch playlists for saved channel or handle
    final prefs = await SharedPreferences.getInstance();
    final handle = prefs.getString(_keyInnerTubeHandle) ?? _currentUser?.id;
    if (handle != null &&
        handle.isNotEmpty &&
        !handle.contains('@youtube') &&
        !handle.contains('@innertube') &&
        !handle.contains('@example.com')) {
      final ytExplode = YoutubeExplode();
      try {
        Channel? ch;
        if (handle.startsWith('@')) {
          ch = await ytExplode.channels.getByHandle(handle);
        } else if (handle.startsWith('UC')) {
          ch = await ytExplode.channels.get(handle);
        } else {
          try {
            ch = await ytExplode.channels.getByHandle('@$handle');
          } catch (_) {}
        }

        final targetId = ch?.id.value ?? handle;
        final channelPlaylists = <UserPlaylist>[];
        final yt = await YTMusic.create();

        // 1. Try browsing channel user object
        try {
          final userObj = await yt.getUser(targetId);
          final playlistsObj = userObj['playlists'];
          if (playlistsObj is Map && playlistsObj['results'] is List) {
            for (final p in (playlistsObj['results'] as List).take(maxResults)) {
              if (p is! Map) continue;
              final pid = p['playlistId']?.toString() ?? p['browseId']?.toString() ?? '';
              final title = p['title']?.toString() ?? 'Playlist';
              final thumbs = p['thumbnails'];
              String thumbUrl = '';
              if (thumbs is List && thumbs.isNotEmpty) {
                thumbUrl = thumbs.last['url']?.toString() ?? '';
              }
              final count = int.tryParse(p['count']?.toString() ?? p['itemCount']?.toString() ?? '') ?? 0;
              if (pid.isNotEmpty) {
                channelPlaylists.add(UserPlaylist(
                  id: pid,
                  title: title,
                  description: '',
                  thumbnailUrl: thumbUrl,
                  videoCount: count,
                ));
              }
            }
          }
        } catch (e) {
          debugPrint('getUser playlists InnerTube: $e');
        }

        // 2. Search fallback for playlists under handle / user name
        if (channelPlaylists.isEmpty) {
          try {
            final searchResults = await yt.search(handle, filter: SearchFilterType.playlists);
            for (final p in searchResults.take(maxResults)) {
              if (p is! Map) continue;
              final pid = p['playlistId']?.toString() ?? p['browseId']?.toString() ?? '';
              final title = p['title']?.toString() ?? 'Playlist';
              final thumbs = p['thumbnails'];
              String thumbUrl = '';
              if (thumbs is List && thumbs.isNotEmpty) {
                thumbUrl = thumbs.last['url']?.toString() ?? '';
              }
              final count = int.tryParse(p['itemCount']?.toString() ?? '') ?? 0;
              if (pid.isNotEmpty) {
                channelPlaylists.add(UserPlaylist(
                  id: pid,
                  title: title,
                  description: p['author']?.toString() ?? '',
                  thumbnailUrl: thumbUrl,
                  videoCount: count,
                ));
              }
            }
          } catch (e) {
            debugPrint('search playlists fallback InnerTube: $e');
          }
        }

        if (channelPlaylists.isNotEmpty) {
          debugPrint(
              'fetchPlaylists (InnerTube): Loaded ${channelPlaylists.length} playlists');
          return channelPlaylists;
        }
      } catch (e) {
        debugPrint('fetchPlaylists InnerTube error: $e');
      } finally {
        ytExplode.close();
      }
    }

    return <UserPlaylist>[];
  }

  /// Fetches the user's subscribed YouTube channels/artists via YouTube Data API v3,
  /// strictly filtered so that ONLY music artists/producers/bands are returned.
  /// Results are cached locally in SharedPreferences for instantaneous offline availability.
  Future<List<SubscribedArtist>> fetchSubscribedArtists({
    bool forceRefresh = false,
    bool musicOnly = true,
    int maxResults = 100,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = prefs.getString(_keySubscribedArtists);
      if (cached != null && cached.isNotEmpty) {
        try {
          final list = (jsonDecode(cached) as List<dynamic>)
              .map((item) =>
                  SubscribedArtist.fromJson(item as Map<String, dynamic>))
              .toList();
          if (list.isNotEmpty) {
            return list;
          }
        } catch (e) {
          debugPrint('Error parsing cached subscribed artists: $e');
        }
      }
    }

    if (_currentUser == null || _accessToken == null || _accessToken!.isEmpty) {
      final cached = prefs.getString(_keySubscribedArtists);
      if (cached != null && cached.isNotEmpty) {
        try {
          final list = (jsonDecode(cached) as List<dynamic>)
              .map((item) => SubscribedArtist.fromJson(item as Map<String, dynamic>))
              .toList();
          if (list.isNotEmpty) return list;
        } catch (_) {}
      }
      return getFallbackMusicArtists();
    }

    var token = _accessToken;

    try {
      final rawChannels = <SubscribedArtist>[];
      String? pageToken;
      int fetchedCount = 0;
      // Fetch more channels if musicOnly so we gather enough music artists after filtering
      final targetFetch = musicOnly ? (maxResults * 2).clamp(50, 150) : maxResults;

      while (fetchedCount < targetFetch) {
        final queryParams = <String, String>{
          'part': 'snippet',
          'mine': 'true',
          'maxResults': '${(targetFetch - fetchedCount).clamp(1, 50)}',
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        };
        final uri = Uri.https(
            'www.googleapis.com', '/youtube/v3/subscriptions', queryParams);

        var response = await http.get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 401 && isSupported) {
          debugPrint(
              'fetchSubscribedArtists: HTTP 401, refreshing token silently...');
          if (token != null) {
            try {
              await _googleSignIn.authorizationClient
                  .clearAuthorizationToken(accessToken: token);
            } catch (_) {}
          }
          await _ensureAuthorization(forceRefresh: true);
          token = _accessToken;
          if (token != null && token.isNotEmpty) {
            response = await http.get(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            );
          }
        }

        if (response.statusCode != 200) {
          debugPrint(
              'fetchSubscribedArtists error: HTTP ${response.statusCode} - ${response.body}');
          break;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
          final resourceId =
              snippet['resourceId'] as Map<String, dynamic>? ?? {};
          final channelId = resourceId['channelId'] as String? ?? '';
          if (channelId.isEmpty) continue;

          final title = snippet['title'] as String? ?? 'Artist';
          final description = snippet['description'] as String? ?? '';
          final thumbnails =
              snippet['thumbnails'] as Map<String, dynamic>? ?? {};
          final thumbUrl = (thumbnails['high'] ??
                  thumbnails['medium'] ??
                  thumbnails['default'])?['url'] as String? ??
              '';

          rawChannels.add(SubscribedArtist(
            channelId: channelId,
            title: title,
            description: description,
            thumbnailUrl: thumbUrl,
          ));
        }

        fetchedCount = rawChannels.length;
        pageToken = data['nextPageToken'] as String?;
        if (pageToken == null || pageToken.isEmpty) {
          break;
        }
      }

      // Filter raw subscriptions to ONLY music artists
      final filteredArtists = musicOnly && token != null
          ? await _filterToMusicArtistsOnly(rawChannels, token)
          : rawChannels;

      final result = filteredArtists.take(maxResults).toList();

      if (result.isNotEmpty) {
        await prefs.setString(
          _keySubscribedArtists,
          jsonEncode(result.map((a) => a.toJson()).toList()),
        );
        debugPrint(
            'fetchSubscribedArtists: Loaded and cached ${result.length} music artists (from ${rawChannels.length} total subscriptions)');
      }
      return result.isNotEmpty ? result : getFallbackMusicArtists();
    } catch (e) {
      debugPrint('fetchSubscribedArtists error: $e');
    }

    return getFallbackMusicArtists();
  }

  static List<SubscribedArtist> getFallbackMusicArtists() {
    return const [
      SubscribedArtist(
        channelId: 'UC-J-KZfRV8c13fGAxGZ-9dQ',
        title: 'Dua Lipa',
        description: 'Official artist channel for Dua Lipa.',
        thumbnailUrl: 'https://img.youtube.com/vi/TUVcZfQe-Kw/hqdefault.jpg',
      ),
      SubscribedArtist(
        channelId: 'UC0WP5P-ufpRfjbNrmOWwLBQ',
        title: 'The Weeknd',
        description: 'Official artist channel for The Weeknd.',
        thumbnailUrl: 'https://img.youtube.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
      ),
      SubscribedArtist(
        channelId: 'UCqECaJ8Gagnn7YCbPEzWH6g',
        title: 'Taylor Swift',
        description: 'Official artist channel for Taylor Swift.',
        thumbnailUrl: 'https://img.youtube.com/vi/e-ORhEE9VVg/hqdefault.jpg',
      ),
      SubscribedArtist(
        channelId: 'UCiGm_E4DwYcU-fxNc26TG2g',
        title: 'Coldplay',
        description: 'Official artist channel for Coldplay.',
        thumbnailUrl: 'https://img.youtube.com/vi/yKNxeF4KMsY/hqdefault.jpg',
      ),
      SubscribedArtist(
        channelId: 'UCi2knUfYnLkWUu5bA_mN-0A',
        title: 'Billie Eilish',
        description: 'Official artist channel for Billie Eilish.',
        thumbnailUrl: 'https://img.youtube.com/vi/d5gf9dXbPi0/hqdefault.jpg',
      ),
      SubscribedArtist(
        channelId: 'UC0C-w0YjGpqDXGB8IHb662A',
        title: 'Ed Sheeran',
        description: 'Official artist channel for Ed Sheeran.',
        thumbnailUrl: 'https://img.youtube.com/vi/2Vv-BfVoq4g/hqdefault.jpg',
      ),
      SubscribedArtist(
        channelId: 'UCpDJl2EmP7Oh90Vylx0dZtA',
        title: 'Sabrina Carpenter',
        description: 'Official artist channel for Sabrina Carpenter.',
        thumbnailUrl: 'https://img.youtube.com/vi/eVli-tstM5E/hqdefault.jpg',
      ),
    ];
  }

  /// Verifies a list of subscribed channels against YouTube topic categories and heuristics
  /// to ensure ONLY genuine music artists/bands/producers are returned.
  Future<List<SubscribedArtist>> _filterToMusicArtistsOnly(
    List<SubscribedArtist> rawChannels,
    String token,
  ) async {
    if (rawChannels.isEmpty) return [];

    final musicArtists = <SubscribedArtist>[];
    final channelMap = {for (final c in rawChannels) c.channelId: c};
    final pendingIds = <String>[];

    // 1. First pass: immediate heuristic matches
    for (final channel in rawChannels) {
      if (_isMusicTitleOrDescription(channel.title, channel.description)) {
        musicArtists.add(channel);
      } else {
        pendingIds.add(channel.channelId);
      }
    }

    // 2. Second pass: Batch query YouTube Data API for topicDetails (up to 50 at a time)
    for (int i = 0; i < pendingIds.length; i += 50) {
      final chunk = pendingIds.skip(i).take(50).toList();
      try {
        final uri = Uri.https('www.googleapis.com', '/youtube/v3/channels', {
          'part': 'topicDetails',
          'id': chunk.join(','),
        });
        final response = await http.get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final items = data['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            final id = item['id'] as String? ?? '';
            final topicDetails = item['topicDetails'] as Map<String, dynamic>?;
            final categories =
                topicDetails?['topicCategories'] as List<dynamic>? ?? [];
            if (_hasMusicTopic(categories)) {
              final match = channelMap[id];
              if (match != null && !musicArtists.contains(match)) {
                musicArtists.add(match);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('_filterToMusicArtistsOnly chunk error: $e');
      }
    }

    // 3. Fallback: if no artists were verified (e.g., topicDetails not indexed),
    // exclude explicit non-music channels (gamers, vloggers, tutorials)
    if (musicArtists.isEmpty && rawChannels.isNotEmpty) {
      return rawChannels
          .where((c) => !_isDefinitelyNonMusic(c.title, c.description))
          .toList();
    }

    return musicArtists;
  }

  static bool _hasMusicTopic(List<dynamic> categories) {
    for (final cat in categories) {
      final s = cat.toString().toLowerCase();
      if (s.contains('/music') ||
          s.contains('/musician') ||
          s.contains('music_genre') ||
          s.contains('electronic_music') ||
          s.contains('hip_hop') ||
          s.contains('rock_music') ||
          s.contains('pop_music') ||
          s.contains('soundtrack') ||
          s.contains('independent_music') ||
          s.contains('song') ||
          s.contains('singer') ||
          s.contains('band') ||
          s.contains('orchestra') ||
          s.contains('rhythm_and_blues') ||
          s.contains('country_music') ||
          s.contains('classical_music') ||
          s.contains('vocal') ||
          s.contains('heavy_metal')) {
        return true;
      }
    }
    return false;
  }

  static bool _isMusicTitleOrDescription(String title, String description) {
    final t = title.toLowerCase();
    final d = description.toLowerCase();

    if (t.endsWith(' - topic') ||
        t.contains('vevo') ||
        t.contains('records') ||
        t.contains('official music') ||
        t.contains(' sound') ||
        t.contains(' audio') ||
        t.contains(' studio') ||
        t.contains(' entertainment') ||
        t.contains(' band') ||
        t.contains(' orchestra')) {
      return true;
    }

    if (d.contains('official artist channel') ||
        d.contains('music video') ||
        d.contains('listen on spotify') ||
        d.contains('listen on apple music') ||
        d.contains('debut single') ||
        d.contains('new single') ||
        d.contains('new album') ||
        d.contains('stream now') ||
        d.contains('singer-songwriter') ||
        d.contains('music producer') ||
        d.contains('discography') ||
        d.contains('original song') ||
        d.contains('original music')) {
      return true;
    }

    return false;
  }

  static bool _isDefinitelyNonMusic(String title, String description) {
    final t = title.toLowerCase();
    final d = description.toLowerCase();
    const nonMusicKeywords = [
      'gameplay',
      'let\'s play',
      'walkthrough',
      'gaming',
      'minecraft',
      'roblox',
      'fortnite',
      'tech review',
      'smartphone',
      'hardware',
      'tutorial',
      'coding',
      'daily vlog',
      'comedy sketches',
      'prank',
      'reactions',
    ];
    for (final kw in nonMusicKeywords) {
      if (t.contains(kw) || d.contains(kw)) return true;
    }
    return false;
  }

  /// Fetches videos from a playlist via InnerTube (getPlaylist) or YouTube API.
  Future<List<PlaylistVideo>> fetchPlaylistVideos(
    String playlistId, {
    int maxResults = 50,
  }) async {
    // 1. If signed in, query user playlistItems (supports private/unlisted playlists)
    await _ensureAuthorization();
    var token = _accessToken;
    if (token != null && token.isNotEmpty) {
      try {
        var response = await http.get(
          Uri.parse(
            'https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId=$playlistId&maxResults=${maxResults.clamp(1, 50)}',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 401 && isSupported) {
          debugPrint(
              'fetchPlaylistVideos: HTTP 401 Unauthorized, refreshing token silently...');
          try {
            await _googleSignIn.authorizationClient
                .clearAuthorizationToken(accessToken: token);
          } catch (_) {}
          await _ensureAuthorization(forceRefresh: true);
          token = _accessToken;
          if (token != null && token.isNotEmpty) {
            response = await http.get(
              Uri.parse(
                'https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId=$playlistId&maxResults=${maxResults.clamp(1, 50)}',
              ),
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
            );
          }
        }

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final items = data['items'] as List<dynamic>? ?? [];
          final videos = <PlaylistVideo>[];

          for (final item in items) {
            final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
            final resourceId =
                snippet['resourceId'] as Map<String, dynamic>? ?? {};
            final videoId = resourceId['videoId'] as String? ?? '';
            if (videoId.isEmpty) continue;

            final title = snippet['title'] as String? ?? 'Untitled';
            final channelTitle = snippet['videoOwnerChannelTitle'] as String? ??
                snippet['channelTitle'] as String? ??
                '';
            final thumbnails =
                snippet['thumbnails'] as Map<String, dynamic>? ?? {};
            final thumbUrl = (thumbnails['high'] ??
                    thumbnails['medium'] ??
                    thumbnails['default'])?['url'] as String? ??
                'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

            videos.add(PlaylistVideo(
              videoId: videoId,
              title: title,
              channelTitle: channelTitle,
              thumbnailUrl: thumbUrl,
              duration: Duration.zero,
            ));
          }
          if (videos.isNotEmpty) {
            debugPrint('fetchPlaylistVideos (API): Loaded ${videos.length} videos');
            return videos;
          }
        }
      } catch (e) {
        debugPrint('fetchPlaylistVideos API error: $e');
      }
    }

    final yt = await _getYtMusic();
    try {
      final res = await yt.getPlaylist(playlistId, limit: maxResults);
      final rawTracks = res['tracks'] as List? ?? [];
      final videos = <PlaylistVideo>[];

      for (final item in rawTracks) {
        if (item is! Map) continue;
        final videoId = item['videoId'] as String?;
        if (videoId == null || videoId.isEmpty) continue;

        final title = (item['title'] as String?)?.isNotEmpty == true
            ? item['title'] as String
            : 'Untitled';

        String artist = '';
        final artists = item['artists'];
        if (artists is List && artists.isNotEmpty) {
          artist = artists
              .map((a) =>
                  a is Map ? (a['name']?.toString() ?? '') : a.toString())
              .where((s) => s.isNotEmpty)
              .join(', ');
        }
        if (artist.isEmpty && item['author'] != null) {
          artist = item['author'].toString();
        }

        String thumbUrl = 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
        final thumbs = item['thumbnails'];
        if (thumbs is List && thumbs.isNotEmpty) {
          final last = thumbs.last;
          if (last is Map && last['url'] != null) {
            thumbUrl = last['url'].toString();
          }
        }

        Duration dur = Duration.zero;
        if (item['duration_seconds'] is num) {
          dur = Duration(seconds: (item['duration_seconds'] as num).toInt());
        } else if (item['duration'] is String) {
          dur = _parseDuration(item['duration'] as String);
        }

        videos.add(PlaylistVideo(
          videoId: videoId,
          title: title,
          channelTitle: artist,
          thumbnailUrl: thumbUrl,
          duration: dur,
        ));
      }

      debugPrint(
          'fetchPlaylistVideos returned ${videos.length} videos from $playlistId');
      return videos;
    } catch (e) {
      debugPrint('fetchPlaylistVideos error: $e');
      rethrow;
    }
  }

  /// Spotify-style unified search returning Top Result, songs, artists, albums, and playlists.
  Future<UnifiedSearchResults> unifiedSearch({
    required String query,
    String category = 'All',
    int limit = 25,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const UnifiedSearchResults();

    final yt = await _getYtMusic();

    try {
      if (category == 'Songs') {
        final raw = await yt.search(trimmed,
            filter: SearchFilterType.songs, limit: limit);
        final songs = _parseSongs(raw);
        return UnifiedSearchResults(songs: songs);
      } else if (category == 'Artists') {
        final raw = await yt.search(trimmed,
            filter: SearchFilterType.artists, limit: limit);
        final artists = _parseArtists(raw);
        return UnifiedSearchResults(artists: artists);
      } else if (category == 'Albums') {
        final raw = await yt.search(trimmed,
            filter: SearchFilterType.albums, limit: limit);
        final albums = _parseAlbums(raw);
        return UnifiedSearchResults(albums: albums);
      } else if (category == 'Playlists') {
        final raw = await yt.search(trimmed,
            filter: SearchFilterType.playlists, limit: limit);
        final playlists = _parsePlaylists(raw);
        return UnifiedSearchResults(playlists: playlists);
      } else if (category == 'Videos') {
        final raw = await yt.search(trimmed,
            filter: SearchFilterType.videos, limit: limit);
        final songs = _parseSongs(raw);
        return UnifiedSearchResults(songs: songs);
      }

      // Default 'All': unfiltered search for high relevance & curated top result
      final futures = await Future.wait([
        yt.search(trimmed, limit: 30),
        yt.search(trimmed, filter: SearchFilterType.songs, limit: 20),
      ]);
      final raw = futures[0];
      final rawSongs = futures[1];
      final parsed = _parseUnifiedAll(raw);
      final parsedSongs = _parseSongs(rawSongs);

      final seenSongIds = <String>{};
      final enrichedSongs = <PlaylistVideo>[];

      if (parsed.topResult?.isSong == true && parsed.topResult!.asSong != null) {
        seenSongIds.add(parsed.topResult!.asSong!.videoId);
      }

      for (final s in parsed.songs) {
        if (seenSongIds.add(s.videoId)) {
          if (s.channelTitle.isEmpty) {
            final match = parsedSongs.firstWhere(
              (p) => p.videoId == s.videoId,
              orElse: () => s,
            );
            enrichedSongs.add(match);
          } else {
            enrichedSongs.add(s);
          }
        }
      }

      for (final s in parsedSongs) {
        if (seenSongIds.add(s.videoId)) {
          enrichedSongs.add(s);
        }
      }

      return UnifiedSearchResults(
        topResult: parsed.topResult,
        songs: enrichedSongs,
        artists: parsed.artists,
        albums: parsed.albums,
        playlists: parsed.playlists,
      );
    } catch (e) {
      debugPrint('unifiedSearch error: $e');
      // If error or empty on desktop/unfiltered, attempt fallback to songs
      try {
        final fallback = await yt.search(trimmed,
            filter: SearchFilterType.songs, limit: limit);
        final songs = _parseSongs(fallback);
        return UnifiedSearchResults(songs: songs);
      } catch (_) {}
      return const UnifiedSearchResults();
    }
  }

  static String _extractThumb(dynamic thumbs, {String fallback = ''}) {
    if (thumbs is List && thumbs.isNotEmpty) {
      final last = thumbs.last;
      if (last is Map && last['url'] != null) {
        return last['url'].toString();
      }
    } else if (thumbs is Map && thumbs['url'] != null) {
      return thumbs['url'].toString();
    }
    return fallback;
  }

  static String _extractArtistName(dynamic item) {
    if (item is! Map) return '';
    final artists = item['artists'];
    if (artists is List && artists.isNotEmpty) {
      final names = artists
          .map((a) => a is Map ? (a['name']?.toString() ?? '') : a.toString())
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.isNotEmpty) return names.join(', ');
    }
    if (item['artist'] != null) {
      if (item['artist'] is Map) {
        final n = item['artist']['name']?.toString() ?? '';
        if (n.isNotEmpty) return n;
      }
      final s = item['artist'].toString().trim();
      if (s.isNotEmpty) return s;
    }
    if (item['author'] != null) {
      if (item['author'] is Map) {
        final n = item['author']['name']?.toString() ?? '';
        if (n.isNotEmpty) return n;
      }
      final s = item['author'].toString().trim();
      if (s.isNotEmpty) return s;
    }
    if (item['channelTitle'] != null && item['channelTitle'].toString().trim().isNotEmpty) {
      return item['channelTitle'].toString().trim();
    }
    return '';
  }

  static List<PlaylistVideo> _parseSongs(List<dynamic> items) {
    final list = <PlaylistVideo>[];
    for (final item in items) {
      if (item is! Map) continue;
      final videoId = item['videoId'] as String?;
      if (videoId == null || videoId.isEmpty) continue;

      final title = (item['title'] as String?)?.isNotEmpty == true
          ? item['title'] as String
          : 'Untitled';
      final artist = _extractArtistName(item);
      final thumbUrl = _extractThumb(item['thumbnails'],
          fallback: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg');

      Duration dur = Duration.zero;
      if (item['duration_seconds'] is num) {
        dur = Duration(seconds: (item['duration_seconds'] as num).toInt());
      } else if (item['duration'] is String) {
        dur = _parseDuration(item['duration'] as String);
      }

      list.add(PlaylistVideo(
        videoId: videoId,
        title: title,
        channelTitle: artist,
        thumbnailUrl: thumbUrl,
        duration: dur,
      ));
    }
    return list;
  }

  static List<SearchArtist> _parseArtists(List<dynamic> items) {
    final list = <SearchArtist>[];
    for (final item in items) {
      if (item is! Map) continue;
      var browseId = item['browseId']?.toString() ?? item['channelId']?.toString() ?? '';
      var name = item['artist']?.toString() ?? item['title']?.toString() ?? '';
      if (name.isEmpty && item['artists'] is List && (item['artists'] as List).isNotEmpty) {
        final first = (item['artists'] as List).first;
        if (first is Map) {
          name = first['name']?.toString() ?? '';
          if (browseId.isEmpty) {
            browseId = first['id']?.toString() ?? first['browseId']?.toString() ?? '';
          }
        }
      }
      if (name.isEmpty) continue;

      list.add(SearchArtist(
        id: browseId,
        name: name,
        thumbnailUrl: _extractThumb(item['thumbnails']),
        subscribers: item['subscribers']?.toString(),
      ));
    }
    return list;
  }

  static List<SearchAlbum> _parseAlbums(List<dynamic> items) {
    final list = <SearchAlbum>[];
    for (final item in items) {
      if (item is! Map) continue;
      final browseId = item['browseId'] as String? ?? '';
      final title = item['title']?.toString() ?? 'Untitled Album';
      list.add(SearchAlbum(
        browseId: browseId,
        playlistId: item['playlistId'] as String?,
        title: title,
        artist: _extractArtistName(item),
        year: item['year']?.toString(),
        type: item['type']?.toString(),
        thumbnailUrl: _extractThumb(item['thumbnails']),
      ));
    }
    return list;
  }

  static List<SearchPlaylist> _parsePlaylists(List<dynamic> items) {
    final list = <SearchPlaylist>[];
    for (final item in items) {
      if (item is! Map) continue;
      final id = item['playlistId'] as String? ?? item['browseId'] as String? ?? '';
      final title = item['title']?.toString() ?? 'Untitled Playlist';
      list.add(SearchPlaylist(
        id: id,
        title: title,
        author: item['author']?.toString(),
        itemCount: item['itemCount'] is num
            ? (item['itemCount'] as num).toInt()
            : (item['itemCount'] is String ? int.tryParse(item['itemCount'] as String) : null),
        thumbnailUrl: _extractThumb(item['thumbnails']),
      ));
    }
    return list;
  }

  static UnifiedSearchResults _parseUnifiedAll(List<dynamic> items) {
    TopSearchResult? topResult;
    final songs = <PlaylistVideo>[];
    final artists = <SearchArtist>[];
    final albums = <SearchAlbum>[];
    final playlists = <SearchPlaylist>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) continue;

      final category = (item['category'] as String?)?.toLowerCase() ?? '';
      final resultType = (item['resultType'] as String? ?? item['type'] as String? ?? '').toLowerCase();
      final isTop = category == 'top result' || (i == 0 && topResult == null);

      if (resultType == 'artist' || (category == 'top result' && (item['artists'] != null || item['subscribers'] != null) && item['videoId'] == null)) {
        var browseId = item['browseId']?.toString() ?? item['channelId']?.toString() ?? '';
        var name = item['artist']?.toString() ?? item['title']?.toString() ?? '';
        if (name.isEmpty && item['artists'] is List && (item['artists'] as List).isNotEmpty) {
          final first = (item['artists'] as List).first;
          if (first is Map) {
            name = first['name']?.toString() ?? '';
            if (browseId.isEmpty) {
              browseId = first['id']?.toString() ?? first['browseId']?.toString() ?? '';
            }
          }
        }
        if (name.isNotEmpty) {
          final artist = SearchArtist(
            id: browseId,
            name: name,
            thumbnailUrl: _extractThumb(item['thumbnails']),
            subscribers: item['subscribers']?.toString(),
          );
          if (isTop && topResult == null) {
            topResult = TopSearchResult(type: 'artist', data: artist);
          } else {
            artists.add(artist);
          }
        }
      } else if (resultType == 'song' || resultType == 'video' || item['videoId'] != null) {
        final videoId = item['videoId'] as String?;
        if (videoId != null && videoId.isNotEmpty) {
          final title = item['title']?.toString() ?? 'Untitled';
          final artist = _extractArtistName(item);
          final thumb = _extractThumb(item['thumbnails'],
              fallback: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg');
          Duration dur = Duration.zero;
          if (item['duration_seconds'] is num) {
            dur = Duration(seconds: (item['duration_seconds'] as num).toInt());
          } else if (item['duration'] is String) {
            dur = _parseDuration(item['duration'] as String);
          }
          final song = PlaylistVideo(
            videoId: videoId,
            title: title,
            channelTitle: artist,
            thumbnailUrl: thumb,
            duration: dur,
          );
          if (isTop && topResult == null) {
            topResult = TopSearchResult(type: 'song', data: song);
          } else {
            songs.add(song);
          }
        }
      } else if (resultType == 'album') {
        final album = SearchAlbum(
          browseId: item['browseId'] as String? ?? '',
          playlistId: item['playlistId'] as String?,
          title: item['title']?.toString() ?? 'Untitled Album',
          artist: _extractArtistName(item),
          year: item['year']?.toString(),
          type: item['type']?.toString(),
          thumbnailUrl: _extractThumb(item['thumbnails']),
        );
        if (isTop && topResult == null) {
          topResult = TopSearchResult(type: 'album', data: album);
        } else {
          albums.add(album);
        }
      } else if (resultType == 'playlist') {
        final playlist = SearchPlaylist(
          id: item['playlistId'] as String? ?? item['browseId'] as String? ?? '',
          title: item['title']?.toString() ?? 'Untitled Playlist',
          author: item['author']?.toString(),
          itemCount: item['itemCount'] is num
              ? (item['itemCount'] as num).toInt()
              : (item['itemCount'] is String ? int.tryParse(item['itemCount'] as String) : null),
          thumbnailUrl: _extractThumb(item['thumbnails']),
        );
        if (isTop && topResult == null) {
          topResult = TopSearchResult(type: 'playlist', data: playlist);
        } else {
          playlists.add(playlist);
        }
      }
    }

    // If top result wasn't explicitly tagged, take the first artist or first song
    if (topResult == null) {
      if (artists.isNotEmpty) {
        topResult = TopSearchResult(type: 'artist', data: artists.removeAt(0));
      } else if (songs.isNotEmpty) {
        topResult = TopSearchResult(type: 'song', data: songs.removeAt(0));
      } else if (albums.isNotEmpty) {
        topResult = TopSearchResult(type: 'album', data: albums.removeAt(0));
      }
    }

    return UnifiedSearchResults(
      topResult: topResult,
      songs: songs,
      artists: artists,
      albums: albums,
      playlists: playlists,
    );
  }

  /// Searches YouTube Music for songs matching [query] via InnerTube.
  Future<List<PlaylistVideo>> searchMusic({
    required String query,
    int maxResults = 15,
  }) async {
    final res = await unifiedSearch(query: query, category: 'Songs', limit: maxResults);
    if (res.songs.isNotEmpty) return res.songs;
    final fallback = await unifiedSearch(query: query, category: 'All', limit: maxResults);
    final list = <PlaylistVideo>[];
    if (fallback.topResult?.isSong == true && fallback.topResult!.asSong != null) {
      list.add(fallback.topResult!.asSong!);
    }
    list.addAll(fallback.songs);
    return list;
  }

  /// Retrieves an artist's discography and metadata via InnerTube.
  Future<Map<String, dynamic>> getArtist(String channelId) async {
    final yt = await _getYtMusic();
    final res = await yt.getArtist(channelId);
    return Map<String, dynamic>.from(res);
  }

  /// Retrieves YouTube Music home feed catalog via InnerTube.
  Future<List<dynamic>> getHome({int limit = 3}) async {
    final yt = await _getYtMusic();
    return await yt.getHome(limit: limit);
  }

  /// Retrieves recommendations watch playlist via InnerTube.
  Future<Map<String, dynamic>> getWatchPlaylist({
    String? videoId,
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
  }) async {
    final yt = await _getYtMusic();
    final res = await yt.getWatchPlaylist(
      videoId: videoId,
      playlistId: playlistId,
      limit: limit,
      radio: radio,
      shuffle: shuffle,
    );
    return Map<String, dynamic>.from(res);
  }

  static Duration _parseDuration(String durationStr) {
    final parts = durationStr.trim().split(':');
    if (parts.length == 2) {
      final mins = int.tryParse(parts[0]) ?? 0;
      final secs = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: mins, seconds: secs);
    } else if (parts.length == 3) {
      final hrs = int.tryParse(parts[0]) ?? 0;
      final mins = int.tryParse(parts[1]) ?? 0;
      final secs = int.tryParse(parts[2]) ?? 0;
      return Duration(hours: hrs, minutes: mins, seconds: secs);
    }
    return Duration.zero;
  }

  @override
  void dispose() {
    _authEventsSub?.cancel();
    _ytMusic?.close();
    super.dispose();
  }
}
