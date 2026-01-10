import 'dart:async';
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
import '../services/chat_history_service.dart';
import '../services/knowledge_graph_service.dart';
import '../services/voice_note_service.dart';

class GraphAiScreen extends StatefulWidget {
  final String? graphId;

  const GraphAiScreen({super.key, this.graphId});

  @override
  State<GraphAiScreen> createState() => _GraphAiScreenState();
}

class _RemoteChatSession {
  final String id;
  final String title;
  final String updatedAt;

  const _RemoteChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  static _RemoteChatSession fromJson(Map<String, dynamic> json) {
    return _RemoteChatSession(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled session').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
    );
  }
}

class _GraphAiScreenState extends State<GraphAiScreen> {
  final _authService = AuthService();
  final _knowledgeGraphService = KnowledgeGraphService();
  final _aiChatService = AiChatService();
  final _chatHistoryService = ChatHistoryService();
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

  String _lastSavedTitle = '';
  String _lastSavedContent = '';

  bool _enableAiChat = true;
  String _aiProvider = 'grok';
  List<Map<String, String>> _aiMessages = [];
  bool _aiSending = false;
  // ignore: unused_field
  bool _aiImageGenerating = false;
  String _aiImageError = '';
  Uint8List? _aiImageBytes;
  String? _aiImageUrl;
  String? _aiImagePrompt;
  bool _aiImageAnalyzing = false;
  String _aiImageAnalysisError = '';
  bool _aiAudioTranscribing = false;
  // ignore: unused_field
  String _aiAudioError = '';
  String _aiAudioText = '';
  // ignore: unused_field
  String _aiAudioFileName = '';
  bool _aiRecording = false;
  bool _voiceRecording = false;
  bool _voiceSending = false;
  String _voiceError = '';
  DateTime? _voiceRecordingStartedAt;
  String? _voiceDraftPath;
  int? _voiceDraftDurationMs;
  bool _voiceDraftPlaying = false;

  List<_RemoteChatSession> _aiSessions = [];
  String? _activeAiSessionId;
  bool _aiSessionsLoading = false;
  String _aiSessionsError = '';

  Timer? _sessionsRefreshDebounce;
  bool _sessionsRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _loadAiPreferences();
    _loadActiveGraph();
  }

  String? _sessionsGraphId() {
    final id = _graphId;
    if (id == null || id.trim().isEmpty) return null;
    return id;
  }

  Future<Map<String, String>?> _historyAuth() async {
    final userId = await _authService.getUserId();
    if (userId == null || userId.trim().isEmpty) return null;
    final email = await _authService.getEmail();
    return {
      'userId': userId,
      'email': (email == null || email.trim().isEmpty)
          ? 'anonymous@vegvisr.org'
          : email,
      'role': 'User',
    };
  }

  String _activeSessionStorageKey({
    required String userId,
    required String graphId,
  }) {
    return 'graph_ai_active_session:$userId:$graphId';
  }

  Map<String, dynamic> _buildSessionMetadata() {
    return {'graphTitle': _graphTitle ?? 'Untitled Graph'};
  }

  String _formatSessionTimestamp(String isoString) {
    if (isoString.trim().isEmpty) return 'No activity yet';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final sameDay =
          dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      if (sameDay) return '$hh:$mm';
      return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hh:$mm';
    } catch (_) {
      return isoString;
    }
  }

  void _scheduleQuietSessionsRefresh() {
    _sessionsRefreshDebounce?.cancel();
    _sessionsRefreshDebounce = Timer(const Duration(milliseconds: 650), () {
      _fetchRemoteSessionsQuietly();
    });
  }

  Future<void> _fetchRemoteSessionsQuietly() async {
    if (_sessionsRefreshInFlight) return;
    final graphId = _sessionsGraphId();
    if (graphId == null) return;
    final auth = await _historyAuth();
    if (auth == null) return;

    _sessionsRefreshInFlight = true;
    try {
      final result = await _chatHistoryService.listSessions(
        userId: auth['userId']!,
        userEmail: auth['email']!,
        userRole: auth['role']!,
        graphId: graphId,
      );

      if (!mounted) return;
      if (result['success'] == true) {
        final raw = (result['sessions'] as List?) ?? const [];
        final sessions = <_RemoteChatSession>[];
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            sessions.add(_RemoteChatSession.fromJson(item));
          } else if (item is Map) {
            sessions.add(
              _RemoteChatSession.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }

        setState(() {
          _aiSessions = sessions;
          _aiSessionsError = '';
        });
      }
    } finally {
      _sessionsRefreshInFlight = false;
    }
  }

  Future<void> _fetchRemoteSessions() async {
    final graphId = _sessionsGraphId();
    if (graphId == null) return;
    final auth = await _historyAuth();
    if (auth == null) return;

    setState(() {
      _aiSessionsLoading = true;
      _aiSessionsError = '';
    });

    try {
      final result = await _chatHistoryService.listSessions(
        userId: auth['userId']!,
        userEmail: auth['email']!,
        userRole: auth['role']!,
        graphId: graphId,
      );

      if (!mounted) return;
      if (result['success'] == true) {
        final raw = (result['sessions'] as List?) ?? const [];
        final sessions = <_RemoteChatSession>[];
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            sessions.add(_RemoteChatSession.fromJson(item));
          } else if (item is Map) {
            sessions.add(
              _RemoteChatSession.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }

        setState(() {
          _aiSessions = sessions;
        });
      } else {
        setState(() {
          _aiSessionsError = (result['error'] ?? 'Failed to load sessions')
              .toString();
        });
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _aiSessionsLoading = false;
      });
    }
  }

  Future<void> _loadRemoteHistoryIfPossible() async {
    final graphId = _sessionsGraphId();
    if (graphId == null) return;
    final auth = await _historyAuth();
    if (auth == null) return;

    await _fetchRemoteSessions();

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(
      _activeSessionStorageKey(userId: auth['userId']!, graphId: graphId),
    );

    if (stored == null || stored.trim().isEmpty) {
      setState(() {
        _activeAiSessionId = null;
        _aiMessages = [];
      });
      return;
    }

    if (!_aiSessions.any((s) => s.id == stored)) {
      setState(() {
        _activeAiSessionId = null;
        _aiMessages = [];
      });
      return;
    }

    await _selectAiSession(stored);
  }

  Future<void> _ensureSessionForMessaging() async {
    if (_activeAiSessionId != null && _activeAiSessionId!.trim().isNotEmpty) {
      return;
    }
    final graphId = _sessionsGraphId();
    if (graphId == null) return;
    final auth = await _historyAuth();
    if (auth == null) return;

    final defaultTitle = _graphTitle ?? 'Graph Conversation';
    final created = await _chatHistoryService.upsertSession(
      userId: auth['userId']!,
      userEmail: auth['email']!,
      userRole: auth['role']!,
      graphId: graphId,
      provider: _aiProvider,
      metadata: _buildSessionMetadata(),
      title: defaultTitle,
    );

    if (!mounted) return;
    if (created['success'] == true && created['session'] != null) {
      final session = created['session'] as Map;
      final sessionId = (session['id'] ?? '').toString();
      if (sessionId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _activeSessionStorageKey(userId: auth['userId']!, graphId: graphId),
          sessionId,
        );

        setState(() {
          _activeAiSessionId = sessionId;
        });
        await _fetchRemoteSessions();
      }
    }
  }

  Future<void> _persistChatMessageRemote({
    required String role,
    required String content,
  }) async {
    final sessionId = _activeAiSessionId;
    if (sessionId == null || sessionId.trim().isEmpty) return;
    final auth = await _historyAuth();
    if (auth == null) return;

    final res = await _chatHistoryService.persistMessage(
      userId: auth['userId']!,
      userEmail: auth['email']!,
      userRole: auth['role']!,
      sessionId: sessionId,
      role: role,
      content: content,
      provider: role == 'assistant' ? _aiProvider : null,
    );

    if (res['success'] == true) {
      _scheduleQuietSessionsRefresh();
    }
  }

  Future<void> _startNewAiSession() async {
    final graphId = _sessionsGraphId();
    if (graphId == null) return;
    final auth = await _historyAuth();
    if (auth == null) return;

    setState(() {
      _aiSessionsLoading = true;
      _aiSessionsError = '';
      _aiMessages = [];
      _activeAiSessionId = null;
    });

    final created = await _chatHistoryService.upsertSession(
      userId: auth['userId']!,
      userEmail: auth['email']!,
      userRole: auth['role']!,
      graphId: graphId,
      provider: _aiProvider,
      metadata: _buildSessionMetadata(),
      title: _graphTitle ?? 'Graph Conversation',
    );

    if (!mounted) return;

    if (created['success'] == true && created['session'] != null) {
      final session = created['session'] as Map;
      final sessionId = (session['id'] ?? '').toString();
      if (sessionId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _activeSessionStorageKey(userId: auth['userId']!, graphId: graphId),
          sessionId,
        );
        setState(() {
          _activeAiSessionId = sessionId;
        });
      }
    } else {
      setState(() {
        _aiSessionsError = (created['error'] ?? 'Failed to create session')
            .toString();
      });
    }

    await _fetchRemoteSessions();
    if (!mounted) return;
    setState(() {
      _aiSessionsLoading = false;
    });
  }

  Future<void> _selectAiSession(String sessionId) async {
    final graphId = _sessionsGraphId();
    if (graphId == null) return;
    final auth = await _historyAuth();
    if (auth == null) return;

    setState(() {
      _aiSessionsLoading = true;
      _aiSessionsError = '';
      _activeAiSessionId = sessionId;
      _aiMessages = [];
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _activeSessionStorageKey(userId: auth['userId']!, graphId: graphId),
      sessionId,
    );

    final fetched = await _chatHistoryService.loadMessages(
      userId: auth['userId']!,
      userEmail: auth['email']!,
      userRole: auth['role']!,
      sessionId: sessionId,
      limit: 200,
      decrypt: true,
    );

    if (!mounted) return;

    if (fetched['success'] == true) {
      final raw = (fetched['messages'] as List?) ?? const [];
      final msgs = <Map<String, String>>[];
      for (final item in raw) {
        if (item is Map) {
          final role = item['role']?.toString() ?? '';
          final content = item['content']?.toString() ?? '';
          if (role.isNotEmpty && content.isNotEmpty) {
            msgs.add({'role': role, 'content': content});
          }
        }
      }
      setState(() {
        _aiMessages = msgs;
      });
    } else {
      setState(() {
        _aiSessionsError = (fetched['error'] ?? 'Failed to load chat history')
            .toString();
      });
    }

    setState(() {
      _aiSessionsLoading = false;
    });
  }

  Future<void> _renameAiSession(String sessionId, String title) async {
    final graphId = _sessionsGraphId();
    if (graphId == null) return;
    final auth = await _historyAuth();
    if (auth == null) return;

    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _aiSessionsLoading = true;
      _aiSessionsError = '';
    });

    final res = await _chatHistoryService.upsertSession(
      userId: auth['userId']!,
      userEmail: auth['email']!,
      userRole: auth['role']!,
      graphId: graphId,
      provider: _aiProvider,
      metadata: _buildSessionMetadata(),
      sessionId: sessionId,
      title: trimmed,
    );

    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _aiSessionsError = (res['error'] ?? 'Failed to rename session')
            .toString();
      });
    }

    await _fetchRemoteSessions();
    if (!mounted) return;
    setState(() {
      _aiSessionsLoading = false;
    });
  }

  Future<void> _deleteAiSession(String sessionId) async {
    final graphId = _sessionsGraphId();
    if (graphId == null) return;
    final auth = await _historyAuth();
    if (auth == null) return;

    setState(() {
      _aiSessionsLoading = true;
      _aiSessionsError = '';
    });

    final res = await _chatHistoryService.deleteSession(
      userId: auth['userId']!,
      userEmail: auth['email']!,
      userRole: auth['role']!,
      sessionId: sessionId,
    );

    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _aiSessionsError = (res['error'] ?? 'Failed to delete session')
            .toString();
      });
    } else {
      if (_activeAiSessionId == sessionId) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(
          _activeSessionStorageKey(userId: auth['userId']!, graphId: graphId),
        );
        setState(() {
          _activeAiSessionId = null;
          _aiMessages = [];
        });
      }
    }

    await _fetchRemoteSessions();
    if (!mounted) return;
    setState(() {
      _aiSessionsLoading = false;
    });
  }

  Future<void> _promptRenameSession(_RemoteChatSession session) async {
    final controller = TextEditingController(text: session.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Session name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter a session name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      await _renameAiSession(session.id, result);
    }
  }

  Future<void> _confirmDeleteSession(_RemoteChatSession session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete session?'),
          content: Text('Delete "${session.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await _deleteAiSession(session.id);
    }
  }

  void _showAiSessionsSheet() {
    if (_aiSessionsLoading) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'AI Sessions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _startNewAiSession();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('New'),
                    ),
                  ],
                ),
                if (_aiSessionsError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _aiSessionsError,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _aiSessions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final s = _aiSessions[index];
                      final isActive = s.id == _activeAiSessionId;
                      return ListTile(
                        title: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'Updated ${_formatSessionTimestamp(s.updatedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        leading: Icon(
                          isActive
                              ? Icons.check_circle
                              : Icons.chat_bubble_outline,
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          await _selectAiSession(s.id);
                        },
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              tooltip: 'Rename',
                              onPressed: () async {
                                Navigator.pop(context);
                                await _promptRenameSession(s);
                              },
                              icon: const Icon(Icons.edit),
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () async {
                                Navigator.pop(context);
                                await _confirmDeleteSession(s);
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _sessionsRefreshDebounce?.cancel();
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

      final loadedTitle =
          (graph['title'] ?? activeGraphTitle ?? 'Untitled graph').toString();
      final loadedContent = content;

      setState(() {
        _graphId = activeGraphId;
        _graphTitle = loadedTitle;
        _titleController.text = loadedTitle;
        _contentController.text = loadedContent;
        _youtubeUrl = graph['youtubeUrl'];
        _publicEdit = graph['publicEdit'] == true;
        _lastSavedTitle = loadedTitle.trim();
        _lastSavedContent = loadedContent.trim();
        _loading = false;
      });

      await _loadRemoteHistoryIfPossible();

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

  void _leaveAssistantAndOpenDrawer() {
    if (!mounted) return;
    context.go('/?openDrawer=true');
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

      await _ensureSessionForMessaging();
      await _persistChatMessageRemote(role: 'user', content: prompt);
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

    await _ensureSessionForMessaging();
    await _persistChatMessageRemote(role: 'user', content: prompt);

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
        await _persistChatMessageRemote(role: 'assistant', content: reply);
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

  // ignore: unused_element
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

    final nextTitle = _titleController.text.trim().isEmpty
        ? (_graphTitle ?? 'Untitled').trim()
        : _titleController.text.trim();
    final nextContent = _contentController.text.trim();

    if (nextTitle == _lastSavedTitle && nextContent == _lastSavedContent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No changes to save')));
      return;
    }

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
      title: nextTitle,
      content: nextContent,
      youtubeUrl: _youtubeUrl,
      publicEdit: _publicEdit,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      // Re-fetch once to ensure the backend actually persisted the update.
      final fetched = await _knowledgeGraphService.getGraph(
        phone: phone,
        userId: userId,
        graphId: _graphId!,
      );

      if (!mounted) return;

      if (fetched['success'] == true) {
        final graph = fetched['graph'] as Map<String, dynamic>;
        String fetchedContent = (graph['content'] ?? '').toString();
        final footerIndex = fetchedContent.lastIndexOf(
          '\n\n---\n\n*Created by:',
        );
        if (footerIndex > 0) {
          fetchedContent = fetchedContent.substring(0, footerIndex);
        }

        final fetchedTitle = (graph['title'] ?? '').toString().trim();
        final fetchedTrimmedContent = fetchedContent.trim();

        final matches =
            fetchedTitle == nextTitle && fetchedTrimmedContent == nextContent;

        if (!matches) {
          setState(() {
            _error =
                'Saved, but the graph did not refresh with the new content. Please try again.';
          });
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('active_graph_title', fetchedTitle);

          setState(() {
            _graphTitle = fetchedTitle;
            _titleController.text = fetchedTitle;
            _contentController.text = fetchedContent;
            _lastSavedTitle = fetchedTitle;
            _lastSavedContent = fetchedTrimmedContent;
          });

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Graph updated')));
        }
      } else {
        setState(() {
          _error =
              'Graph updated, but reloading failed: ${fetched['error'] ?? 'unknown error'}';
        });
      }
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'AI Assistant',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Chat sessions',
                onPressed: _sessionsGraphId() == null
                    ? null
                    : () async {
                        await _fetchRemoteSessions();
                        if (!mounted) return;
                        _showAiSessionsSheet();
                      },
                icon: const Icon(Icons.folder_open),
              ),
            ],
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
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
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
              const SizedBox(width: 4),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
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
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _leaveAssistantAndOpenDrawer();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _leaveAssistantAndOpenDrawer,
          ),
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
                      Text(
                        _error.isNotEmpty ? _error : 'Select a graph first.',
                      ),
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
      ),
    );
  }
}
