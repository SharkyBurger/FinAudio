import 'package:flutter/material.dart';
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
  bool _loading = false;
  String? _error;
  bool _showAdvanced = false;

  @override
  void dispose() {
    _handleController.dispose();
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    final handle = _handleController.text.trim();
    final cookie = _cookieController.text.trim();

    if (handle.isEmpty && cookie.isEmpty) {
      setState(() => _error = 'Please enter your YouTube handle or channel ID.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.authService.signInWithInnerTube(
        handleOrChannelId: handle,
        authCookie: cookie.isNotEmpty ? cookie : null,
      );
      if (!mounted) return;
      widget.onSignedIn?.call();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected as ${widget.authService.currentUser?.displayName ?? 'YouTube User'}!'),
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
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNativeSupported = widget.authService.isNativeGoogleSignInPluginSupported;
    final onAccent = widget.accentColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
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
              const SizedBox(height: 20),

              // Google Sign-In (WebAuth on Desktop, Native SDK on Mobile/Web)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _handleNativeSignIn,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.g_mobiledata_rounded, size: 24),
                  label: Text(_loading ? 'Signing in via Browser…' : 'Sign in with Google'),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Divider(color: theme.colorScheme.outlineVariant.withAlpha(80))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'OR CONNECT VIA YOUTUBE HANDLE',
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

              // Handle Input
              Text(
                'Enter your YouTube Handle or Channel Link:',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _handleController,
                autofocus: !isNativeSupported,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: '@yourname (e.g. @sharkyburger)',
                  hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withAlpha(140)),
                  prefixIcon: Icon(Icons.alternate_email_rounded, color: widget.accentColor, size: 20),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onSubmitted: (_) => _handleConnect(),
              ),
              const SizedBox(height: 10),
              Text(
                'Connects your public YouTube Music profile, synced playlists, and subscribed artists.',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant.withAlpha(150)),
              ),

              // Advanced Cookie toggle
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvanced ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: widget.accentColor,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _showAdvanced ? 'Hide private playlist cookie sync' : 'Sync private playlists (optional cookie)',
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.accentColor,
                            fontWeight: FontWeight.w600,
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
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ],

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _loading ? null : _handleConnect,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Connect Account'),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      foregroundColor: onAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
}
