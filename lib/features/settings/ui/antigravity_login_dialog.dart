import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:pocketstrike/features/providers/data/antigravity_oauth.dart';

/// Guided Google sign-in for Antigravity.
///
/// The consent page is opened in the system browser. A loopback listener on
/// `localhost:51121` receives the authorization code and finishes the login
/// automatically; the code field stays available as a manual fallback.
class AntigravityLoginDialog extends StatefulWidget {
  const AntigravityLoginDialog({
    super.key,
    required this.session,
    required this.service,
  });

  final AntigravityOAuthSession session;
  final AntigravityOAuthService service;

  @override
  State<AntigravityLoginDialog> createState() => _AntigravityLoginDialogState();
}

class _AntigravityLoginDialogState extends State<AntigravityLoginDialog> {
  final TextEditingController _codeController = TextEditingController();
  StreamSubscription<String>? _subscription;
  bool _busy = false;
  bool _captured = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = widget.service.onCode.listen((code) {
      if (!mounted) return;
      _codeController.text = code;
      setState(() {
        _captured = true;
        _error = null;
      });
      _submit();
    });

    // The callback can land before the dialog is shown (for example when the
    // browser finishes very quickly). Pick up an already-captured code.
    final captured = widget.service.capturedCode;
    if (captured != null && captured.isNotEmpty) {
      _codeController.text = captured;
      _captured = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit();
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Paste the authorization code first.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await widget.service.exchangeCode(
        codeInput: code,
        codeVerifier: widget.session.codeVerifier,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on AntigravityOAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Login failed: $e';
      });
    }
  }

  Future<void> _openBrowser() async {
    final uri = Uri.parse(widget.session.authUrl);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(() => _error =
            'Could not open a browser. Copy the login link and open it manually.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open a browser: $e');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.session.authUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Login link copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.colorScheme;

    return AlertDialog(
      title: const Text('Login with Google'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. Finish the Google sign-in in your browser.\n'
                '2. Return here — Vina Agent captures the code automatically '
                'from localhost:51121.',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 10),
              SelectableText(
                widget.session.redirectUri,
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.primary,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 14),
              if (_captured)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: tokens.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _busy
                              ? 'Code captured. Finishing login...'
                              : 'Code captured from the browser.',
                          style: TextStyle(fontSize: 12, color: tokens.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: _codeController,
                minLines: 1,
                maxLines: 3,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Authorization code (fallback)',
                  hintText: 'Paste the code or the full localhost callback URL',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Paste from clipboard',
                    icon: const Icon(Icons.content_paste, size: 18),
                    onPressed: _busy
                        ? null
                        : () async {
                            final data =
                                await Clipboard.getData(Clipboard.kTextPlain);
                            final text = data?.text;
                            if (text != null && text.isNotEmpty) {
                              _codeController.text = text;
                            }
                          },
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12.5, color: tokens.error),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy ? null : _openBrowser,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open browser'),
                  ),
                  TextButton.icon(
                    onPressed: _copyLink,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy link'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Finish login'),
        ),
      ],
    );
  }
}
