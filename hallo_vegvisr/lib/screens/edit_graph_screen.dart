import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/knowledge_graph_service.dart';
import '../services/auth_service.dart';
import '../services/ai_chat_service.dart';

class EditGraphScreen extends StatefulWidget {
  final String graphId;

  const EditGraphScreen({super.key, required this.graphId});

  @override
  State<EditGraphScreen> createState() => _EditGraphScreenState();
}

class _EditGraphScreenState extends State<EditGraphScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _knowledgeGraphService = KnowledgeGraphService();
  final _authService = AuthService();
  final _imagePicker = ImagePicker();
  final _aiChatService = AiChatService();
  final _aiInputController = TextEditingController();
  final _aiScrollController = ScrollController();
  final _recorder = AudioRecorder();

  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String _error = '';
  String _aiError = '';
  String? _youtubeUrl;
  Map<String, dynamic>? _result;
  bool _publicEdit = false;

  // AI Chat settings
  bool _enableAiChat = true;
  String _aiProvider = 'grok';
  List<Map<String, String>> _aiMessages = [];
  bool _aiSending = false;
  bool _aiImageGenerating = false;
  String _aiImageError = '';
  Uint8List? _aiImageBytes;
  String? _aiImageUrl;
  bool _aiAudioTranscribing = false;
  String _aiAudioError = '';
  String _aiAudioText = '';
  String _aiAudioFileName = '';
  bool _aiRecording = false;

  @override
  void initState() {
    super.initState();
    _loadGraph();
    _loadAiPreferences();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _youtubeController.dispose();
    _aiInputController.dispose();
    _aiScrollController.dispose();
    _recorder.dispose();
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

  Future<void> _loadGraph() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final phone = await _authService.getPhone();
    final userId = await _authService.getUserId();

    if (phone == null || phone.isEmpty) {
      setState(() {
        _error = 'Not logged in. Please log in again.';
        _loading = false;
      });
      return;
    }

    final result = await _knowledgeGraphService.getGraph(
      phone: phone,
      userId: userId,
      graphId: widget.graphId,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final graph = result['graph'] as Map<String, dynamic>;
      debugPrint('[GetGraph] loaded graph keys=${graph.keys.toList()}');

      // Parse content - remove the footer metadata if present
      String content = graph['content'] ?? '';
      final footerIndex = content.lastIndexOf('\n\n---\n\n*Created by:');
      if (footerIndex > 0) {
        content = content.substring(0, footerIndex);
      }

      setState(() {
        _titleController.text = graph['title'] ?? '';
        _contentController.text = content;
        _youtubeUrl = graph['youtubeUrl'];
        _publicEdit = graph['publicEdit'] == true;
        if (_youtubeUrl != null) {
          _youtubeController.text = _youtubeUrl!;
        }
        _loading = false;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_graph_id', widget.graphId);
      await prefs.setString('active_graph_title', graph['title'] ?? '');
    } else {
      setState(() {
        _error = result['error'] ?? 'Failed to load graph';
        _loading = false;
      });
    }
  }

  Future<void> _sendAiMessage() async {
    final prompt = _aiInputController.text.trim();
    if (prompt.isEmpty || _aiSending) return;

    final phone = await _authService.getPhone();
    final userId = await _authService.getUserId();

    if (phone == null || phone.isEmpty) {
      setState(() {
        _aiError = 'Not logged in. Please log in again.';
      });
      return;
    }

    setState(() {
      _aiSending = true;
      _aiError = '';
      _aiMessages = [
        ..._aiMessages,
        {'role': 'user', 'content': prompt},
      ];
      _aiInputController.clear();
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
        _aiError = result['error'] ?? 'AI request failed';
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
  }

  Future<void> _generateAiImage() async {
    final prompt = _aiInputController.text.trim();
    if (prompt.isEmpty) {
      setState(() {
        _aiImageError = 'Type a prompt to generate an image.';
      });
      return;
    }

    setState(() {
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
      } else if (_aiProvider == 'grok') {
        final userId = await _authService.getUserId();
        final result = await _aiChatService.generateGrokImage(
          prompt: prompt,
          userId: userId,
        );
        if (!mounted) return;
        if (result['success'] != true) {
          setState(() {
            _aiImageError = result['error'] ?? 'Grok image failed';
            _aiImageGenerating = false;
          });
          return;
        }
        bytes = result['bytes'] as Uint8List?;
      } else {
        setState(() {
          _aiImageError =
              'Image generation is available for Gemini, OpenAI, or Grok.';
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

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _uploading = true;
        _error = '';
      });

      final bytes = await image.readAsBytes();
      final result = await _knowledgeGraphService.uploadImage(
        bytes,
        image.name,
        'image/${image.name.split('.').last}',
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final imageUrl = result['url'];
        final altText = image.name.replaceAll(RegExp(r'\.[^/.]+$'), '');
        final markdownImage = '![$altText]($imageUrl)';

        final text = _contentController.text;
        final selection = _contentController.selection;
        final start = selection.start >= 0 ? selection.start : text.length;
        final end = selection.end >= 0 ? selection.end : text.length;
        final safeStart = start <= end ? start : end;
        final safeEnd = start <= end ? end : start;
        final newText =
            '${text.substring(0, safeStart)}$markdownImage\n${text.substring(safeEnd)}';

        _contentController.text = newText;
        _contentController.selection = TextSelection.collapsed(
          offset: safeStart + markdownImage.length + 1,
        );

        setState(() => _uploading = false);
      } else {
        setState(() {
          _error = result['error'] ?? 'Failed to upload image';
          _uploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error picking image: $e';
        _uploading = false;
      });
    }
  }

  void _addYouTubeVideo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add YouTube Video'),
        content: TextField(
          controller: _youtubeController,
          decoration: const InputDecoration(
            hintText: 'Enter YouTube URL',
            labelText: 'YouTube URL',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = _youtubeController.text.trim();
              final normalizedUrl = _knowledgeGraphService.normalizeYouTubeUrl(
                url,
              );

              if (normalizedUrl != null) {
                setState(() {
                  _youtubeUrl = normalizedUrl;
                  _error = '';
                });
                Navigator.pop(context);
              } else {
                setState(() {
                  _error = 'Invalid YouTube URL';
                });
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _removeYouTubeVideo() {
    setState(() {
      _youtubeUrl = null;
      _youtubeController.clear();
    });
  }

  Future<void> _confirmClearContent() async {
    if (_contentController.text.trim().isEmpty) {
      return;
    }
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear content?'),
        content: const Text(
          'This removes the current content from the editor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (shouldClear == true && mounted) {
      setState(() {
        _contentController.clear();
      });
    }
  }

  Future<void> _updateGraph() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a title');
      return;
    }
    if (_contentController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter some content');
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
      _result = null;
    });

    final phone = await _authService.getPhone();
    final userId = await _authService.getUserId();

    if (phone == null || phone.isEmpty) {
      setState(() {
        _error = 'Not logged in. Please log in again.';
        _saving = false;
      });
      return;
    }

    final result = await _knowledgeGraphService.updateGraph(
      phone: phone,
      userId: userId,
      graphId: widget.graphId,
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      youtubeUrl: _youtubeUrl,
      publicEdit: _publicEdit,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _result = result;
        _saving = false;
      });
    } else {
      setState(() {
        _error = result['error'] ?? 'Failed to update';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Graph'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: 'Open AI Assistant',
            onPressed: () =>
                context.push('/graph-ai?graphId=${widget.graphId}'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title field
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Document Title',
                      hintText: 'Enter document title...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    enabled: !_saving,
                  ),
                  const SizedBox(height: 16),

                  // Toolbar
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: (_uploading || _saving)
                            ? null
                            : _pickAndUploadImage,
                        icon: _uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.image),
                        label: Text(_uploading ? 'Uploading...' : 'Add Image'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _addYouTubeVideo,
                        icon: const Icon(
                          Icons.play_circle_fill,
                          color: Colors.red,
                        ),
                        label: const Text('Add YouTube'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // YouTube indicator
                  if (_youtubeUrl != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.play_circle_fill, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _youtubeUrl!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _removeYouTubeVideo,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Content field
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: (_saving || _uploading)
                          ? null
                          : _confirmClearContent,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear content'),
                    ),
                  ),
                  TextField(
                    controller: _contentController,
                    decoration: InputDecoration(
                      labelText: 'Content (Markdown)',
                      hintText: 'Write your markdown content here...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    maxLines: 12,
                    enabled: !_saving && !_uploading,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Supports Markdown: **bold**, *italic*, # headings, - lists, ```code blocks```, ![alt](url) for images',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.smart_toy_outlined),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'AI Assistant is now available in its own screen.',
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push(
                            '/graph-ai?graphId=${widget.graphId}',
                          ),
                          child: const Text('Open'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Public edit'),
                    subtitle: const Text(
                      'Anyone with the link can edit this graph',
                    ),
                    value: _publicEdit,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _publicEdit = value),
                  ),
                  const SizedBox(height: 8),

                  // Update button
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
                        : const Text('Update Graph'),
                  ),

                  // Error message
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

                  // Success result
                  if (_result != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Updated Successfully!',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Version: ${_result!['newVersion']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                final graphUrl =
                                    'https://www.vegvisr.org/gnew-viewer?graphId=${widget.graphId}';
                                final url = Uri.parse(graphUrl);
                                final messenger = ScaffoldMessenger.of(context);
                                launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                ).catchError((_) {
                                  Clipboard.setData(
                                    ClipboardData(text: graphUrl),
                                  );
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('URL copied to clipboard'),
                                    ),
                                  );
                                  return false;
                                });
                              },
                              child: const Text(
                                'View in Browser',
                                style: TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Bottom padding for scroll
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
