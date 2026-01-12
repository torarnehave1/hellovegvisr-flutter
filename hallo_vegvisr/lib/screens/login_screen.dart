import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/invitation_service.dart';
import '../main.dart' show firebaseInitialized;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _authService = AuthService();
  final _pushService = PushNotificationService();

  String _step = 'phone'; // 'phone' | 'code'
  bool _loading = false;
  String _error = '';
  String _success = '';
  String _normalizedPhone = '';
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = '${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _sendSmsCode() async {
    final phone = _phoneController.text.trim();

    if (phone.isEmpty || phone.length < 8) {
      setState(() => _error = 'Please enter a valid phone number (8 digits)');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
      _success = '';
    });

    final result = await _authService.sendOtpCode(phone);

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _step = 'code';
        _normalizedPhone = result['phone'] ?? phone;
        _success = 'SMS code sent! Check your phone.';
        _loading = false;
      });
    } else {
      setState(() {
        _error = result['error'] ?? 'Failed to send SMS code. Try again.';
        _loading = false;
      });
    }
  }

  Future<void> _verifyOtpCode() async {
    final code = _codeController.text.trim();

    if (code.isEmpty || code.length != 6) {
      setState(() => _error = 'Please enter a valid 6-digit code');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await _authService.verifyOtpCode(_normalizedPhone, code);

    if (!mounted) return;

    if (result['success'] == true) {
      // Register device for push notifications (if Firebase is configured)
      if (firebaseInitialized) {
        final userId = await _authService.getUserId();
        final email = await _authService.getEmail();
        if (userId != null) {
          await _pushService.registerDeviceToken(
            userId: userId,
            phone: _normalizedPhone,
            email: email,
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Login successful!')));

      // Check for pending brand invitation
      final pendingInvite = InvitationService.consumePendingInvite();
      if (pendingInvite != null) {
        // Redirect to accept the pending invitation
        context.go('/join/$pendingInvite');
      } else {
        // Navigate to home
        context.go('/');
      }
    } else {
      setState(() {
        _error = result['error'] ?? 'Invalid or expired code';
        _loading = false;
      });
    }
  }

  void _goBackToPhone() {
    setState(() {
      _step = 'phone';
      _codeController.clear();
      _error = '';
      _success = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SvgPicture.asset(
                    'assets/Black.svg',
                    width: 120,
                    semanticsLabel: 'Vegvisr logo',
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Hallo Vegvisr',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Powered by VEGR.AI',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 4),
                if (_appVersion.isNotEmpty)
                  Text(
                    'v$_appVersion',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                const SizedBox(height: 36),
                if (_step == 'phone') ...[
                  const Text(
                    'Sign in with SMS',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Norwegian numbers only (+47)',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      hintText: '12345678',
                      labelText: 'Phone number',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.phone),
                      prefixText: '+47 ',
                      helperText: 'Enter 8 digits without country code',
                    ),
                    keyboardType: TextInputType.phone,
                    maxLength: 8,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: _loading ? null : _sendSmsCode,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send SMS Code'),
                  ),
                ] else if (_step == 'code') ...[
                  const Icon(Icons.sms, color: Colors.green, size: 64),
                  const SizedBox(height: 24),
                  const Text(
                    'Enter verification code',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a 6-digit code to $_normalizedPhone',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  if (_success.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _success,
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  TextField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      hintText: '000000',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.security),
                    ),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLength: 6,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: _loading ? null : _verifyOtpCode,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verify Code'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _goBackToPhone,
                    child: const Text('Use a different number'),
                  ),
                  TextButton(
                    onPressed: _loading ? null : _sendSmsCode,
                    child: const Text('Resend code'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
