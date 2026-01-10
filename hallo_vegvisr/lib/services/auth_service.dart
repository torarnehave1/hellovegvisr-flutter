import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'branding_service.dart';

class AuthService {
  static const String smsApiUrl = 'https://smsgway.vegvisr.org';

  /// Send 6-digit SMS verification code to user's phone
  /// Phone number should be Norwegian format (8 digits or +47...)
  Future<Map<String, dynamic>> sendOtpCode(String phone) async {
    // Demo/reviewer bypass: Skip SMS for demo phone number
    if (phone == '+4712003400' || phone == '12003400') {
      return {
        'success': true,
        'phone': '+4712003400',
        'expires_at': DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'message': 'Demo account - use code: 123456',
      };
    }

    try {
      final response = await http.post(
        Uri.parse('$smsApiUrl/api/auth/phone/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
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
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Verify 6-digit SMS code
  /// Returns success with user data if verification succeeds
  Future<Map<String, dynamic>> verifyOtpCode(String phone, String code) async {
    // Demo/reviewer bypass: Accept code 123456 for demo phone
    if ((phone == '+4712003400' || phone == '12003400') && code == '123456') {
      final demoData = {
        'success': true,
        'email': 'post@slowyou.net',
        'phone': '+4712003400',
        'verified_at': DateTime.now().millisecondsSinceEpoch,
        'userId': 'demo-reviewer-user',
        'user_id': 'demo-reviewer-user',
      };
      await _saveUser(demoData);
      return demoData;
    }

    try {
      final response = await http.post(
        Uri.parse('$smsApiUrl/api/auth/phone/verify-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'code': code}),
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
        return {'success': false, 'error': data['error'] ?? 'Invalid code'};
      }
    } catch (e) {
      print('Verify OTP error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Check phone verification status
  Future<Map<String, dynamic>?> checkPhoneStatus(String phone) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$smsApiUrl/api/auth/phone/status?phone=${Uri.encodeComponent(phone)}',
        ),
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
    await prefs.remove('profile_image_url');
    await prefs.setBool('logged_in', false);
    // Clear branding cache on logout
    BrandingService.clearBranding();
  }

  /// Get user profile from server (includes profile_image_url)
  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      final phone = await getPhone();
      final userId = await getUserId();

      if (phone == null && userId == null) {
        return {'success': false, 'error': 'Not logged in'};
      }

      final queryParam = userId != null
          ? 'user_id=${Uri.encodeComponent(userId)}'
          : 'phone=${Uri.encodeComponent(phone!)}';

      final response = await http.get(
        Uri.parse('$smsApiUrl/api/auth/profile?$queryParam'),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // Cache the profile image URL locally
        if (data['profile_image_url'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('profile_image_url', data['profile_image_url']);
        }
        return {
          'success': true,
          'user_id': data['user_id'],
          'email': data['email'],
          'phone': data['phone'],
          'profile_image_url': data['profile_image_url'],
          'verified': data['verified'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to get profile',
        };
      }
    } catch (e) {
      print('Get profile error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Update user profile image URL
  Future<Map<String, dynamic>> updateProfileImage(String imageUrl) async {
    try {
      final phone = await getPhone();
      final userId = await getUserId();

      if (phone == null && userId == null) {
        return {'success': false, 'error': 'Not logged in'};
      }

      final response = await http.put(
        Uri.parse('$smsApiUrl/api/auth/profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'user_id': userId,
          'profile_image_url': imageUrl,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // Cache the profile image URL locally
        final prefs = await SharedPreferences.getInstance();
        if (imageUrl.isNotEmpty) {
          await prefs.setString('profile_image_url', imageUrl);
        } else {
          await prefs.remove('profile_image_url');
        }
        return {
          'success': true,
          'profile_image_url': data['profile_image_url'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to update profile',
        };
      }
    } catch (e) {
      print('Update profile error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Get cached profile image URL (from local storage)
  Future<String?> getProfileImageUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('profile_image_url');
  }

  /// Get another user's profile image by user_id (for chat display)
  Future<String?> getUserProfileImage(String userId) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$smsApiUrl/api/auth/profile/image?user_id=${Uri.encodeComponent(userId)}',
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['profile_image_url'];
      }
      return null;
    } catch (e) {
      print('Get user profile image error: $e');
      return null;
    }
  }
}
