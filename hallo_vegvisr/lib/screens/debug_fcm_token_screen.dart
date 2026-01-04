import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show firebaseInitialized;
import '../services/push_notification_service.dart';

class DebugFcmTokenScreen extends StatefulWidget {
  const DebugFcmTokenScreen({super.key});

  @override
  State<DebugFcmTokenScreen> createState() => _DebugFcmTokenScreenState();
}

class _DebugFcmTokenScreenState extends State<DebugFcmTokenScreen> {
  final _pushService = PushNotificationService();
  String? _token;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!firebaseInitialized) {
        setState(() {
          _error = 'Firebase not initialized on this build.';
          _loading = false;
        });
        return;
      }

      // Try stored token first
      final stored = await _pushService.getToken();

      // Ask FCM for a fresh token (helps when switching accounts/devices)
      final fresh = await FirebaseMessaging.instance.getToken();
      final resolvedToken = fresh ?? stored;

      if (!mounted) return;
      setState(() {
        _token = resolvedToken;
        _loading = false;
        if (resolvedToken == null) {
          _error = 'No FCM token yet. Try refresh after login or check push permissions.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load token: $e';
        _loading = false;
      });
    }
  }

  Future<void> _copyToken() async {
    if (_token == null) return;
    await Clipboard.setData(ClipboardData(text: _token!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('FCM token copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FCM Token Debug'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current FCM token',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Loading token...'),
                ],
              )
            else if (_token != null)
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _token!,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              )
            else if (_error != null)
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
              )
            else
              const Text('No token available yet.'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _loading || _token == null ? null : _copyToken,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _loadToken,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Tip: log in first so the token is registered to your account. Refresh after switching accounts or reinstalling.',
            ),
          ],
        ),
      ),
    );
  }
}
