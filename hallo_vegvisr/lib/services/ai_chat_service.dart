import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class AiChatService {
  static const String _smsGatewayUrl = 'https://smsgway.vegvisr.org';
  static const String _openAiWorkerUrl = 'https://openai.vegvisr.org';
  static const String _grokWorkerUrl = 'https://grok.vegvisr.org';

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
          'response_format': 'url',
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
      final imageData = (data['data'] as List?)?.isNotEmpty == true
          ? data['data'][0] as Map<String, dynamic>?
          : null;
      if (imageData == null) {
        return {
          'success': false,
          'error': 'OpenAI did not return image data',
        };
      }

      Uint8List? bytes;
      final b64 = imageData['b64_json'];
      if (b64 is String && b64.isNotEmpty) {
        bytes = base64Decode(b64);
      } else {
        final url = imageData['url']?.toString();
        if (url == null || url.isEmpty) {
          return {
            'success': false,
            'error': 'OpenAI did not return image data',
          };
        }
        final imageResponse = await http.get(Uri.parse(url));
        if (imageResponse.statusCode != 200) {
          return {
            'success': false,
            'error': 'Failed to download image (${imageResponse.statusCode})',
          };
        }
        bytes = imageResponse.bodyBytes;
      }

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

  Future<Map<String, dynamic>> generateGrokImage({
    required String prompt,
    String? userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_grokWorkerUrl/images'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'prompt': prompt,
          'model': 'grok-2-image',
          'response_format': 'url',
          if (userId != null && userId.isNotEmpty) 'userId': userId,
        }),
      );

      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': response.body.isNotEmpty
              ? response.body
              : 'Grok image request failed',
        };
      }

      final data = jsonDecode(response.body);
      final imageData = (data['data'] as List?)?.isNotEmpty == true
          ? data['data'][0] as Map<String, dynamic>?
          : null;
      if (imageData == null) {
        return {
          'success': false,
          'error': 'Grok did not return image data',
        };
      }

      // Grok returns JPG images at imgen.x.ai
      final url = imageData['url']?.toString();
      if (url == null || url.isEmpty) {
        return {
          'success': false,
          'error': 'Grok did not return image URL',
        };
      }

      final imageResponse = await http.get(Uri.parse(url));
      if (imageResponse.statusCode != 200) {
        return {
          'success': false,
          'error': 'Failed to download image (${imageResponse.statusCode})',
        };
      }

      return {
        'success': true,
        'bytes': imageResponse.bodyBytes,
        'revised_prompt': imageData['revised_prompt'], // Grok provides enhanced prompts
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Grok image error: $e',
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

  Future<Map<String, dynamic>> analyzeOpenAiImage({
    required Uint8List bytes,
    required String prompt,
    String? userId,
    String mimeType = 'image/png',
  }) async {
    try {
      final base64Image = base64Encode(bytes);
      final response = await http.post(
        Uri.parse('$_openAiWorkerUrl/gpt-4o'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mimeType;base64,$base64Image'}
                }
              ]
            }
          ],
          'max_tokens': 300,
        }),
      );

      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': response.body.isNotEmpty
              ? response.body
              : 'OpenAI image analysis failed',
        };
      }

      final data = jsonDecode(response.body);
      final content =
          data['choices']?[0]?['message']?['content']?.toString().trim();
      if (content == null || content.isEmpty) {
        return {
          'success': false,
          'error': 'OpenAI did not return analysis text',
        };
      }

      return {
        'success': true,
        'message': content,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'OpenAI image analysis error: $e',
      };
    }
  }

  // Conversion removed for stability; expect supported formats only.
}
