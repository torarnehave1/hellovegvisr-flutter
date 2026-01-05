import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class VoiceNoteService {
  static const String baseUrl = 'https://voice.vegvisr.org';

  Future<Map<String, dynamic>> uploadVoiceNote({
    required String chatId,
    required Uint8List bytes,
    required String fileName,
    String? messageId,
    String contentType = 'audio/mp4',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/upload'),
      headers: {
        'Content-Type': contentType,
        'X-File-Name': fileName,
        'X-Chat-Id': chatId,
        if (messageId != null && messageId.isNotEmpty) 'X-Message-Id': messageId,
      },
      body: bytes,
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to upload voice note');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> transcribe({
    String? audioUrl,
    String? objectKey,
    String model = 'whisper-1',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/transcribe'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (audioUrl != null) 'audioUrl': audioUrl,
        if (objectKey != null) 'objectKey': objectKey,
        'model': model,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to transcribe voice note');
    }
    return Map<String, dynamic>.from(data);
  }
}
