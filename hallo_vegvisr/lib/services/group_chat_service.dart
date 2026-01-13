import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class MessagesPage {
  final List<Map<String, dynamic>> messages;
  final bool hasMore;
  final int? nextBefore;

  const MessagesPage({
    required this.messages,
    required this.hasMore,
    required this.nextBefore,
  });
}

class GroupChatService {
  static const String baseUrl =
      'https://group-chat-worker.torarnehave.workers.dev';

  // Best-practice paging response for cursor-based history loads.
  // Existing call sites can continue using `fetchMessages()`.
  static const int _maxServerPageSize = 200;

  static int? _tryParseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static bool _tryParseBool(dynamic value) {
    if (value is bool) return value;
    final s = value?.toString().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  static List<Map<String, dynamic>> _parseMessages(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  Map<String, dynamic>? _tryDecodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Never _throwHttpFailure({
    required String action,
    required int statusCode,
    required String body,
  }) {
    final snippet = body.trim().isEmpty
        ? '<empty body>'
        : (body.length > 600 ? '${body.substring(0, 600)}…' : body);
    throw Exception('$action failed (HTTP $statusCode): $snippet');
  }

  Future<Map<String, dynamic>> uploadMediaStream({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
    required Stream<List<int>> stream,
    required int length,
    required String fileName,
    required String contentType,
    void Function(int sentBytes, int totalBytes)? onProgress,
    void Function(void Function() cancel)? onCancel,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/groups/$groupId/media?user_id=${Uri.encodeComponent(userId)}'
      '&phone=${Uri.encodeComponent(phone)}'
      '${email != null && email.isNotEmpty ? '&email=${Uri.encodeComponent(email)}' : ''}',
    );

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.headers.set('X-File-Name', fileName);
      request.contentLength = length;

      onCancel?.call(() {
        try {
          request.abort();
        } catch (_) {
          // ignore
        }
        client.close(force: true);
      });

      // Stream (no full buffering) + progress.
      var sent = 0;
      var sinceFlush = 0;
      const flushEveryBytes = 1024 * 1024; // 1MB
      await for (final chunk in stream.timeout(const Duration(minutes: 10))) {
        request.add(chunk);
        sent += chunk.length;
        sinceFlush += chunk.length;
        if (sinceFlush >= flushEveryBytes) {
          sinceFlush = 0;
          await request.flush();
        }
        onProgress?.call(sent, length);
      }
      onProgress?.call(length, length);
      final response = await request.close().timeout(
        const Duration(minutes: 15),
      );

      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(minutes: 2));

      final data = _tryDecodeJson(body);
      if (response.statusCode != 200) {
        if (data != null && data['error'] != null) {
          throw Exception(
            'Upload failed (HTTP ${response.statusCode}): ${data['error']}',
          );
        }
        _throwHttpFailure(
          action: 'Upload',
          statusCode: response.statusCode,
          body: body,
        );
      }
      if (data == null) {
        _throwHttpFailure(
          action: 'Upload',
          statusCode: response.statusCode,
          body: body,
        );
      }
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Failed to upload media');
      }
      return Map<String, dynamic>.from(data);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> uploadMediaFile({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
    required File file,
    required String fileName,
    required String contentType,
  }) async {
    final length = await file.length();
    return uploadMediaStream(
      groupId: groupId,
      userId: userId,
      phone: phone,
      email: email,
      stream: file.openRead(),
      length: length,
      fileName: fileName,
      contentType: contentType,
    );
  }

  Future<Map<String, dynamic>> uploadMedia({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/groups/$groupId/media?user_id=${Uri.encodeComponent(userId)}'
      '&phone=${Uri.encodeComponent(phone)}'
      '${email != null && email.isNotEmpty ? '&email=${Uri.encodeComponent(email)}' : ''}',
    );

    final response = await http.post(
      uri,
      headers: {'Content-Type': contentType, 'X-File-Name': fileName},
      body: bytes,
    );

    final body = response.body;
    final data = _tryDecodeJson(body);
    if (response.statusCode != 200) {
      if (data != null && data['error'] != null) {
        throw Exception(
          'Upload failed (HTTP ${response.statusCode}): ${data['error']}',
        );
      }
      _throwHttpFailure(
        action: 'Upload',
        statusCode: response.statusCode,
        body: body,
      );
    }
    if (data == null || data['success'] != true) {
      throw Exception((data ?? const {})['error'] ?? 'Failed to upload media');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> sendMediaMessage({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
    required String mediaUrl,
    required String mediaType, // 'image' | 'video'
    String? mediaObjectKey,
    String? mediaContentType,
    int? mediaSize,
    String? videoThumbnailUrl,
    int? videoDurationMs,
    String? body,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/groups/$groupId/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        'type': mediaType,
        'media_url': mediaUrl,
        if (mediaObjectKey != null && mediaObjectKey.isNotEmpty)
          'media_object_key': mediaObjectKey,
        if (mediaContentType != null && mediaContentType.isNotEmpty)
          'media_content_type': mediaContentType,
        if (mediaSize != null) 'media_size': mediaSize,
        if (mediaType == 'video' &&
            videoThumbnailUrl != null &&
            videoThumbnailUrl.isNotEmpty)
          'video_thumbnail_url': videoThumbnailUrl,
        if (mediaType == 'video' && videoDurationMs != null)
          'video_duration_ms': videoDurationMs,
        if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
      }),
    );

    final bodyJson = response.body;
    final data = _tryDecodeJson(bodyJson);
    if (response.statusCode != 201) {
      if (data != null && data['error'] != null) {
        throw Exception(
          'Send failed (HTTP ${response.statusCode}): ${data['error']}',
        );
      }
      _throwHttpFailure(
        action: 'Send',
        statusCode: response.statusCode,
        body: bodyJson,
      );
    }
    if (data == null || data['success'] != true) {
      throw Exception(
        (data ?? const {})['error'] ?? 'Failed to send media message',
      );
    }
    return Map<String, dynamic>.from(data['message']);
  }

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
    int? before,
    int limit = 50,
    bool latest = false,
  }) async {
    final clampedLimit = limit.clamp(1, _maxServerPageSize);
    final uri = Uri.parse(
      '$baseUrl/groups/$groupId/messages?user_id=${Uri.encodeComponent(userId)}'
      '&phone=${Uri.encodeComponent(phone)}'
      '${email != null && email.isNotEmpty ? '&email=${Uri.encodeComponent(email)}' : ''}'
      '&after=$after&limit=$clampedLimit'
      '${before != null && before > 0 ? '&before=$before' : ''}'
      '${latest ? '&latest=1' : ''}',
    );

    final response = await http.get(uri);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to load messages');
    }
    return List<Map<String, dynamic>>.from(data['messages'] ?? []);
  }

  Future<MessagesPage> fetchMessagesPage({
    required String groupId,
    required String userId,
    required String phone,
    String? email,
    int? before,
    int limit = 10,
  }) async {
    final clampedLimit = limit.clamp(1, _maxServerPageSize);
    final uri = Uri.parse(
      '$baseUrl/groups/$groupId/messages?user_id=${Uri.encodeComponent(userId)}'
      '&phone=${Uri.encodeComponent(phone)}'
      '${email != null && email.isNotEmpty ? '&email=${Uri.encodeComponent(email)}' : ''}'
      '&after=0&limit=$clampedLimit&latest=1'
      '${before != null && before > 0 ? '&before=$before' : ''}',
    );

    final response = await http.get(uri);
    final decoded = _tryDecodeJson(response.body);
    if (response.statusCode != 200 ||
        decoded == null ||
        decoded['success'] != true) {
      _throwHttpFailure(
        action: 'Load messages',
        statusCode: response.statusCode,
        body: response.body,
      );
    }

    final messages = _parseMessages(decoded['messages']);
    final pagingRaw = decoded['paging'];
    final paging = pagingRaw is Map
        ? Map<String, dynamic>.from(pagingRaw)
        : null;
    final hasMore = paging != null
        ? _tryParseBool(paging['has_more'])
        : (messages.length == clampedLimit);
    final nextBefore = paging != null
        ? _tryParseInt(paging['next_before'])
        : (messages.isNotEmpty ? (messages.first['id'] as int?) : null);

    return MessagesPage(
      messages: messages,
      hasMore: hasMore,
      nextBefore: nextBefore,
    );
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
    String? body,
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
        if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
        if (audioDurationMs != null) 'audio_duration_ms': audioDurationMs,
        if (transcriptText != null) 'transcript_text': transcriptText,
        if (transcriptLang != null) 'transcript_lang': transcriptLang,
        if (transcriptionStatus != null)
          'transcription_status': transcriptionStatus,
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
    String? body,
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
        if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
        if (transcriptText != null) 'transcript_text': transcriptText,
        if (transcriptLang != null) 'transcript_lang': transcriptLang,
        if (transcriptionStatus != null)
          'transcription_status': transcriptionStatus,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to update transcript');
    }
    return Map<String, dynamic>.from(data['message']);
  }

  Future<void> deleteMessage({
    required String groupId,
    required int messageId,
    required String userId,
    required String phone,
    String? email,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/groups/$groupId/messages/$messageId?user_id=${Uri.encodeComponent(userId)}'
      '&phone=${Uri.encodeComponent(phone)}'
      '${email != null && email.isNotEmpty ? '&email=${Uri.encodeComponent(email)}' : ''}',
    );

    final response = await http.delete(uri);
    final decoded = _tryDecodeJson(response.body);
    if (response.statusCode != 200 || decoded == null || decoded['success'] != true) {
      if (decoded != null && decoded['error'] != null) {
        throw Exception(decoded['error']);
      }
      _throwHttpFailure(
        action: 'Delete message',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
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
    final groups = await fetchGroups(
      userId: userId,
      phone: phone,
      email: email,
    );
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
