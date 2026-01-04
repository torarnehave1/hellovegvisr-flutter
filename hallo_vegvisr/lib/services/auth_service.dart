import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AuthService {
  static const String smsApiUrl =
      'https://smsgway.vegvisr.org';

  /// Send 6-digit SMS verification code to user's phone
  /// Phone number should be Norwegian format (8 digits or +47...)
  Future<Map<String, dynamic>> sendOtpCode(String phone) async {
    try {
      final response = await http.post(
        Uri.parse('$smsApiUrl/api/auth/phone/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'phone': data['phone'],
          'expires_at': data['expires_at'],
          'message': data['message'] ?? 'Code sent',
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to send code',
        };
      }
    } catch (e) {
      print('Send OTP error: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Verify 6-digit SMS code
  /// Returns success with user data if verification succeeds
  Future<Map<String, dynamic>> verifyOtpCode(String phone, String code) async {
    try {
      final response = await http.post(
        Uri.parse('$smsApiUrl/api/auth/phone/verify-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'code': code,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // Save user session
        await _saveUser(data);
        return {
          'success': true,
          'email': data['email'],
          'phone': data['phone'],
          'verified_at': data['verified_at'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Invalid code',
        };
      }
    } catch (e) {
      print('Verify OTP error: $e');
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Check phone verification status
  Future<Map<String, dynamic>?> checkPhoneStatus(String phone) async {
    try {
      final response = await http.get(
        Uri.parse('$smsApiUrl/api/auth/phone/status?phone=${Uri.encodeComponent(phone)}'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Check phone status error: $e');
      return null;
    }
  }

  Future<void> _saveUser(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', userData['email'] ?? '');
    await prefs.setString('user_phone', userData['phone'] ?? '');
    await prefs.setInt('verified_at', userData['verified_at'] ?? 0);
    await prefs.setBool('logged_in', true);

    // Use user_id from database (returned by verify-code endpoint)
    final dbUserId = userData['user_id'];
    if (dbUserId != null && dbUserId.toString().isNotEmpty) {
      await prefs.setString('user_id', dbUserId.toString());
    }
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('logged_in') ?? false;
  }

  Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_email');
  }

  Future<String?> getPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_phone');
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_email');
    await prefs.remove('user_phone');
    await prefs.remove('verified_at');
    await prefs.setBool('logged_in', false);
  }
}
