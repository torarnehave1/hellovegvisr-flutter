import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class AiChatService {
  static const String _smsGatewayUrl = 'https://smsgway.vegvisr.org';
  static const String _openAiWorkerUrl = 'https://openai.vegvisr.org';

  Future<Map<String, dynamic>> sendMessage({
    required String phone,
    String? userId,
    required String provider,
    required List<Map<String, String>> messages,
  }) async {
    try {
      if (provider == 'gemini') {
        final prompt = _buildGeminiPrompt(messages);
        final model = FirebaseAI.googleAI()
            .generativeModel(model: 'gemini-2.5-flash');
        final response = await model.generateContent([Content.text(prompt)]);
        final text = response.text?.trim() ?? '';
        return {
          'success': true,
          'message': text,
          'model': 'gemini-2.5-flash',
          'usage': response.usageMetadata,
        };
      }

      final response = await http.post(
        Uri.parse('$_smsGatewayUrl/api/ai-chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'userId': userId,
          'provider': provider,
          'messages': messages,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'],
          'model': data['model'],
          'usage': data['usage'],
        };
      }

      return {
        'success': false,
        'error': data['error'] ?? 'AI request failed',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  String _buildGeminiPrompt(List<Map<String, String>> messages) {
    return messages
        .map((msg) {
          final role = (msg['role'] ?? 'user').toUpperCase();
          final content = (msg['content'] ?? '').trim();
          return '$role: $content';
        })
        .where((line) => line.trim().isNotEmpty)
        .join('\n\n');
  }

  Future<Map<String, dynamic>> generateOpenAiImage({
    required String prompt,
    String? userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_openAiWorkerUrl/images'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'prompt': prompt,
          'model': 'gpt-image-1',
          'size': '1024x1024',
          'response_format': 'b64_json',
          if (userId != null && userId.isNotEmpty) 'userId': userId,
        }),
      );

      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': response.body.isNotEmpty
              ? response.body
              : 'OpenAI image request failed',
        };
      }

      final data = jsonDecode(response.body);
      final b64 = data['data']?[0]?['b64_json'];
      if (b64 == null) {
        return {
          'success': false,
          'error': 'OpenAI did not return image data',
        };
      }

      final bytes = base64Decode(b64);
      return {
        'success': true,
        'bytes': bytes,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'OpenAI image error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> transcribeOpenAiAudio({
    required String filePath,
    String? userId,
  }) async {
    try {
      final allowed = {
        'flac': 'audio/flac',
        'm4a': 'audio/mp4',
        'mp3': 'audio/mpeg',
        'mp4': 'audio/mp4',
        'mpeg': 'audio/mpeg',
        'mpga': 'audio/mpeg',
        'oga': 'audio/ogg',
        'ogg': 'audio/ogg',
        'wav': 'audio/wav',
        'webm': 'audio/webm',
      };

      String ext = filePath.split('.').last.toLowerCase();
      return await _uploadTranscription(filePath, userId, allowed, ext);
    } catch (e) {
      return {
        'success': false,
        'error': 'OpenAI transcription error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> _uploadTranscription(
    String filePath,
    String? userId,
    Map<String, String> allowed,
    String ext,
  ) async {
    final contentType = allowed[ext];
    if (contentType == null) {
      return {
        'success': false,
        'error': 'Unsupported audio format. Please use: ${allowed.keys.join(', ')}',
      };
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_openAiWorkerUrl/audio'),
    );

    if (userId != null && userId.isNotEmpty) {
      request.fields['userId'] = userId;
    }
    request.fields['model'] = 'whisper-1';
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        filePath,
        contentType: MediaType.parse(contentType),
      ),
    );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      return {
        'success': false,
        'error':
            response.body.isNotEmpty ? response.body : 'OpenAI transcription failed',
      };
    }

    final data = jsonDecode(response.body);
    final text = (data['text'] ?? '').toString();
    if (text.isEmpty) {
      return {
        'success': false,
        'error': 'No transcription text returned',
      };
    }
    return {
      'success': true,
      'text': text,
    };
  }

  // Conversion removed for stability; expect supported formats only.
}
