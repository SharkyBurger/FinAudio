import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:finaudio/services/google_auth_service.dart';

/// Shows an adaptive Google / YouTube Music sign-in dialog.
/// On desktop (Windows/Linux), allows connecting via YouTube handle (@username),
/// channel link/ID, or InnerTube auth token.
/// On mobile/web, provides both native Google Sign-In and InnerTube handle connect.
Future<void> showGoogleSignInDialog({
  required BuildContext context,
  required GoogleAuthService authService,
  required Color accentColor,
  VoidCallback? onSignedIn,
}) async {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _GoogleSignInDialog(
      authService: authService,
      accentColor: accentColor,
      onSignedIn: onSignedIn,
    ),
  );
}

class _GoogleSignInDialog extends StatefulWidget {
  final GoogleAuthService authService;
  final Color accentColor;
  final VoidCallback? onSignedIn;

  const _GoogleSignInDialog({
    required this.authService,
    required this.accentColor,
    this.onSignedIn,
  });

  @override
  State<_GoogleSignInDialog> createState() => _GoogleSignInDialogState();
}

class _GoogleSignInDialogState extends State<_GoogleSignInDialog> {
  final TextEditingController _handleController = TextEditingController();
  final TextEditingController _cookieController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showAdvanced = false;
  bool _showOAuthDetails = false;

  @override
  void initState() {
    super.initState();
    _clientIdController.text = widget.authService.customClientId ?? '';
  }

  @override
  void dispose() {
    _handleController.dispose();
    _cookieController.dispose();
    _clientIdController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    final input = _handleController.text.trim();
    final cookie = _cookieController.text.trim();

    if (input.isEmpty && cookie.isEmpty) {
      setState(() => _error = 'Please enter your YouTube handle (@yourname) or Google Token (ya29...).');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String cleanInput = input;
      if (cleanInput.contains('youtube.com/') || cleanInput.contains('youtu.be/')) {
        final uri = Uri.tryParse(cleanInput);
        if (uri != null) {
          final segments = uri.pathSegments;
          if (segments.isNotEmpty) {
            if (segments.first.startsWith('@')) {
              cleanInput = segments.first;
            } else if (segments.first == 'channel' && segments.length > 1) {
              cleanInput = segments[1];
            } else if (segments.first == 'c' && segments.length > 1) {
              cleanInput = segments[1];
            } else {
              cleanInput = segments.last;
            }
          }
        }
      } else if (!cleanInput.startsWith('@') &&
          !cleanInput.startsWith('UC') &&
          !cleanInput.startsWith('ya29.') &&
          cleanInput.isNotEmpty) {
        cleanInput = '@$cleanInput';
      }

      if (cleanInput.startsWith('ya29.')) {
        await widget.authService.signInWithGoogleToken(cleanInput);
      } else {
        await widget.authService.signInWithInnerTube(
          handleOrChannelId: cleanInput,
          authCookie: cookie.isNotEmpty ? cookie : null,
        );
      }
      if (!mounted) return;
      widget.onSignedIn?.call();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected as ${widget.authService.currentUser?.displayName ?? 'User'}!'),
          backgroundColor: widget.accentColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to connect: $e';
      });
    }
  }

  Future<void> _handleNativeSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await widget.authService.signIn();
      if (!mounted) return;
      if (user != null) {
        widget.onSignedIn?.call();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Signed in as ${user.displayName ?? user.email}!'),
            backgroundColor: widget.accentColor,
          ),
        );
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        final errStr = '$e';
        if (errStr.contains('redirect_uri_mismatch') || errStr.contains('400')) {
          _error = 'Google Cloud rejected browser sign-in.\n'
              'Skip Google Cloud entirely: type your YouTube handle (@username) or Google token above!';
        } else {
          _error = errStr;
        }
      });
    }
  }

  Future<void> _saveCustomClientId() async {
    final newId = _clientIdController.text.trim();
    await widget.authService.setCustomClientId(newId.isNotEmpty ? newId : null);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newId.isNotEmpty
            ? 'Custom Client ID saved!'
            : 'Reset to default Client ID!'),
        backgroundColor: widget.accentColor,
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNativeSupported = widget.authService.isNativeGoogleSignInPluginSupported;
    final onAccent = widget.accentColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    const redirectUri = 'http://127.0.0.1:${GoogleAuthService.desktopOAuthPort}';

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.account_circle_rounded, color: widget.accentColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google & YouTube Account',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Sync playlists, subscriptions & speed dial',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // SECTION 1: YouTube Handle Connect (Primary on Desktop)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: !isNativeSupported
                      ? widget.accentColor.withAlpha(20)
                      : theme.colorScheme.surfaceContainerHighest.withAlpha(100),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: !isNativeSupported
                        ? widget.accentColor.withAlpha(80)
                        : theme.colorScheme.outlineVariant.withAlpha(50),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.alternate_email_rounded,
                            size: 18, color: !isNativeSupported ? widget.accentColor : theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Connect via YouTube Handle',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (!isNativeSupported) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: widget.accentColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'RECOMMENDED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: onAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Instant sync for your playlists, subscribed artists, and profile. Zero setup required.',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _handleController,
                            autofocus: !isNativeSupported,
                            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: '@yourname (e.g. @sharkyburger)',
                              hintStyle: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant.withAlpha(140),
                                fontSize: 13,
                              ),
                              prefixIcon: Icon(Icons.person_outline_rounded,
                                  color: widget.accentColor, size: 18),
                              filled: true,
                              fillColor: theme.colorScheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onSubmitted: (_) => _handleConnect(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _loading ? null : _handleConnect,
                          style: FilledButton.styleFrom(
                            backgroundColor: widget.accentColor,
                            foregroundColor: onAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Connect Account'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Divider(color: theme.colorScheme.outlineVariant.withAlpha(80))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'OR VIA BROWSER',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: theme.colorScheme.outlineVariant.withAlpha(80))),
                ],
              ),
              const SizedBox(height: 14),

              // SECTION 2: Google Sign-In (WebAuth on Desktop)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _handleNativeSignIn,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.g_mobiledata_rounded, size: 24),
                  label: Text(_loading ? 'Signing in via Browser…' : 'Sign in with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              if (!isNativeSupported) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => setState(() => _showOAuthDetails = !_showOAuthDetails),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _showOAuthDetails ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _showOAuthDetails ? 'Hide Google Cloud settings' : 'Advanced: Google Cloud settings (optional)',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showOAuthDetails) ...[
                  const SizedBox(height: 8),
                  // OAuth Helper Card for Desktop
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(50)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 15, color: widget.accentColor),
                            const SizedBox(width: 6),
                            Text(
                              'Google Cloud Redirect URI:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: SelectableText(
                                  redirectUri,
                                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 15),
                                tooltip: 'Copy Redirect URI',
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  Clipboard.setData(const ClipboardData(text: redirectUri));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Copied $redirectUri to clipboard!')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _clientIdController,
                                style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: 'Paste custom Client ID (...apps.googleusercontent.com)',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
                                    fontSize: 11,
                                  ),
                                  filled: true,
                                  fillColor: theme.colorScheme.surfaceContainerHighest,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _saveCustomClientId,
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              // Advanced Cookie toggle
              const SizedBox(height: 10),
              InkWell(
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvanced ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _showAdvanced ? 'Hide private playlist cookie sync' : 'Sync private playlists (optional cookie)',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_showAdvanced) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _cookieController,
                  maxLines: 2,
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Paste YouTube Music Cookie (SAPISID=...; HSID=...)',
                    hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withAlpha(120), fontSize: 11),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withAlpha(120),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.error.withAlpha(80)),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 11, height: 1.3),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Close', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
