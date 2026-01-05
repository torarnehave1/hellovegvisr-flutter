import 'dart:convert';
import 'package:http/http.dart' as http;

class GroupChatService {
  static const String baseUrl = 'https://group-chat-worker.torarnehave.workers.dev';

  Future<List<Map<String, dynamic>>> fetchGroups({
    required String userId,
    required String phone,
    String? email,
    int? since,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/groups?user_id=${Uri.encodeComponent(userId)}&phone=${Uri.encodeComponent(phone)}'
      '${email != null && email.isNotEmpty ? '&email=${Uri.encodeComponent(email)}' : ''}'
      '${since != null ? '&since=$since' : ''}',
    );

    final response = await http.get(uri);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to load groups');
    }
    return List<Map<String, dynamic>>.from(data['groups'] ?? []);
  }

  Future<Map<String, dynamic>> createGroup({
    required String name,
    required String createdBy,
    required String phone,
    String? email,
    String? graphId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/groups'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'created_by': createdBy,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (graphId != null && graphId.isNotEmpty) 'graph_id': graphId,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 201 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to create group');
    }
    return Map<String, dynamic>.from(data['group']);
  }

  Future<List<Map<String, dynamic>>> fetchMessages({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
    int after = 0,
    int limit = 50,
    bool latest = false,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/groups/$groupId/messages?user_id=${Uri.encodeComponent(userId)}'
      '&phone=${Uri.encodeComponent(phone)}'
      '${email != null && email.isNotEmpty ? '&email=${Uri.encodeComponent(email)}' : ''}'
      '&after=$after&limit=$limit'
      '${latest ? '&latest=1' : ''}',
    );

    final response = await http.get(uri);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to load messages');
    }
    return List<Map<String, dynamic>>.from(data['messages'] ?? []);
  }

  Future<Map<String, dynamic>> sendMessage({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
    required String body,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/groups/$groupId/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        'body': body,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 201 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to send message');
    }
    return Map<String, dynamic>.from(data['message']);
  }

  Future<Map<String, dynamic>> sendVoiceMessage({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
    required String audioUrl,
    int? audioDurationMs,
    String? transcriptText,
    String? transcriptLang,
    String? transcriptionStatus,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/groups/$groupId/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        'type': 'voice',
        'audio_url': audioUrl,
        if (audioDurationMs != null) 'audio_duration_ms': audioDurationMs,
        if (transcriptText != null) 'transcript_text': transcriptText,
        if (transcriptLang != null) 'transcript_lang': transcriptLang,
        if (transcriptionStatus != null) 'transcription_status': transcriptionStatus,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 201 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to send voice message');
    }
    return Map<String, dynamic>.from(data['message']);
  }

  Future<Map<String, dynamic>> updateMessageTranscript({
    required String groupId,
    required int messageId,
    required String userId,
    required String phone,
    String? email,
    String? transcriptText,
    String? transcriptLang,
    String? transcriptionStatus,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/groups/$groupId/messages/$messageId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (transcriptText != null) 'transcript_text': transcriptText,
        if (transcriptLang != null) 'transcript_lang': transcriptLang,
        if (transcriptionStatus != null) 'transcription_status': transcriptionStatus,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to update transcript');
    }
    return Map<String, dynamic>.from(data['message']);
  }

  /// Create an invite link for a group (owner/admin only)
  Future<Map<String, dynamic>> createInviteLink({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
    int expiresInDays = 7,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/groups/$groupId/invite'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        'expires_in_days': expiresInDays,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 201 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to create invite link');
    }
    return Map<String, dynamic>.from(data['invite']);
  }

  /// Get invite info by code (no auth required)
  Future<Map<String, dynamic>> getInviteInfo(String code) async {
    final response = await http.get(Uri.parse('$baseUrl/invite/$code'));

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Invalid invite code');
    }
    return Map<String, dynamic>.from(data['invite']);
  }

  /// Join a group via invite code
  Future<Map<String, dynamic>> joinViaInvite({
    required String code,
    required String userId,
    required String phone,
    String? email,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/invite/$code/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to join group');
    }
    return Map<String, dynamic>.from(data);
  }

  /// Get a single group's details
  Future<Map<String, dynamic>?> fetchGroup({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
  }) async {
    // Fetch all groups and find the one we need
    final groups = await fetchGroups(userId: userId, phone: phone, email: email);
    for (final g in groups) {
      if (g['id'] == groupId) {
        return g;
      }
    }
    return null;
  }

  /// Update group info (name, image_url) - owner/admin only
  Future<Map<String, dynamic>> updateGroup({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
    String? name,
    String? imageUrl,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/groups/$groupId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (name != null) 'name': name,
        if (imageUrl != null) 'image_url': imageUrl,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to update group');
    }
    return Map<String, dynamic>.from(data['group']);
  }

  /// Get members of a group
  Future<List<Map<String, dynamic>>> fetchMembers({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/groups/$groupId/members?user_id=${Uri.encodeComponent(userId)}'
      '&phone=${Uri.encodeComponent(phone)}'
      '${email != null && email.isNotEmpty ? '&email=${Uri.encodeComponent(email)}' : ''}',
    );

    final response = await http.get(uri);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to load members');
    }
    return List<Map<String, dynamic>>.from(data['members'] ?? []);
  }
}
