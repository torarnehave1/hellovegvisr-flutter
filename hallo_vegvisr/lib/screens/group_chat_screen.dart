import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:share_plus/share_plus.dart';
import '../services/auth_service.dart';
import '../services/group_chat_service.dart';
import '../services/voice_note_service.dart';

/// Cache for user profile images to avoid repeated API calls
class _UserProfileCache {
  static final Map<String, String?> _cache = {};
  static final Map<String, DateTime> _cacheTime = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  static String? get(String userId) => _cache[userId];

  static void set(String userId, String? imageUrl) {
    _cache[userId] = imageUrl;
    _cacheTime[userId] = DateTime.now();
  }

  static bool isExpired(String userId) {
    final time = _cacheTime[userId];
    if (time == null) return true;
    return DateTime.now().difference(time) > _cacheDuration;
  }

  static bool has(String userId) =>
      _cache.containsKey(userId) && !isExpired(userId);
}

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String? groupName;

  const GroupChatScreen({super.key, required this.groupId, this.groupName});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _authService = AuthService();
  final _chatService = GroupChatService();
  final _voiceNoteService = VoiceNoteService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final _draftPlayer = AudioPlayer();
  Timer? _pollTimer;

  String? _userId;
  String? _phone;
  String? _email;
  String? _groupImageUrl;
  int? _groupUpdatedAt;
  String? _myProfileImageUrl;
  bool _loading = true;
  bool _sending = false;
  bool _sendingVoice = false;
  bool _recording = false;
  DateTime? _recordingStartedAt;
  String? _pendingVoicePath;
  int? _pendingVoiceDurationMs;
  bool _isDraftPlaying = false;
  int _lastMessageId = 0;
  final List<Map<String, dynamic>> _messages = [];
  final Map<String, String?> _userProfileImages = {};
  final Set<int> _transcribingMessages = {};
  final Map<String, Duration> _audioDurations = {};
  String? _playingAudioUrl;
  bool _isPlayingAudio = false;
  final Set<int> _expandedVoiceMessages = {};

  String? _cacheBustedImageUrl(String? url, int? updatedAt) {
    if (url == null || url.isEmpty || updatedAt == null) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}v=$updatedAt';
  }

  @override
  void initState() {
    super.initState();
    _initChat();
    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlayingAudio = false;
        _playingAudioUrl = null;
      });
    });
    _draftPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _isDraftPlaying = false);
    });
    _audioPlayer.onDurationChanged.listen((duration) {
      final audioUrl = _playingAudioUrl;
      if (audioUrl == null || duration == Duration.zero) return;
      if (!mounted) return;
      setState(() {
        _audioDurations[audioUrl] = duration;
      });
    });
  }

  Future<void> _initChat() async {
    final userId = await _authService.getUserId();
    final phone = await _authService.getPhone();
    final email = await _authService.getEmail();
    final profileImageUrl = await _authService.getProfileImageUrl();
    setState(() {
      _userId = userId;
      _phone = phone;
      _email = email;
      _myProfileImageUrl = profileImageUrl;
    });

    // Cache my own profile image
    if (userId != null) {
      _userProfileImages[userId] = profileImageUrl;
      _UserProfileCache.set(userId, profileImageUrl);
    }

    await _loadGroupInfo();
    await _loadMessages();
    _startPolling();
  }

  Future<void> _loadGroupInfo() async {
    if (_userId == null || _phone == null) return;

    try {
      final group = await _chatService.fetchGroup(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
      );

      if (group != null && mounted) {
        setState(() {
          _groupImageUrl = group['image_url'] as String?;
          _groupUpdatedAt = group['updated_at'] as int?;
        });
      }
    } catch (_) {
      // Ignore - image is optional
    }
  }

  Future<void> _loadMessages() async {
    if (_userId == null || _phone == null) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final messages = await _chatService.fetchMessages(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
        after: 0,
        latest: true,
        limit: 100,
      );
      _messages
        ..clear()
        ..addAll(messages);
      if (_messages.isNotEmpty) {
        _lastMessageId = _messages.last['id'] as int;
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load messages: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollMessages();
    });
  }

  Future<void> _pollMessages() async {
    if (_userId == null || _phone == null) {
      return;
    }

    try {
      final messages = await _chatService.fetchMessages(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
        after: _lastMessageId,
      );
      if (messages.isNotEmpty) {
        // Get existing message IDs to prevent duplicates
        final existingIds = _messages.map((m) => m['id']).toSet();
        final newMessages = <Map<String, dynamic>>[];
        for (final message in messages) {
          final messageId = message['id'];
          if (existingIds.contains(messageId)) {
            continue;
          }
          final audioUrl = message['audio_url']?.toString() ?? '';
          if (audioUrl.isNotEmpty) {
            final existingIndex = _messages.indexWhere(
              (m) => (m['audio_url']?.toString() ?? '') == audioUrl,
            );
            if (existingIndex != -1) {
              _messages[existingIndex] = {
                ..._messages[existingIndex],
                ...message,
              };
              continue;
            }
          }
          newMessages.add(message);
        }

        if (newMessages.isNotEmpty) {
          setState(() {
            _messages.addAll(newMessages);
            _lastMessageId = _messages.last['id'] as int;
          });
          _scrollToBottom();
        }
      }
    } catch (_) {
      // Ignore polling errors to avoid UI spam.
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }
    if (_userId == null || _phone == null) {
      return;
    }
    // Prevent double-tap sending
    if (_sending) {
      return;
    }

    setState(() => _sending = true);
    _messageController.clear();
    try {
      final message = await _chatService.sendMessage(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
        body: text,
      );
      setState(() {
        _messages.add(message);
        _lastMessageId = message['id'] as int;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path != null && path.isNotEmpty) {
        final startedAt = _recordingStartedAt;
        final duration = startedAt != null
            ? DateTime.now().difference(startedAt).inMilliseconds
            : null;
        if (!mounted) return;
        setState(() {
          _pendingVoicePath = path;
          _pendingVoiceDurationMs = duration;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording failed to save')),
        );
      }
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _draftPlayer.stop();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    setState(() {
      _recording = true;
      _recordingStartedAt = DateTime.now();
      _pendingVoicePath = null;
      _pendingVoiceDurationMs = null;
      _isDraftPlaying = false;
    });
  }

  Future<void> _sendVoiceMessageFromPath(String path, {int? durationMs}) async {
    if (_userId == null || _phone == null) {
      return;
    }
    if (_sendingVoice) {
      return;
    }

    _draftPlayer.stop();
    setState(() {
      _sendingVoice = true;
      _isDraftPlaying = false;
    });
    try {
      final tempId = -DateTime.now().millisecondsSinceEpoch;
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      final tempMessage = {
        'id': tempId,
        'group_id': widget.groupId,
        'user_id': _userId,
        'body': '',
        'created_at': createdAt,
        'message_type': 'voice',
        'audio_url': '',
        'audio_duration_ms': durationMs,
        'transcript_text': null,
        'transcript_lang': null,
        'transcription_status': 'uploading',
      };
      setState(() {
        _messages.add(tempMessage);
      });
      _scrollToBottom();

      final file = File(path);
      final bytes = await file.readAsBytes();
      final fileName = path.split('/').last;
      final uploadResult = await _voiceNoteService.uploadVoiceNote(
        chatId: widget.groupId,
        bytes: bytes,
        fileName: fileName,
        contentType: 'audio/mp4',
      );
      final audioUrl = uploadResult['audioUrl']?.toString() ?? '';
      if (audioUrl.isEmpty) {
        throw Exception('Missing audio URL from upload');
      }
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == tempId);
        if (index != -1) {
          _messages[index] = {
            ..._messages[index],
            'audio_url': audioUrl,
            'transcription_status': 'uploading',
          };
        }
      });

      final message = await _chatService.sendVoiceMessage(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
        audioUrl: audioUrl,
        audioDurationMs: durationMs,
        transcriptionStatus: 'none',
      );
      setState(() {
        _messages.removeWhere(
          (m) => (m['audio_url']?.toString() ?? '') == audioUrl,
        );
        final index = _messages.indexWhere((m) => m['id'] == tempId);
        if (index != -1) {
          _messages[index] = message;
        } else {
          _messages.add(message);
        }
        _lastMessageId = message['id'] as int;
        _pendingVoicePath = null;
        _pendingVoiceDurationMs = null;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.removeWhere((m) => (m['id'] is int) && (m['id'] as int) < 0);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingVoice = false);
      }
    }
  }

  void _discardPendingVoice() {
    setState(() {
      _pendingVoicePath = null;
      _pendingVoiceDurationMs = null;
      _recordingStartedAt = null;
      _isDraftPlaying = false;
    });
    _draftPlayer.stop();
  }

  Future<void> _togglePlayback(String audioUrl) async {
    if (audioUrl.isEmpty) return;

    if (_playingAudioUrl == audioUrl && _isPlayingAudio) {
      await _audioPlayer.pause();
      if (!mounted) return;
      setState(() => _isPlayingAudio = false);
      return;
    }

    await _audioPlayer.stop();
    await _audioPlayer.play(UrlSource(audioUrl));
    if (!mounted) return;
    setState(() {
      _playingAudioUrl = audioUrl;
      _isPlayingAudio = true;
    });
  }

  Future<void> _toggleDraftPlayback() async {
    final path = _pendingVoicePath;
    if (path == null) return;

    if (_isDraftPlaying) {
      await _draftPlayer.pause();
      if (!mounted) return;
      setState(() => _isDraftPlaying = false);
      return;
    }

    await _draftPlayer.stop();
    await _draftPlayer.play(DeviceFileSource(path));
    if (!mounted) return;
    setState(() => _isDraftPlaying = true);
  }

  Future<File?> _downloadVoiceToDocuments(
    String audioUrl, {
    String? fileName,
  }) async {
    if (audioUrl.isEmpty) return null;
    final dir = await getApplicationDocumentsDirectory();
    final safeName = (fileName?.isNotEmpty == true ? fileName! : 'voice-note')
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final filePath = '${dir.path}/$safeName';
    final file = File(filePath);
    if (await file.exists()) {
      return file;
    }

    final response = await http.get(Uri.parse(audioUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download audio (${response.statusCode})');
    }
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  Future<void> _downloadVoiceMessage(Map<String, dynamic> message) async {
    final audioUrl = message['audio_url']?.toString() ?? '';
    if (audioUrl.isEmpty) return;
    final messageId = message['id']?.toString() ?? 'voice';
    final fileName = 'voice-$messageId.m4a';
    try {
      final file = await _downloadVoiceToDocuments(
        audioUrl,
        fileName: fileName,
      );
      if (!mounted) return;
      if (file != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Future<void> _shareVoiceMessage(Map<String, dynamic> message) async {
    final audioUrl = message['audio_url']?.toString() ?? '';
    if (audioUrl.isEmpty) return;
    final messageId = message['id']?.toString() ?? 'voice';
    final fileName = 'voice-$messageId.m4a';
    try {
      final file = await _downloadVoiceToDocuments(
        audioUrl,
        fileName: fileName,
      );
      if (file == null) return;
      await Share.shareXFiles([XFile(file.path)], text: 'Voice message');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _transcribeVoiceMessage(Map<String, dynamic> message) async {
    final id = message['id'];
    if (id is! int) return;
    if (_transcribingMessages.contains(id)) return;

    final audioUrl = message['audio_url']?.toString() ?? '';
    if (audioUrl.isEmpty) return;

    setState(() {
      _transcribingMessages.add(id);
    });

    try {
      final result = await _voiceNoteService.transcribe(audioUrl: audioUrl);
      final transcriptText = result['text']?.toString() ?? '';
      final transcriptLang = result['language']?.toString();
      final updated = await _chatService.updateMessageTranscript(
        groupId: widget.groupId,
        messageId: id,
        userId: _userId ?? '',
        phone: _phone ?? '',
        email: _email,
        transcriptText: transcriptText,
        transcriptLang: transcriptLang,
        transcriptionStatus: 'complete',
      );
      _replaceMessage(updated);
    } catch (e) {
      if (_userId != null && _phone != null) {
        try {
          await _chatService.updateMessageTranscript(
            groupId: widget.groupId,
            messageId: id,
            userId: _userId!,
            phone: _phone!,
            email: _email,
            transcriptionStatus: 'failed',
          );
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Transcription failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _transcribingMessages.remove(id);
        });
      }
    }
  }

  void _replaceMessage(Map<String, dynamic> updated) {
    final id = updated['id'];
    if (id is! int) return;
    final index = _messages.indexWhere((m) => m['id'] == id);
    if (index == -1) return;
    setState(() {
      _messages[index] = {..._messages[index], ...updated};
    });
  }

  void _toggleVoiceExpanded(int id) {
    setState(() {
      if (_expandedVoiceMessages.contains(id)) {
        _expandedVoiceMessages.remove(id);
      } else {
        _expandedVoiceMessages.add(id);
      }
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Load profile image for a user (with caching)
  Future<void> _loadUserProfileImage(String userId) async {
    // Check local cache first
    if (_userProfileImages.containsKey(userId)) return;

    // Check global cache
    if (_UserProfileCache.has(userId)) {
      setState(() {
        _userProfileImages[userId] = _UserProfileCache.get(userId);
      });
      return;
    }

    // Fetch from server
    try {
      final imageUrl = await _authService.getUserProfileImage(userId);
      _UserProfileCache.set(userId, imageUrl);
      if (mounted) {
        setState(() {
          _userProfileImages[userId] = imageUrl;
        });
      }
    } catch (_) {
      // Ignore errors - just don't show image
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    _draftPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4f6d7a),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Check if we can pop, otherwise go to home
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: GestureDetector(
          onTap: () => context.push(
            '/group-info/${widget.groupId}',
            extra: widget.groupName,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                backgroundImage: _groupImageUrl != null
                    ? NetworkImage(
                        _cacheBustedImageUrl(
                          _groupImageUrl,
                          _groupUpdatedAt,
                        )!,
                      )
                    : null,
                child: _groupImageUrl == null
                    ? Text(
                        (widget.groupName ?? 'G')[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.groupName ?? 'Group Chat',
                      style: const TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'tap for info',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[_messages.length - 1 - index];
                      final isMine = message['user_id'] == _userId;
                      return _buildMessageBubble(message, isMine);
                    },
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMine) {
    final text = message['body']?.toString() ?? '';
    final messageType =
        message['message_type']?.toString() ??
        message['type']?.toString() ??
        'text';
    final messageUserId = message['user_id']?.toString();
    final baseStyle = TextStyle(color: isMine ? Colors.white : Colors.black87);
    final linkStyle = baseStyle.copyWith(
      color: isMine ? Colors.lightBlueAccent : Colors.blueAccent,
      decoration: TextDecoration.underline,
    );

    // Load profile image for other users
    if (!isMine &&
        messageUserId != null &&
        !_userProfileImages.containsKey(messageUserId)) {
      _loadUserProfileImage(messageUserId);
    }

    // Get profile image URL for this message's sender
    final profileImageUrl = messageUserId != null
        ? _userProfileImages[messageUserId]
        : null;

    // Get initials from email or phone for fallback avatar
    String getInitials() {
      final email = message['email']?.toString();
      final phone = message['phone']?.toString();
      if (email != null && email.isNotEmpty) {
        final parts = email.split('@')[0].split('.');
        if (parts.length >= 2) {
          return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
        }
        return email[0].toUpperCase();
      }
      if (phone != null && phone.length >= 2) {
        return phone.substring(phone.length - 2);
      }
      return '?';
    }

    final messageContent =
        messageType == 'voice' || message['audio_url'] != null
        ? _buildVoiceContent(message, isMine)
        : RichText(
            text: TextSpan(
              style: baseStyle,
              children: _buildMessageSpans(text, linkStyle),
            ),
          );

    final messageBubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: isMine ? const Color(0xFF4f6d7a) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: messageContent,
    );

    // For my messages, just show the bubble aligned right
    if (isMine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: messageBubble,
        ),
      );
    }

    // For other users' messages, show avatar + bubble
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // User avatar
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF4f6d7a).withValues(alpha: 0.3),
            backgroundImage: profileImageUrl != null
                ? NetworkImage(profileImageUrl)
                : null,
            child: profileImageUrl == null
                ? Text(
                    getInitials(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4f6d7a),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          // Message bubble
          Flexible(child: messageBubble),
        ],
      ),
    );
  }

  Widget _buildVoiceContent(Map<String, dynamic> message, bool isMine) {
    final audioUrl = message['audio_url']?.toString() ?? '';
    final transcriptText = message['transcript_text']?.toString() ?? '';
    final transcriptionStatus =
        message['transcription_status']?.toString() ?? '';
    final id = message['id'];
    final messageId = id is int ? id : null;
    final isExpanded =
        messageId != null && _expandedVoiceMessages.contains(messageId);
    final isPlaying =
        audioUrl.isNotEmpty && _playingAudioUrl == audioUrl && _isPlayingAudio;
    final canTranscribe =
        transcriptText.isEmpty &&
        audioUrl.isNotEmpty &&
        id is int &&
        !_transcribingMessages.contains(id);
    final textColor = isMine ? Colors.white : Colors.black87;
    final subTextColor = isMine ? Colors.white70 : Colors.black54;
    final label = transcriptText.isNotEmpty ? transcriptText : 'Voice message';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_circle : Icons.play_circle,
                color: textColor,
              ),
              onPressed: audioUrl.isEmpty
                  ? null
                  : () => _togglePlayback(audioUrl),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                onTap: messageId == null
                    ? null
                    : () => _toggleVoiceExpanded(messageId),
                child: Text(
                  label,
                  style: TextStyle(color: textColor),
                  maxLines: isExpanded ? null : 2,
                  overflow: isExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        if (audioUrl.isEmpty && transcriptionStatus == 'uploading')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Uploading voice message...',
              style: TextStyle(color: subTextColor, fontSize: 12),
            ),
          ),
        if (transcriptionStatus == 'failed' && transcriptText.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Transcription failed',
              style: TextStyle(color: subTextColor, fontSize: 12),
            ),
          ),
        if (audioUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: () => _shareVoiceMessage(message),
                  icon: Icon(
                    Icons.share_outlined,
                    size: 16,
                    color: subTextColor,
                  ),
                  label: Text('Share', style: TextStyle(color: subTextColor)),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        if (canTranscribe)
          TextButton.icon(
            onPressed: () => _transcribeVoiceMessage(message),
            icon: Icon(
              Icons.text_snippet_outlined,
              size: 16,
              color: subTextColor,
            ),
            label: Text('Transcribe', style: TextStyle(color: subTextColor)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.only(top: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        if (!canTranscribe && _transcribingMessages.contains(id))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 12,
                  width: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: subTextColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Transcribing...',
                  style: TextStyle(color: subTextColor, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<TextSpan> _buildMessageSpans(String text, TextStyle linkStyle) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'(https?://[^\s]+)');
    int lastIndex = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      final url = match.group(0) ?? '';
      spans.add(
        TextSpan(
          text: url,
          style: linkStyle,
          recognizer: TapGestureRecognizer()..onTap = () => _openLink(url),
        ),
      );
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }

    return spans;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final secondsStr = seconds.toString().padLeft(2, '0');
    return '$minutes:$secondsStr';
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open link')));
    }
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.emoji_emotions_outlined, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: _pendingVoicePath == null
                  ? TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    )
                  : Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isDraftPlaying
                                ? Icons.pause_circle
                                : Icons.play_circle,
                            color: Colors.grey,
                          ),
                          onPressed: _toggleDraftPlayback,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.mic,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _pendingVoiceDurationMs == null
                                ? 'Voice message ready'
                                : 'Voice message · ${_formatDuration(Duration(milliseconds: _pendingVoiceDurationMs!))}',
                            style: const TextStyle(color: Colors.black87),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.grey,
                          ),
                          onPressed: _discardPendingVoice,
                        ),
                      ],
                    ),
            ),
            if (_sendingVoice)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: Icon(
                  _recording ? Icons.stop_circle : Icons.mic,
                  color: _recording ? Colors.redAccent : Colors.grey,
                ),
                onPressed: _toggleVoiceRecording,
              ),
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFF4f6d7a)),
              onPressed: () {
                if (_pendingVoicePath != null) {
                  _sendVoiceMessageFromPath(
                    _pendingVoicePath!,
                    durationMs: _pendingVoiceDurationMs,
                  );
                } else {
                  _sendMessage();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
