import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:finaudio/services/discord_rpc_service.dart';
import 'package:finaudio/services/settings_service.dart';

/// Shows a dialog or screen allowing the user to connect their Discord account for Mobile Rich Presence.
Future<bool?> showDiscordLoginDialog({
  required BuildContext context,
  required SettingsService settingsService,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => DiscordLoginDialog(settingsService: settingsService),
  );
}

/// Dialog allowing either automatic official Discord Web login or direct token entry.
class DiscordLoginDialog extends StatefulWidget {
  final SettingsService settingsService;

  const DiscordLoginDialog({super.key, required this.settingsService});

  @override
  State<DiscordLoginDialog> createState() => _DiscordLoginDialogState();
}

class _DiscordLoginDialogState extends State<DiscordLoginDialog> {
  final TextEditingController _tokenController = TextEditingController();
  bool _obscureText = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _showGuide = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _errorMessage = 'Please enter or paste your Discord token.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await DiscordRpcService.validateAndFetchUser(token);
      if (!mounted) return;

      if (user != null) {
        await widget.settingsService.setDiscordAccount(
          token: user.token,
          username: user.username,
          avatar: user.avatar,
          userId: user.id,
        );

        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Connected to Discord as @${user.username}!',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF5865F2), // Discord Blurple
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid token or authentication failed. Please check and try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Connection error: $e';
      });
    }
  }

  void _openWebLogin() {
    Navigator.of(context).pop(false);
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => DiscordWebViewScreen(settingsService: widget.settingsService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = widget.settingsService.surfaceColor;
    final textColor = widget.settingsService.textColor;
    const discordColor = Color(0xFF5865F2);

    final canUseWebView = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return Dialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
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
                        Text(
                          'Connect Discord',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Rich Presence Account Link',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: textColor.withValues(alpha: 0.5)),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Description
              Text(
                'Connect your Discord account to broadcast your currently playing songs, album artwork, and animated progress bar directly to your Discord profile in real-time.',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.8),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),

              // 1. One-Click Discord Web OAuth Login Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openWebLogin,
                  icon: const Icon(Icons.verified_user_rounded, size: 20),
                  label: Text(
                    canUseWebView ? 'Log in with Discord (Authorize)' : 'Log in via Discord Web',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: discordColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Opens the official Discord authorization prompt (just like ArchiveTune). Tap Authorize to link your account seamlessly.',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.55),
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: textColor.withValues(alpha: 0.12))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'OR ENTER TOKEN MANUALLY',
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: textColor.withValues(alpha: 0.12))),
                ],
              ),
              const SizedBox(height: 16),

              // Token Input Field
              Text(
                'Discord Account Token',
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tokenController,
                obscureText: _obscureText,
                style: TextStyle(color: textColor, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Paste your Discord token here...',
                  hintStyle: TextStyle(color: textColor.withValues(alpha: 0.35), fontSize: 13),
                  filled: true,
                  fillColor: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.6),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: textColor.withValues(alpha: 0.15)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: discordColor, width: 1.5),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: textColor.withValues(alpha: 0.5),
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureText = !_obscureText),
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // Collapsible Guide Button
              InkWell(
                onTap: () => setState(() => _showGuide = !_showGuide),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _showGuide ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        color: discordColor,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _showGuide ? 'Hide instructions' : 'How do I find my Discord token?',
                          style: const TextStyle(
                            color: discordColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Collapsible Step-by-Step Instructions
              if (_showGuide) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: discordColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: discordColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _guideStep('1', 'Open discord.com/app in your browser (Chrome/Kiwi/Firefox).'),
                      _guideStep('2', 'Press F12 (or open DevTools) and select Console.'),
                      _guideStep('3', 'Type or paste:'),
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: SelectableText(
                          "(webpackChunkdiscord_app.push([[''],{},e=>{m=[];for(let c in e.c)m.push(e.c[c])}]),m).find(m=>m?.exports?.default?.getToken!==void 0).exports.default.getToken()",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10.5,
                            color: Colors.lightGreenAccent.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      _guideStep('4', 'Copy the returned string without quotes and paste it above.'),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // Privacy Notice
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: textColor.withValues(alpha: 0.5), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Security Notice: Your token is stored encrypted exclusively on this device and communicates solely with official Discord Gateway servers.',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.55),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: textColor.withValues(alpha: 0.7),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _isLoading ? null : _handleConnect,
                    style: FilledButton.styleFrom(
                      backgroundColor: discordColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Connect',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number. ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF5865F2)),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: widget.settingsService.textColor.withValues(alpha: 0.75)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen in-app WebView for seamless official Discord login on Mobile.
class DiscordWebViewScreen extends StatefulWidget {
  final SettingsService settingsService;

  const DiscordWebViewScreen({super.key, required this.settingsService});

  /// Official Discord OAuth2 Authorize URL requesting Social SDK presence scopes.
  static String get oauthAuthorizeUrl {
    const appId = DiscordRpcService.defaultAppId;
    return 'https://discord.com/oauth2/authorize?client_id=$appId&response_type=token&scope=openid%20sdk.social_layer_presence&redirect_uri=https://localhost';
  }

  @override
  State<DiscordWebViewScreen> createState() => _DiscordWebViewScreenState();
}

class _DiscordWebViewScreenState extends State<DiscordWebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _isAuthorizing = false;
  Timer? _pollTimer;

  static const String _tokenExtractionScript = '''
    (function() {
      try {
        let token;
        window.webpackChunkdiscord_app.push([
          [Symbol()],
          {},
          (o) => {
            for (let e of Object.values(o.c)) {
              try {
                if (!e.exports || e.exports === window) continue;
                if (e.exports?.default?.getToken) { token = e.exports.default.getToken(); return; }
                if (e.exports?.getToken) { token = e.exports.getToken(); return; }
                for (let p in e.exports) {
                  if (e.exports?.[p]?.getToken && e.exports[p][Symbol.toStringTag] !== 'IntlMessagesProxy') {
                    token = e.exports[p].getToken();
                    return;
                  }
                }
              } catch(e) {}
            }
          },
        ]);
        window.webpackChunkdiscord_app.pop();
        if (token) return token;
      } catch(e) {}
      try {
        var t = window.localStorage.getItem('token');
        if (t && t.length > 20) return t.replace(/^"(.*)"\$/, '\$1');
      } catch(e) {}
      try {
        var f = document.createElement('iframe');
        document.body.appendChild(f);
        var t2 = f.contentWindow.localStorage.getItem('token');
        document.body.removeChild(f);
        if (t2 && t2.length > 20) return t2.replace(/^"(.*)"\$/, '\$1');
      } catch(e) {}
      return null;
    })()
  ''';

  String? _extractTokenFromUrl(String url) {
    if (!url.contains('access_token=')) return null;

    try {
      final uri = Uri.parse(url);
      if (uri.hasFragment && uri.fragment.isNotEmpty) {
        final fragmentParams = Uri.splitQueryString(uri.fragment);
        final token = fragmentParams['access_token'];
        if (token != null && token.isNotEmpty) return token;
      }
      if (uri.queryParameters.containsKey('access_token')) {
        final token = uri.queryParameters['access_token'];
        if (token != null && token.isNotEmpty) return token;
      }
    } catch (_) {}

    final match = RegExp(r'[#?&]access_token=([^&]+)').firstMatch(url);
    if (match != null && match.groupCount >= 1) {
      final token = match.group(1);
      if (token != null && token.isNotEmpty) {
        return Uri.decodeComponent(token);
      }
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _initWebView();
    } else {
      _isLoading = false;
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final token = _extractTokenFromUrl(request.url);
            if (token != null) {
              _onTokenFound(token);
              return NavigationDecision.prevent;
            }
            if (request.url.contains('error=access_denied')) {
              Navigator.of(context).pop(false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            if (mounted) setState(() => _isLoading = true);
            final token = _extractTokenFromUrl(url);
            if (token != null) {
              _onTokenFound(token);
            }
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _isLoading = false);
            final token = _extractTokenFromUrl(url);
            if (token != null) {
              _onTokenFound(token);
            } else {
              _attemptTokenExtraction();
            }
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) {
              final token = _extractTokenFromUrl(url);
              if (token != null) {
                _onTokenFound(token);
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(DiscordWebViewScreen.oauthAuthorizeUrl));

    _pollTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (!_isAuthorizing && mounted) {
        _attemptTokenExtraction();
      }
    });
  }

  Future<void> _attemptTokenExtraction() async {
    if (_controller == null || _isAuthorizing) return;
    try {
      final raw = await _controller!.runJavaScriptReturningResult(_tokenExtractionScript);
      final rawStr = raw.toString().trim();
      if (rawStr.isEmpty || rawStr == 'null' || rawStr == 'undefined') return;

      final cleanToken = rawStr.replaceAll('"', '').trim();
      if (cleanToken.length > 20) {
        await _onTokenFound(cleanToken);
      }
    } catch (_) {}
  }

  Future<void> _onTokenFound(String token) async {
    if (_isAuthorizing) return;
    setState(() => _isAuthorizing = true);
    _pollTimer?.cancel();

    try {
      final user = await DiscordRpcService.validateAndFetchUser(token);
      if (!mounted) return;

      if (user != null) {
        await widget.settingsService.setDiscordAccount(
          token: user.token,
          username: user.username,
          avatar: user.avatar,
          userId: user.id,
        );

        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Connected to Discord as @${user.username}!',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF5865F2),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isAuthorizing = false);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const discordColor = Color(0xFF5865F2);
    final surfaceColor = widget.settingsService.surfaceColor;
    final textColor = widget.settingsService.textColor;
    final canUseWebView = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: textColor),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Row(
          children: [
            const Icon(Icons.headset_mic_rounded, color: discordColor, size: 22),
            const SizedBox(width: 10),
            Text(
              'Discord Login',
              style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(discordColor),
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          if (canUseWebView && _controller != null)
            WebViewWidget(controller: _controller!)
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.desktop_windows_rounded, color: discordColor, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'PC Discord RPC Active',
                      style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'On PC, FinAudio connects to Discord Desktop automatically via native IPC named pipes with zero login required.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          if (_isAuthorizing)
            Container(
              color: Colors.black.withValues(alpha: 0.65),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: discordColor),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Connecting your Discord account...',
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
