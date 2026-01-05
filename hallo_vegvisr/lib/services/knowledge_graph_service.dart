import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class KnowledgeGraphService {
  static const String uploadApiUrl = 'https://api.vegvisr.org/upload';
  // SMS Gateway handles authentication and proxies to Knowledge Graph Worker
  static const String smsGatewayUrl = 'https://smsgway.vegvisr.org';

  static String buildPublicGraphUrl(String graphId) =>
      'https://www.vegvisr.org/gnew-viewer?graphId=$graphId';

  /// Upload an image to R2 storage
  /// Returns the public URL of the uploaded image
  Future<Map<String, dynamic>> uploadImage(
    Uint8List imageBytes,
    String fileName,
    String mimeType,
  ) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(uploadApiUrl));
      request.files.add(
        http.MultipartFile.fromBytes('file', imageBytes, filename: fileName),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'url': data['url']};
      } else {
        return {
          'success': false,
          'error': 'Failed to upload image: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('Upload image error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Save content to the Knowledge Graph
  /// Calls SMS Gateway which validates phone auth and proxies to Knowledge Graph Worker
  Future<Map<String, dynamic>> saveToKnowledgeGraph({
    required String title,
    required String content,
    required String phone,
    String? userId,
    String? youtubeUrl,
    bool aiChatEnabled = true,
    String? aiProvider,
    bool publicEdit = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$smsGatewayUrl/api/save-graph'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'userId': userId,
          'title': title,
          'content': content,
          'youtubeUrl': youtubeUrl,
          'aiChatEnabled': aiChatEnabled,
          'aiProvider': aiProvider,
          'publicEdit': publicEdit,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'graphId': data['graphId'],
          'nodeId': data['nodeId'],
          'graphUrl': data['graphUrl'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to save to Knowledge Graph',
        };
      }
    } catch (e) {
      print('Save to knowledge graph error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Extract YouTube video ID from various URL formats
  String? extractYouTubeId(String url) {
    if (url.isEmpty) return null;

    // Pattern for youtube.com/watch?v=, youtu.be/, youtube.com/embed/, youtube.com/v/
    final patterns = [
      RegExp(
        r'(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/|youtube\.com\/v\/)([^&\n?#]+)',
      ),
      RegExp(r'^([a-zA-Z0-9_-]{11})$'), // Direct video ID
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  /// Normalize YouTube URL to standard format
  String? normalizeYouTubeUrl(String url) {
    final videoId = extractYouTubeId(url.trim());
    if (videoId != null) {
      return 'https://www.youtube.com/watch?v=$videoId';
    }
    return null;
  }

  /// Get graphs created by the authenticated user
  Future<Map<String, dynamic>> getMyGraphs({
    required String phone,
    String? userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$smsGatewayUrl/api/my-graphs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'userId': userId}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'graphs': data['graphs'] ?? []};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch graphs',
        };
      }
    } catch (e) {
      print('Get my graphs error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Delete a graph created by the authenticated user
  Future<Map<String, dynamic>> deleteGraph({
    required String phone,
    required String graphId,
    String? userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$smsGatewayUrl/api/delete-graph'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'userId': userId,
          'graphId': graphId,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Graph deleted successfully',
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to delete graph',
        };
      }
    } catch (e) {
      print('Delete graph error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Get a single graph's content for editing
  Future<Map<String, dynamic>> getGraph({
    required String phone,
    required String graphId,
    String? userId,
  }) async {
    try {
      debugPrint(
        '[GetGraph] request graphId=$graphId userId=$userId phone=$phone',
      );
      final response = await http.post(
        Uri.parse('$smsGatewayUrl/api/get-graph'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'userId': userId,
          'graphId': graphId,
        }),
      );

      debugPrint(
        '[GetGraph] status=${response.statusCode} body=${response.body}',
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'graph': data['graph']};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch graph',
        };
      }
    } catch (e) {
      print('Get graph error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// Update an existing graph
  Future<Map<String, dynamic>> updateGraph({
    required String phone,
    required String graphId,
    required String title,
    required String content,
    String? userId,
    String? youtubeUrl,
    bool publicEdit = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$smsGatewayUrl/api/update-graph'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'userId': userId,
          'graphId': graphId,
          'title': title,
          'content': content,
          'youtubeUrl': youtubeUrl,
          'publicEdit': publicEdit,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'graphId': data['graphId'],
          'newVersion': data['newVersion'],
          'message': data['message'] ?? 'Graph updated successfully',
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to update graph',
        };
      }
    } catch (e) {
      print('Update graph error: $e');
      return {'success': false, 'error': 'Network error: $e'};
    }
  }
}
