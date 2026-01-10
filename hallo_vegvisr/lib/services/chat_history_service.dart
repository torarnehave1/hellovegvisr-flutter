import 'dart:convert';

import 'package:http/http.dart' as http;

class ChatHistoryService {
  static const String baseUrl = 'https://api.vegvisr.org/chat-history';

  Map<String, String> _headers({
    required String userId,
    required String userEmail,
    String userRole = 'User',
    bool jsonContent = true,
  }) {
    return {
      if (jsonContent) 'Content-Type': 'application/json',
      'x-user-id': userId,
      'x-user-email': userEmail,
      'x-user-role': userRole,
    };
  }

  Future<Map<String, dynamic>> listSessions({
    required String userId,
    required String userEmail,
    required String graphId,
    String userRole = 'User',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/sessions').replace(
        queryParameters: {
          if (graphId.trim().isNotEmpty) 'graphId': graphId,
        },
      );

      final response = await http.get(
        uri,
        headers: _headers(userId: userId, userEmail: userEmail, userRole: userRole, jsonContent: false),
      );

      if (!response.statusCode.toString().startsWith('2')) {
        return {
          'success': false,
          'error': response.body.isNotEmpty ? response.body : 'Failed to load sessions (${response.statusCode})',
        };
      }

      final data = jsonDecode(response.body);
      return {
        'success': true,
        'sessions': (data['sessions'] as List?) ?? const [],
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> upsertSession({
    required String userId,
    required String userEmail,
    required String graphId,
    required String provider,
    Map<String, dynamic>? metadata,
    String? sessionId,
    String? title,
    String userRole = 'User',
  }) async {
    try {
      final payload = <String, dynamic>{
        'graphId': graphId,
        'provider': provider,
        if (metadata != null) 'metadata': metadata,
        if (sessionId != null && sessionId.trim().isNotEmpty) 'sessionId': sessionId,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      };

      final response = await http.post(
        Uri.parse('$baseUrl/sessions'),
        headers: _headers(userId: userId, userEmail: userEmail, userRole: userRole),
        body: jsonEncode(payload),
      );

      if (!response.statusCode.toString().startsWith('2')) {
        return {
          'success': false,
          'error': response.body.isNotEmpty ? response.body : 'Failed to create session (${response.statusCode})',
        };
      }

      final data = jsonDecode(response.body);
      return {
        'success': true,
        'session': data['session'],
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteSession({
    required String userId,
    required String userEmail,
    required String sessionId,
    String userRole = 'User',
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/sessions/$sessionId'),
        headers: _headers(userId: userId, userEmail: userEmail, userRole: userRole, jsonContent: false),
      );

      if (!response.statusCode.toString().startsWith('2')) {
        return {
          'success': false,
          'error': response.body.isNotEmpty ? response.body : 'Failed to delete session (${response.statusCode})',
        };
      }

      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> loadMessages({
    required String userId,
    required String userEmail,
    required String sessionId,
    int limit = 200,
    bool decrypt = true,
    String userRole = 'User',
  }) async {
    try {
      final params = {
        'sessionId': sessionId,
        'limit': '$limit',
        if (decrypt) 'decrypt': '1',
      };
      final uri = Uri.parse('$baseUrl/messages').replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: _headers(userId: userId, userEmail: userEmail, userRole: userRole, jsonContent: false),
      );

      if (!response.statusCode.toString().startsWith('2')) {
        return {
          'success': false,
          'error': response.body.isNotEmpty ? response.body : 'Failed to load messages (${response.statusCode})',
        };
      }

      final data = jsonDecode(response.body);
      return {
        'success': true,
        'messages': (data['messages'] as List?) ?? const [],
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> persistMessage({
    required String userId,
    required String userEmail,
    required String sessionId,
    required String role,
    required String content,
    String? provider,
    String userRole = 'User',
  }) async {
    try {
      final payload = <String, dynamic>{
        'sessionId': sessionId,
        'role': role,
        'content': content,
        if (provider != null && provider.trim().isNotEmpty) 'provider': provider,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/messages'),
        headers: _headers(userId: userId, userEmail: userEmail, userRole: userRole),
        body: jsonEncode(payload),
      );

      if (!response.statusCode.toString().startsWith('2')) {
        return {
          'success': false,
          'error': response.body.isNotEmpty ? response.body : 'Failed to persist message (${response.statusCode})',
        };
      }

      final data = jsonDecode(response.body);
      return {
        'success': true,
        'message': data['message'],
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }
}
