import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/ai_chat_service.dart';
import '../services/knowledge_graph_service.dart';
import '../services/voice_note_service.dart';

class GraphAiScreen extends StatefulWidget {
  final String? graphId;

  const GraphAiScreen({super.key, this.graphId});

  @override
  State<GraphAiScreen> createState() => _GraphAiScreenState();
}

class _GraphAiScreenState extends State<GraphAiScreen> {
  final _authService = AuthService();
  final _knowledgeGraphService = KnowledgeGraphService();
  final _aiChatService = AiChatService();
  final _voiceNoteService = VoiceNoteService();
  final _aiInputController = TextEditingController();
  final _aiScrollController = ScrollController();
  final _contentController = TextEditingController();
  final _titleController = TextEditingController();
  final _recorder = AudioRecorder();
  final _voiceDraftPlayer = AudioPlayer();

  String? _graphId;
  String? _graphTitle;
  String? _youtubeUrl;
  bool _publicEdit = false;
  bool _loading = true;
  bool _saving = false;
  String _error = '';

  bool _enableAiChat = true;
  String _aiProvider = 'grok';
  List<Map<String, String>> _aiMessages = [];
  bool _aiSending = false;
  bool _aiImageGenerating = false;
  String _aiImageError = '';
  Uint8List? _aiImageBytes;
  String? _aiImageUrl;
  String? _aiImagePrompt;
  bool _aiImageAnalyzing = false;
  String _aiImageAnalysisError = '';
  bool _aiAudioTranscribing = false;
  String _aiAudioError = '';
  String _aiAudioText = '';
  String _aiAudioFileName = '';
  bool _aiRecording = false;
  bool _voiceRecording = false;
  bool _voiceSending = false;
  String _voiceError = '';
  DateTime? _voiceRecordingStartedAt;
  String? _voiceDraftPath;
  int? _voiceDraftDurationMs;
  bool _voiceDraftPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadAiPreferences();
    _loadActiveGraph();
  }

  @override
  void dispose() {
    _aiInputController.dispose();
    _aiScrollController.dispose();
    _contentController.dispose();
    _titleController.dispose();
    _recorder.dispose();
    _voiceDraftPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadAiPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _enableAiChat = prefs.getBool('ai_enabled') ?? true;
      _aiProvider = prefs.getString('ai_provider') ?? 'grok';
    });
  }

  Future<void> _setAiProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', provider);
    if (!mounted) return;
    setState(() {
      _aiProvider = provider;
    });
  }

  void _showProviderSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Grok (xAI)'),
              onTap: () {
                _setAiProvider('grok');
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Gemini (Firebase AI)'),
              onTap: () {
                _setAiProvider('gemini');
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('OpenAI (GPT)'),
              onTap: () {
                _setAiProvider('openai');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadActiveGraph() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final prefs = await SharedPreferences.getInstance();
    final activeGraphId = widget.graphId ?? prefs.getString('active_graph_id');
    final activeGraphTitle = prefs.getString('active_graph_title');

    if (activeGraphId == null || activeGraphId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No active graph selected.';
      });
      return;
    }

    final phone = await _authService.getPhone();
    final userId = await _authService.getUserId();

    if (phone == null || phone.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Not logged in. Please log in again.';
      });
      return;
    }

    final result = await _knowledgeGraphService.getGraph(
      phone: phone,
      userId: userId,
      graphId: activeGraphId,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final graph = result['graph'] as Map<String, dynamic>;
      String content = graph['content'] ?? '';
      final footerIndex = content.lastIndexOf('\n\n---\n\n*Created by:');
      if (footerIndex > 0) {
        content = content.substring(0, footerIndex);
      }

      setState(() {
        _graphId = activeGraphId;
        _graphTitle = graph['title'] ?? activeGraphTitle ?? 'Untitled graph';
        _titleController.text = _graphTitle ?? '';
        _contentController.text = content;
        _youtubeUrl = graph['youtubeUrl'];
        _publicEdit = graph['publicEdit'] == true;
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Using active graph: ${_graphTitle ?? ''}')),
      );
    } else {
      setState(() {
        _loading = false;
        _error = result['error'] ?? 'Failed to load graph';
      });
    }
  }

  Future<void> _sendAiMessage() async {
    final prompt = _aiInputController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _aiInputController.clear();
    });

    await _sendAiPrompt(prompt);
  }

  Future<void> _sendAiPrompt(String prompt) async {
    if (_aiSending) return;

    final phone = await _authService.getPhone();
    final userId = await _authService.getUserId();

    if (phone == null || phone.isEmpty) {
      setState(() {
        _aiImageError = 'Not logged in. Please log in again.';
      });
      return;
    }

    final isImagePrompt = RegExp(
      r'\b(create|generate|make|draw)\s+(an\s+|a\s+)?(image|visual|illustration)\b|\billustrate\b',
      caseSensitive: false,
    ).hasMatch(prompt);

    if (isImagePrompt) {
      if (_aiProvider != 'gemini' && _aiProvider != 'openai') {
        setState(() {
          _aiImageError = 'Image generation is available for Gemini or OpenAI.';
        });
        return;
      }
      setState(() {
        _aiMessages = [
          ..._aiMessages,
          {'role': 'user', 'content': prompt},
        ];
      });
      await _generateAiImage(prompt);
      return;
    }

    setState(() {
      _aiSending = true;
      _aiMessages = [
        ..._aiMessages,
        {'role': 'user', 'content': prompt},
      ];
    });

    final messages = [
      {
        'role': 'system',
        'content':
            'You help draft concise Markdown content for a knowledge graph note. Use clear headings, short paragraphs, and bullets when helpful.',
      },
      ..._aiMessages,
    ];

    final result = await _aiChatService.sendMessage(
      phone: phone,
      userId: userId,
      provider: _aiProvider,
      messages: messages,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final reply = (result['message'] ?? '').toString().trim();
      if (reply.isNotEmpty) {
        setState(() {
          _aiMessages = [
            ..._aiMessages,
            {'role': 'assistant', 'content': reply},
          ];
        });
      }
    } else {
      setState(() {
        _aiImageError = result['error'] ?? 'AI request failed';
      });
    }

    setState(() => _aiSending = false);

    if (_aiScrollController.hasClients) {
      _aiScrollController.animateTo(
        _aiScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _insertLatestAiMessage({bool append = true}) {
    final last = _aiMessages.lastWhere(
      (msg) => msg['role'] == 'assistant',
      orElse: () => {},
    );
    final content = (last['content'] ?? '').toString().trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No AI response to insert yet')),
      );
      return;
    }

    _insertAiMessageContent(content, append: append);
  }

  void _insertAiMessageContent(String content, {bool append = true}) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final insertText = append ? '\n\n$content' : content;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;

    final newText = text.substring(0, start) + insertText + text.substring(end);
    _contentController.text = newText;
    _contentController.selection = TextSelection.collapsed(
      offset: start + insertText.length,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Inserted into graph draft')));
  }

  Future<void> _generateAiImage(String prompt) async {
    setState(() {
      _aiImagePrompt = prompt;
      _aiImageGenerating = true;
      _aiImageError = '';
      _aiImageBytes = null;
      _aiImageUrl = null;
    });

    try {
      Uint8List? bytes;
      if (_aiProvider == 'gemini') {
        final model = FirebaseAI.vertexAI().imagenModel(
          model: 'imagen-3.0-generate-002',
          generationConfig: ImagenGenerationConfig(
            numberOfImages: 1,
            imageFormat: ImagenFormat.png(),
          ),
        );

        final response = await model.generateImages(prompt);
        if (!mounted) return;

        if (response.images.isEmpty) {
          setState(() {
            _aiImageError = 'No images were generated.';
            _aiImageGenerating = false;
          });
          return;
        }

        bytes = response.images.first.bytesBase64Encoded;
      } else if (_aiProvider == 'openai') {
        final userId = await _authService.getUserId();
        final result = await _aiChatService.generateOpenAiImage(
          prompt: prompt,
          userId: userId,
        );
        if (!mounted) return;
        if (result['success'] != true) {
          setState(() {
            _aiImageError = result['error'] ?? 'OpenAI image failed';
            _aiImageGenerating = false;
          });
          return;
        }
        bytes = result['bytes'] as Uint8List?;
      } else {
        setState(() {
          _aiImageError = 'Image generation is available for Gemini or OpenAI.';
          _aiImageGenerating = false;
        });
        return;
      }

      if (bytes == null) {
        setState(() {
          _aiImageError = 'No image bytes returned.';
          _aiImageGenerating = false;
        });
        return;
      }

      setState(() {
        _aiImageBytes = bytes;
      });

      final fileName = 'ai_image_${DateTime.now().millisecondsSinceEpoch}.png';
      final upload = await _knowledgeGraphService.uploadImage(
        bytes,
        fileName,
        'image/png',
      );

      if (!mounted) return;

      if (upload['success'] == true) {
        setState(() {
          _aiImageUrl = upload['url'];
          _aiImageGenerating = false;
        });
      } else {
        setState(() {
          _aiImageError = upload['error'] ?? 'Failed to upload image';
          _aiImageGenerating = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiImageError = 'Image generation failed: $e';
        _aiImageGenerating = false;
      });
    }
  }

  Future<String?> _promptForImageAnalysis() async {
    final controller = TextEditingController(
      text: 'Describe this image in detail.',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Analyze image'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'What should the assistant look for?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Analyze'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }

  Future<void> _analyzeAiImage() async {
    if (_aiProvider != 'openai') {
      setState(() {
        _aiImageAnalysisError = 'Image analysis is available only with OpenAI.';
      });
      return;
    }
    if (_aiImageAnalyzing) return;

    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.path == null) {
      setState(() {
        _aiImageAnalysisError = 'Unable to access the selected file.';
      });
      return;
    }

    final prompt = await _promptForImageAnalysis();
    if (prompt == null) return;

    setState(() {
      _aiImageAnalyzing = true;
      _aiImageAnalysisError = '';
      _aiMessages = [
        ..._aiMessages,
        {'role': 'user', 'content': 'Image analysis: $prompt'},
      ];
    });

    try {
      final userId = await _authService.getUserId();
      final bytes = await File(file.path!).readAsBytes();
      final mimeType = file.extension != null
          ? 'image/${file.extension!.toLowerCase()}'
          : 'image/png';
      final result = await _aiChatService.analyzeOpenAiImage(
        bytes: bytes,
        prompt: prompt,
        userId: userId,
        mimeType: mimeType,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        final reply = (result['message'] ?? '').toString().trim();
        if (reply.isNotEmpty) {
          setState(() {
            _aiMessages = [
              ..._aiMessages,
              {'role': 'assistant', 'content': reply},
            ];
          });
        }
      } else {
        setState(() {
          _aiImageAnalysisError = result['error'] ?? 'Image analysis failed';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiImageAnalysisError = 'Image analysis failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _aiImageAnalyzing = false);
      }
    }
  }

  Future<void> _transcribeAiAudio() async {
    if (_aiProvider != 'openai') {
      setState(() {
        _aiAudioError = 'Audio transcription is available only with OpenAI.';
      });
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3',
        'wav',
        'm4a',
        'aac',
        'ogg',
        'opus',
        'webm',
        'mp4',
        '3gp',
        'amr',
      ],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.path == null) {
      setState(() {
        _aiAudioError = 'Unable to access the selected file.';
      });
      return;
    }

    await _transcribeAiAudioPath(file.path!, file.name);
  }

  Future<void> _transcribeAiAudioPath(String path, String name) async {
    setState(() {
      _aiAudioTranscribing = true;
      _aiAudioError = '';
      _aiAudioText = '';
      _aiAudioFileName = name;
    });

    final userId = await _authService.getUserId();
    final result = await _aiChatService.transcribeOpenAiAudio(
      filePath: path,
      userId: userId,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _aiAudioText = result['text'] ?? '';
        _aiAudioTranscribing = false;
      });
    } else {
      setState(() {
        _aiAudioError = result['error'] ?? 'Transcription failed';
        _aiAudioTranscribing = false;
      });
    }
  }

  Future<void> _toggleAiRecording() async {
    if (_aiProvider != 'openai') {
      setState(() {
        _aiAudioError = 'Recording is available only with OpenAI.';
      });
      return;
    }
    if (_voiceRecording) {
      setState(() {
        _aiAudioError = 'Stop voice input recording first.';
      });
      return;
    }

    if (_aiRecording) {
      final path = await _recorder.stop();
      setState(() => _aiRecording = false);
      if (path != null && path.isNotEmpty) {
        await _transcribeAiAudioPath(path, 'Recording');
      } else {
        setState(() {
          _aiAudioError = 'Recording failed to save.';
        });
      }
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() {
        _aiAudioError = 'Microphone permission denied.';
      });
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    setState(() {
      _aiAudioError = '';
      _aiRecording = true;
    });
  }

  Future<void> _toggleAiVoiceRecording() async {
    if (_aiRecording) {
      setState(() {
        _voiceError = 'Stop the Tools recording first.';
      });
      return;
    }
    if (!_voiceRecording && _voiceDraftPath != null) {
      setState(() {
        _voiceError = 'Send or delete the draft first.';
      });
      return;
    }

    if (_voiceRecording) {
      final path = await _recorder.stop();
      setState(() => _voiceRecording = false);
      if (path != null && path.isNotEmpty) {
        final startedAt = _voiceRecordingStartedAt;
        final duration = startedAt != null
            ? DateTime.now().difference(startedAt).inMilliseconds
            : null;
        setState(() {
          _voiceRecordingStartedAt = null;
          _voiceDraftPath = path;
          _voiceDraftDurationMs = duration;
        });
      } else if (mounted) {
        setState(() {
          _voiceError = 'Recording failed to save.';
        });
      }
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      setState(() {
        _voiceError = 'Microphone permission denied.';
      });
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_ai_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    setState(() {
      _voiceError = '';
      _voiceRecording = true;
      _voiceRecordingStartedAt = DateTime.now();
      _voiceDraftPath = null;
      _voiceDraftDurationMs = null;
      _voiceDraftPlaying = false;
    });
  }

  Future<void> _sendAiVoiceDraft() async {
    final path = _voiceDraftPath;
    if (path == null || _voiceSending) return;
    final durationMs = _voiceDraftDurationMs;

    if (_voiceSending) return;

    await _voiceDraftPlayer.stop();
    if (!mounted) return;
    setState(() {
      _voiceDraftPlaying = false;
    });

    setState(() {
      _voiceSending = true;
      _voiceError = '';
    });

    try {
      final userId = await _authService.getUserId();
      final chatId = _graphId ?? userId ?? 'ai-assistant';
      final file = File(path);
      final bytes = await file.readAsBytes();
      final fileName = path.split('/').last;
      final uploadResult = await _voiceNoteService.uploadVoiceNote(
        chatId: chatId,
        bytes: bytes,
        fileName: fileName,
        contentType: 'audio/mp4',
      );
      final audioUrl = uploadResult['audioUrl']?.toString();
      final objectKey = uploadResult['objectKey']?.toString();
      final transcript = await _voiceNoteService.transcribe(
        audioUrl: audioUrl,
        objectKey: objectKey,
      );
      final text = transcript['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        throw Exception('No transcription text returned');
      }
      await _sendAiPrompt(text);
      if (!mounted) return;
      setState(() {
        _voiceDraftPath = null;
        _voiceDraftDurationMs = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceError = 'Voice input failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _voiceSending = false);
      }
    }
  }

  void _discardAiVoiceDraft() {
    setState(() {
      _voiceDraftPath = null;
      _voiceDraftDurationMs = null;
      _voiceDraftPlaying = false;
    });
    _voiceDraftPlayer.stop();
  }

  Future<void> _toggleAiVoiceDraftPlayback() async {
    final path = _voiceDraftPath;
    if (path == null) return;

    if (_voiceDraftPlaying) {
      await _voiceDraftPlayer.pause();
      if (!mounted) return;
      setState(() => _voiceDraftPlaying = false);
      return;
    }

    await _voiceDraftPlayer.stop();
    await _voiceDraftPlayer.play(DeviceFileSource(path));
    if (!mounted) return;
    setState(() => _voiceDraftPlaying = true);
  }

  String _formatDuration(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return '0:00';
    final totalSeconds = (durationMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }

  void _insertImageMarkdown(String url, String altText) {
    final safeAlt = altText.isNotEmpty ? altText : 'ai-image';
    final markdownImage = '![$safeAlt]($url)';

    final text = _contentController.text;
    final selection = _contentController.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText =
        '${text.substring(0, start)}$markdownImage\n${text.substring(end)}';

    _contentController.text = newText;
    _contentController.selection = TextSelection.collapsed(
      offset: start + markdownImage.length + 1,
    );
  }

  Future<void> _updateGraph() async {
    if (_graphId == null) return;

    final phone = await _authService.getPhone();
    final userId = await _authService.getUserId();

    if (phone == null || phone.isEmpty) {
      setState(() {
        _error = 'Not logged in. Please log in again.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });

    final result = await _knowledgeGraphService.updateGraph(
      phone: phone,
      userId: userId,
      graphId: _graphId!,
      title: _titleController.text.trim().isEmpty
          ? (_graphTitle ?? 'Untitled')
          : _titleController.text.trim(),
      content: _contentController.text.trim(),
      youtubeUrl: _youtubeUrl,
      publicEdit: _publicEdit,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Graph updated')));
    } else {
      setState(() {
        _error = result['error'] ?? 'Failed to update graph';
      });
    }

    setState(() => _saving = false);
  }

  Future<void> _openGraphInBrowser() async {
    if (_graphId == null) return;
    final url = Uri.parse(KnowledgeGraphService.buildPublicGraphUrl(_graphId!));
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Widget _buildAiPanel() {
    if (!_enableAiChat) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Enable AI Assistant in Settings to chat while editing.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AI Assistant',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: _aiMessages.isEmpty
                ? Center(
                    child: Text(
                      'Ask the AI to draft your content...',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    controller: _aiScrollController,
                    itemCount: _aiMessages.length,
                    itemBuilder: (context, index) {
                      final msg = _aiMessages[index];
                      final isUser = msg['role'] == 'user';
                      final content = msg['content'] ?? '';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(maxWidth: 320),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.black87 : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                content,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isUser ? Colors.white : Colors.black87,
                                ),
                              ),
                              if (!isUser && content.trim().isNotEmpty)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () =>
                                        _insertAiMessageContent(content),
                                    child: const Text('Insert into graph'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_aiImageError.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _aiImageError,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ],
          if (_aiImageAnalysisError.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _aiImageAnalysisError,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ],
          if (_voiceError.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _voiceError,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: _voiceSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _voiceRecording ? Icons.stop_circle : Icons.mic,
                        color: _voiceRecording ? Colors.redAccent : null,
                      ),
                onPressed: _voiceSending || _aiSending
                    ? null
                    : _toggleAiVoiceRecording,
                tooltip: _voiceRecording
                    ? 'Stop recording'
                    : 'Record voice message',
              ),
              Expanded(
                child: TextField(
                  controller: _aiInputController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendAiMessage(),
                  decoration: InputDecoration(
                    hintText: 'Message the AI…',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  enabled: !_aiSending,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _aiSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                onPressed: _aiSending ? null : _sendAiMessage,
              ),
            ],
          ),
          if (_voiceDraftPath != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _voiceDraftPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: _voiceSending
                        ? null
                        : _toggleAiVoiceDraftPlayback,
                  ),
                  Text(_formatDuration(_voiceDraftDurationMs)),
                  const Spacer(),
                  TextButton(
                    onPressed: _voiceSending ? null : _discardAiVoiceDraft,
                    child: const Text('Delete'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _voiceSending ? null : _sendAiVoiceDraft,
                    child: const Text('Send'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('Tools'),
            childrenPadding: const EdgeInsets.only(top: 8, bottom: 12),
            children: [
              ListTile(
                title: const Text('AI Provider'),
                subtitle: Text(
                  _aiProvider == 'grok'
                      ? 'Grok (xAI)'
                      : _aiProvider == 'gemini'
                      ? 'Gemini (Firebase AI)'
                      : 'OpenAI (GPT)',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showProviderSheet,
              ),
              if (_aiProvider == 'openai')
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _aiImageAnalyzing ? null : _analyzeAiImage,
                        icon: _aiImageAnalyzing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.image_search),
                        label: Text(
                          _aiImageAnalyzing ? 'Analyzing...' : 'Analyze image',
                        ),
                      ),
                    ),
                  ],
                ),
              if (_aiProvider == 'gemini' || _aiProvider == 'openai')
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'Image generation: start a message with “create image…”, “illustrate…”, or “create a visual…”',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              if (_aiProvider == 'openai') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _aiAudioTranscribing
                            ? null
                            : _transcribeAiAudio,
                        icon: _aiAudioTranscribing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.mic_none),
                        label: Text(
                          _aiAudioTranscribing
                              ? 'Transcribing...'
                              : 'Transcribe audio',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _aiAudioTranscribing
                          ? null
                          : _toggleAiRecording,
                      icon: Icon(_aiRecording ? Icons.stop : Icons.mic),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _aiRecording
                            ? Colors.red.shade300
                            : null,
                      ),
                      label: Text(_aiRecording ? 'Stop' : 'Record'),
                    ),
                  ],
                ),
              ],
              if (_aiImageBytes != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _aiImageBytes!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _aiImageUrl == null
                      ? null
                      : () {
                          _insertImageMarkdown(
                            _aiImageUrl!,
                            _aiImagePrompt ?? '',
                          );
                        },
                  child: const Text('Insert image into content'),
                ),
              ],
              if (_aiAudioText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Text(
                    _aiAudioText,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _insertAiMessageContent(_aiAudioText),
                  child: const Text('Insert transcription into content'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: _graphId == null ? null : _openGraphInBrowser,
            tooltip: 'View in browser',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _graphId == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error.isNotEmpty ? _error : 'Select a graph first.'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => context.go('/my-graphs'),
                      child: const Text('Open My Graphs'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _graphTitle ?? 'Active Graph',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildAiPanel(),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _saving ? null : _updateGraph,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: const Color(0xFF4f6d7a),
                      foregroundColor: Colors.white,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save to Graph'),
                  ),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
