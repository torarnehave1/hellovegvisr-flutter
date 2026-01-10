import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Represents invitation details from the API
class InvitationDetails {
  final String domain;
  final String role;
  final DateTime expiresAt;
  final Map<String, dynamic>? branding;
  final bool isValid;
  final String? errorMessage;

  InvitationDetails({
    required this.domain,
    required this.role,
    required this.expiresAt,
    this.branding,
    this.isValid = true,
    this.errorMessage,
  });

  factory InvitationDetails.fromJson(Map<String, dynamic> json) {
    return InvitationDetails(
      domain: json['domain'] ?? '',
      role: json['role'] ?? 'member',
      expiresAt: DateTime.parse(json['expiresAt'] ?? DateTime.now().toIso8601String()),
      branding: json['branding'] as Map<String, dynamic>?,
      isValid: true,
    );
  }

  factory InvitationDetails.error(String message) {
    return InvitationDetails(
      domain: '',
      role: '',
      expiresAt: DateTime.now(),
      isValid: false,
      errorMessage: message,
    );
  }

  /// Get the logo URL from branding
  String? get logoUrl => branding?['myLogo'] as String?;

  /// Get the site title from branding
  String? get siteTitle => branding?['mySite'] as String?;
}

/// Service for handling brand invitations
class InvitationService {
  static const String _apiBaseUrl = 'https://vegvisr-frontend.torarnehave.workers.dev';

  // Store pending invite code for after login
  static String? _pendingInviteCode;

  /// Set a pending invite code (used when user needs to login first)
  static void setPendingInvite(String code) {
    _pendingInviteCode = code;
    debugPrint('InvitationService: Saved pending invite: $code');
  }

  /// Get and clear the pending invite code
  static String? consumePendingInvite() {
    final code = _pendingInviteCode;
    _pendingInviteCode = null;
    if (code != null) {
      debugPrint('InvitationService: Consumed pending invite: $code');
    }
    return code;
  }

  /// Check if there's a pending invite
  static bool get hasPendingInvite => _pendingInviteCode != null;

  /// Fetch invitation details from the API
  static Future<InvitationDetails> getInvitationDetails(String inviteCode) async {
    try {
      final url = '$_apiBaseUrl/brand-invite/$inviteCode';
      debugPrint('InvitationService: Fetching invite details from $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return InvitationDetails.fromJson(data);
        } else {
          return InvitationDetails.error(data['error'] ?? 'Invalid invitation');
        }
      } else if (response.statusCode == 404) {
        return InvitationDetails.error('Invitation not found');
      } else if (response.statusCode == 410) {
        final data = jsonDecode(response.body);
        return InvitationDetails.error(data['error'] ?? 'Invitation expired or already used');
      } else {
        return InvitationDetails.error('Failed to load invitation');
      }
    } catch (e) {
      debugPrint('InvitationService: Error fetching invite: $e');
      return InvitationDetails.error('Network error. Please try again.');
    }
  }

  /// Accept an invitation
  static Future<Map<String, dynamic>> acceptInvitation(String inviteCode, String phone) async {
    try {
      final url = '$_apiBaseUrl/brand-invite/$inviteCode/accept';
      debugPrint('InvitationService: Accepting invite at $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        debugPrint('InvitationService: Invite accepted for domain: ${data['domain']}');
        return {
          'success': true,
          'domain': data['domain'],
          'role': data['role'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to accept invitation',
        };
      }
    } catch (e) {
      debugPrint('InvitationService: Error accepting invite: $e');
      return {
        'success': false,
        'error': 'Network error. Please try again.',
      };
    }
  }

  /// Create a new invitation for a brand (used for sharing)
  static Future<Map<String, dynamic>> createInvitation({
    required String domain,
    required String phone,
    String role = 'member',
  }) async {
    try {
      final url = '$_apiBaseUrl/brand-invites';
      debugPrint('InvitationService: Creating invite at $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'domain': domain,
          'phone': phone,
          'role': role,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data['success'] == true) {
          debugPrint('InvitationService: Created invite: ${data['inviteCode']}');
          return {
            'success': true,
            'inviteCode': data['inviteCode'],
            'inviteUrl': data['inviteUrl'],
          };
        }
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to create invitation',
      };
    } catch (e) {
      debugPrint('InvitationService: Error creating invite: $e');
      return {
        'success': false,
        'error': 'Network error. Please try again.',
      };
    }
  }

  /// Parse invite code from a URL or deep link
  static String? parseInviteCode(String uri) {
    // Handle various URL formats:
    // - hallovegvisr://join/inv_xxxxx
    // - https://vegvisr.org/join/inv_xxxxx
    // - /join/inv_xxxxx
    // - inv_xxxxx

    if (uri.contains('/join/')) {
      final parts = uri.split('/join/');
      if (parts.length > 1) {
        return parts.last.split('?').first.split('#').first;
      }
    }

    // Direct invite code
    if (uri.startsWith('inv_')) {
      return uri.split('?').first.split('#').first;
    }

    return null;
  }
}
