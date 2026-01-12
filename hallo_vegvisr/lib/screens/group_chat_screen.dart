import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../services/auth_service.dart';
import '../services/group_chat_service.dart';
import '../services/voice_note_service.dart';
import 'chat_media_viewer_screen.dart';

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
  static const int _initialMessageLimit = 10;
  static const bool _lightweightChatView = true;

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
  bool _loading = true;
  bool _sending = false;
  bool _sendingVoice = false;
  bool _sendingMedia = false;
  bool _recording = false;
  DateTime? _recordingStartedAt;
  String? _pendingVoicePath;
  int? _pendingVoiceDurationMs;
  bool _isDraftPlaying = false;
  int _lastMessageId = 0;
  final List<Map<String, dynamic>> _messages = [];
  bool _loadingMore = false;
  bool _hasMoreHistory = true;
  int? _nextBefore;
  final Map<String, String?> _userProfileImages = {};
  final Set<int> _transcribingMessages = {};
  final Map<String, Duration> _audioDurations = {};
  String? _playingAudioUrl;
  bool _isPlayingAudio = false;
  final Set<int> _expandedVoiceMessages = {};

  final _imagePicker = ImagePicker();
  final Map<int, void Function()> _cancelUploadByTempId = {};

  String? _scrollDayOverlayLabel;
  bool _showScrollDayOverlay = false;
  Timer? _scrollDayOverlayTimer;
  int _lastScrollOverlayUpdateMs = 0;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final inBuild =
        phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks;
    if (inBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(fn);
      });
      return;
    }
    setState(fn);
  }

  int? _tryParseEpochMs(dynamic raw) {
    if (raw == null) return null;
    final parsed = raw is int ? raw : int.tryParse(raw.toString());
    if (parsed == null) return null;
    // Heuristic: if it's 10-digit-ish assume seconds, otherwise ms.
    if (parsed > 0 && parsed < 1000000000000) {
      return parsed * 1000;
    }
    return parsed;
  }

  DateTime? _messageCreatedAtLocal(Map<String, dynamic> message) {
    final raw =
        message['created_at'] ??
        message['createdAt'] ??
        message['timestamp'] ??
        message['sent_at'] ??
        message['sentAt'];
    final ms = _tryParseEpochMs(raw);
    if (ms == null) return null;
    // Server times are treated as UTC; convert to local for display.
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }

  DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _weekdayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return '';
    }
  }

  String _monthShort(int month) {
    switch (month) {
      case 1:
        return 'Jan';
      case 2:
        return 'Feb';
      case 3:
        return 'Mar';
      case 4:
        return 'Apr';
      case 5:
        return 'May';
      case 6:
        return 'Jun';
      case 7:
        return 'Jul';
      case 8:
        return 'Aug';
      case 9:
        return 'Sep';
      case 10:
        return 'Oct';
      case 11:
        return 'Nov';
      case 12:
        return 'Dec';
      default:
        return '';
    }
  }

  String _formatDateShort(DateTime dt) => '${dt.day} ${_monthShort(dt.month)} ${dt.year}';

  String _dayHeaderLabel(DateTime messageDayLocal, DateTime nowLocal) {
    final today = _startOfDay(nowLocal);
    final day = _startOfDay(messageDayLocal);
    final diffDays = today.difference(day).inDays;
    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    if (diffDays > 1 && diffDays < 7) return _weekdayName(day.weekday);
    return _formatDateShort(day);
  }

  Widget _buildDaySeparator(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFE0E0E0).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayOverlayPill(String label) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0E0).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _guessContentTypeFromFileName(String fileName, {required bool isVideo}) {
    final lower = fileName.toLowerCase();
    if (isVideo) {
      if (lower.endsWith('.mov')) return 'video/quicktime';
      if (lower.endsWith('.mkv')) return 'video/x-matroska';
      return 'video/mp4';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _pickAndSendMedia({required bool isVideo}) async {
    if (_userId == null || _phone == null) return;
    if (_sendingMedia) return;

    var wasCancelled = false;
    int? tempMessageId;

    try {
      final XFile? picked = isVideo
          ? await _imagePicker.pickVideo(source: ImageSource.gallery)
          : await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() => _sendingMedia = true);

      final tempId = -DateTime.now().millisecondsSinceEpoch;
      tempMessageId = tempId;
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      final tempMessage = {
        'id': tempId,
        'group_id': widget.groupId,
        'user_id': _userId,
        'body': '',
        'created_at': createdAt,
        'message_type': isVideo ? 'video' : 'image',
        'media_url': '',
        'media_content_type': isVideo ? 'video/mp4' : 'image/jpeg',
        'media_size': null,
        'video_thumbnail_url': null,
        'video_duration_ms': null,
        'local_thumb_bytes': null,
        'local_image_bytes': null,
        'upload_progress': 0.0,
        'uploading': true,
      };

      setState(() {
        _messages.add(tempMessage);
      });
      _scrollToBottom(force: true);

      int? videoDurationMs;
      String? videoThumbnailUrl;
      int? pickedLength;
      int lastProgressUiUpdateMs = 0;

      if (isVideo) {
        // Guard: very large camera videos can fail or be slow; enforce the backend limit.
        try {
          pickedLength = await picked.length();
          const maxBytes = 200 * 1024 * 1024; // keep in sync with worker MAX_MEDIA_BYTES
          if (pickedLength > maxBytes) {
            throw Exception('Video too large (${(pickedLength / (1024 * 1024)).toStringAsFixed(1)}MB). Max 200MB.');
          }
        } catch (e) {
          throw e;
        }

        // Derive duration and generate a poster thumbnail locally for fast chat previews.
        // IMPORTANT: Do not block the upload on thumbnail generation/upload.
        // We optimistically show a local thumbnail in the UI first (if we can generate it).
        () async {
          // Duration (best-effort)
          try {
            final controller = VideoPlayerController.file(File(picked.path));
            await controller.initialize().timeout(const Duration(seconds: 3));
            videoDurationMs = controller.value.duration.inMilliseconds;
            await controller.dispose();
          } catch (_) {
            videoDurationMs = null;
          }

          Uint8List? thumbBytes;
          try {
            thumbBytes = await VideoThumbnail.thumbnailData(
              video: picked.path,
              imageFormat: ImageFormat.JPEG,
              maxWidth: 512,
              quality: 75,
            ).timeout(const Duration(seconds: 3));
          } catch (_) {
            thumbBytes = null;
          }

          if (!mounted) return;

          if (thumbBytes != null && thumbBytes.isNotEmpty) {
            setState(() {
              final index = _messages.indexWhere((m) => m['id'] == tempId);
              if (index != -1) {
                _messages[index] = {
                  ..._messages[index],
                  'local_thumb_bytes': thumbBytes,
                };
              }
            });

            // Best-effort: upload thumbnail in the background so other clients can see it.
            try {
              final thumbUpload = await _chatService.uploadMedia(
                groupId: widget.groupId,
                userId: _userId!,
                phone: _phone!,
                email: _email,
                bytes: thumbBytes,
                fileName: 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg',
                contentType: 'image/jpeg',
              );
              final url = thumbUpload['mediaUrl']?.toString() ?? '';
              if (url.isNotEmpty && mounted) {
                videoThumbnailUrl = url;
                setState(() {
                  final index = _messages.indexWhere((m) => m['id'] == tempId);
                  if (index != -1) {
                    _messages[index] = {
                      ..._messages[index],
                      'video_thumbnail_url': url,
                    };
                  }
                });
              }
            } catch (_) {
              // ignore
            }
          }

          if (!mounted) return;
          if (videoDurationMs != null) {
            setState(() {
              final index = _messages.indexWhere((m) => m['id'] == tempId);
              if (index != -1) {
                _messages[index] = {
                  ..._messages[index],
                  'video_duration_ms': videoDurationMs,
                };
              }
            });
          }
        }();
      }

      final fileName = picked.name;
      final contentType = _guessContentTypeFromFileName(fileName, isVideo: isVideo);

      Uint8List? imageBytes;
      if (!isVideo) {
        imageBytes = await picked.readAsBytes();
        setState(() {
          final index = _messages.indexWhere((m) => m['id'] == tempId);
          if (index != -1) {
            _messages[index] = {
              ..._messages[index],
              'local_image_bytes': imageBytes,
            };
          }
        });
      }

      final upload = await _chatService.uploadMediaStream(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
        stream: isVideo ? picked.openRead() : Stream<List<int>>.fromIterable([imageBytes!]),
        length: isVideo ? (pickedLength ?? await picked.length()) : imageBytes!.length,
        fileName: fileName,
        contentType: contentType,
        onCancel: (cancel) {
          _cancelUploadByTempId[tempId] = () {
            wasCancelled = true;
            cancel();
            if (!mounted) return;
            setState(() {
              _messages.removeWhere((m) => m['id'] == tempId);
            });
          };
        },
        onProgress: (sent, total) {
          if (!mounted) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          // Throttle UI updates to keep scrolling smooth.
          if (now - lastProgressUiUpdateMs < 200 && sent < total) return;
          lastProgressUiUpdateMs = now;
          final progress = total > 0 ? (sent / total) : 0.0;
          setState(() {
            final index = _messages.indexWhere((m) => m['id'] == tempId);
            if (index != -1) {
              _messages[index] = {
                ..._messages[index],
                'upload_progress': progress.clamp(0.0, 1.0),
              };
            }
          });
        },
      );

      final mediaUrl = upload['mediaUrl']?.toString() ?? '';
      final objectKey = upload['objectKey']?.toString();
      final uploadedContentType = upload['contentType']?.toString();
      final size = upload['size'];
      final mediaSize = size is int ? size : int.tryParse(size?.toString() ?? '');
      if (mediaUrl.isEmpty) {
        throw Exception('Missing media URL from upload');
      }

      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == tempId);
        if (index != -1) {
          _messages[index] = {
            ..._messages[index],
            'media_url': mediaUrl,
            'media_object_key': objectKey,
            'media_content_type': uploadedContentType ?? contentType,
            'media_size': mediaSize,
            'uploading': true,
          };
        }
      });

      final message = await _chatService.sendMediaMessage(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
        mediaUrl: mediaUrl,
        mediaType: isVideo ? 'video' : 'image',
        mediaObjectKey: objectKey,
        mediaContentType: uploadedContentType ?? contentType,
        mediaSize: mediaSize,
        videoThumbnailUrl: isVideo ? videoThumbnailUrl : null,
        videoDurationMs: isVideo ? videoDurationMs : null,
      );

      setState(() {
        // De-dupe by media_url (similar to voice de-dupe by audio_url)
        _messages.removeWhere((m) => (m['media_url']?.toString() ?? '') == mediaUrl && m['id'] != tempId);
        final index = _messages.indexWhere((m) => m['id'] == tempId);
        if (index != -1) {
          _messages[index] = message;
        } else {
          _messages.add(message);
        }
        _lastMessageId = message['id'] as int;
      });
      _scrollToBottom(force: true);
    } catch (e) {
      if (wasCancelled) {
        if (tempMessageId != null) {
          _cancelUploadByTempId.remove(tempMessageId);
        }
        return;
      }
      setState(() {
        _messages.removeWhere((m) => (m['id'] is int) && (m['id'] as int) < 0);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send media: $e')),
        );
      }
    } finally {
      if (tempMessageId != null) {
        _cancelUploadByTempId.remove(tempMessageId);
      }
      if (mounted) {
        setState(() => _sendingMedia = false);
      }
    }
  }

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

    // Reset pagination for a fresh open.
    _hasMoreHistory = true;
    _nextBefore = null;

    try {
      final page = await _chatService.fetchMessagesPage(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
        limit: _initialMessageLimit,
      );
      _messages
        ..clear()
        ..addAll(page.messages);
      _hasMoreHistory = page.hasMore;
      _nextBefore = page.nextBefore;
      if (_messages.isNotEmpty) {
        _lastMessageId = _messages.last['id'] as int;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(force: true);
      });
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

  Future<void> _loadOlderMessages() async {
    if (_userId == null || _phone == null) return;
    if (_loadingMore || _loading) return;
    if (!_hasMoreHistory) return;

    // If we don't have a cursor, we can't load older.
    final before = _nextBefore ?? (_messages.isNotEmpty ? (_messages.first['id'] as int?) : null);
    if (before == null || before <= 0) {
      setState(() => _hasMoreHistory = false);
      return;
    }

    setState(() => _loadingMore = true);

    final position = _scrollController.hasClients ? _scrollController.position : null;
    final previousPixels = position?.pixels;
    final previousMax = position?.maxScrollExtent;

    try {
      final page = await _chatService.fetchMessagesPage(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
        before: before,
        limit: 10,
      );

      if (!mounted) return;

      if (page.messages.isEmpty) {
        setState(() {
          _hasMoreHistory = false;
          _loadingMore = false;
        });
        return;
      }

      setState(() {
        _hasMoreHistory = page.hasMore;
        _nextBefore = page.nextBefore;

        // Prepend older messages, de-duping by id.
        final existingIds = _messages.map((m) => m['id']).toSet();
        final toInsert = <Map<String, dynamic>>[];
        for (final m in page.messages) {
          final id = m['id'];
          if (existingIds.contains(id)) continue;
          toInsert.add(m);
        }
        _messages.insertAll(0, toInsert);
        if (_messages.isNotEmpty) {
          _lastMessageId = _messages.last['id'] as int;
        }
      });

      // Keep the viewport stable when we prepend items.
      if (previousPixels != null && previousMax != null && _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          final newMax = _scrollController.position.maxScrollExtent;
          final delta = newMax - previousMax;
          // When content grows above, maxScrollExtent increases; offset by delta.
          final target = (previousPixels + delta).clamp(0.0, newMax);
          _scrollController.jumpTo(target);
        });
      }
    } catch (_) {
      // Ignore pagination errors (network hiccups). User can scroll again.
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
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

          final mediaUrl = message['media_url']?.toString() ?? '';
          if (mediaUrl.isNotEmpty) {
            final existingIndex = _messages.indexWhere(
              (m) => (m['media_url']?.toString() ?? '') == mediaUrl,
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
      _scrollToBottom(force: true);

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
      _scrollToBottom(force: true);
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

  void _scrollToBottomInternal({required bool force}) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!force) {
      // Avoid yanking the user to the bottom when they're reading history.
      const nearBottomPx = 120.0;
      final distanceFromBottom = (position.maxScrollExtent - position.pixels).abs();
      if (distanceFromBottom > nearBottomPx) return;
    }
    _scrollController.animateTo(
      position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottom({bool force = false}) {
    _scrollToBottomInternal(force: force);
  }

  /// Load profile image for a user (with caching)
  Future<void> _loadUserProfileImage(String userId) async {
    // Check local cache first
    if (_userProfileImages.containsKey(userId)) return;

    // Check global cache
    if (_UserProfileCache.has(userId)) {
      _safeSetState(() {
        _userProfileImages[userId] = _UserProfileCache.get(userId);
      });
      return;
    }

    // Fetch from server
    try {
      final imageUrl = await _authService.getUserProfileImage(userId);
      _UserProfileCache.set(userId, imageUrl);
      if (mounted) {
        _safeSetState(() {
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
    _scrollDayOverlayTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _audioPlayer.dispose();
    _draftPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nowLocal = DateTime.now();
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
                : Stack(
                    children: [
                      NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          // Only act on an actual user drag to avoid runaway behavior.
                          final isUserDrag = (notification is ScrollUpdateNotification &&
                                  notification.dragDetails != null) ||
                              (notification is OverscrollNotification &&
                                  notification.dragDetails != null);
                          if (!isUserDrag) return false;

                          // Trigger history loading near the top.
                          if (!_loading && !_loadingMore && _hasMoreHistory) {
                            const thresholdPx = 220.0;
                            final metrics = notification.metrics;
                            final nearTopOfHistory = metrics.pixels <= thresholdPx;
                            if (nearTopOfHistory) {
                              _loadOlderMessages();
                            }
                          }

                          // Update the floating day indicator (throttled).
                          final nowMs = DateTime.now().millisecondsSinceEpoch;
                          if (nowMs - _lastScrollOverlayUpdateMs >= 80) {
                            _lastScrollOverlayUpdateMs = nowMs;

                            final itemCount = _messages.length + (_hasMoreHistory ? 1 : 0);
                            final maxExtent = notification.metrics.maxScrollExtent;
                            final avgExtent = (itemCount > 1 && maxExtent > 0)
                                ? (maxExtent / (itemCount - 1))
                                : null;

                            int? estimatedIndex;
                            if (avgExtent != null && avgExtent > 0) {
                              estimatedIndex =
                                  (notification.metrics.pixels / avgExtent).floor().clamp(0, itemCount - 1);
                              if (_hasMoreHistory && estimatedIndex == 0) {
                                estimatedIndex = 1;
                              }
                            }

                            if (estimatedIndex != null) {
                              final messageIndex = _hasMoreHistory
                                  ? (estimatedIndex - 1)
                                  : estimatedIndex;
                              if (messageIndex >= 0 && messageIndex < _messages.length) {
                                final message = _messages[messageIndex];
                                final createdAt = _messageCreatedAtLocal(message);
                                if (createdAt != null) {
                                  final label = _dayHeaderLabel(createdAt, nowLocal);
                                  if (_scrollDayOverlayLabel != label || !_showScrollDayOverlay) {
                                    _safeSetState(() {
                                      _scrollDayOverlayLabel = label;
                                      _showScrollDayOverlay = true;
                                    });
                                  }
                                  _scrollDayOverlayTimer?.cancel();
                                  _scrollDayOverlayTimer = Timer(
                                    const Duration(milliseconds: 700),
                                    () => _safeSetState(() => _showScrollDayOverlay = false),
                                  );
                                }
                              }
                            }
                          }

                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length + (_hasMoreHistory ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_hasMoreHistory && index == 0) {
                              // History loader row (top).
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Center(
                                  child: _loadingMore
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _loadOlderMessages,
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            child: Text(
                                              'Tap here to load earlier messages',
                                              style: TextStyle(color: Colors.grey, fontSize: 12),
                                            ),
                                          ),
                                        ),
                                ),
                              );
                            }

                            final messageIndex = _hasMoreHistory ? index - 1 : index;
                            final message = _messages[messageIndex];
                            final createdAt = _messageCreatedAtLocal(message);
                            DateTime? prevCreatedAt;
                            if (messageIndex > 0) {
                              prevCreatedAt = _messageCreatedAtLocal(_messages[messageIndex - 1]);
                            }
                            final showDayHeader =
                                createdAt != null &&
                                (messageIndex == 0 || prevCreatedAt == null || !_isSameDay(createdAt, prevCreatedAt));
                            final dayLabel = createdAt != null ? _dayHeaderLabel(createdAt, nowLocal) : null;

                            final isMine = message['user_id'] == _userId;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDayHeader && dayLabel != null) _buildDaySeparator(dayLabel),
                                _buildMessageBubble(message, isMine),
                              ],
                            );
                          },
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _showScrollDayOverlay && (_scrollDayOverlayLabel?.isNotEmpty ?? false) ? 1 : 0,
                            duration: const Duration(milliseconds: 120),
                            child: Center(
                              child: _scrollDayOverlayLabel == null
                                  ? const SizedBox.shrink()
                                  : _buildDayOverlayPill(_scrollDayOverlayLabel!),
                            ),
                          ),
                        ),
                      ),
                    ],
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

    final isVoice =
      (messageType == 'voice' || (message['audio_url']?.toString() ?? '').isNotEmpty);
    final isMedia =
      (messageType == 'image' || messageType == 'video' || (message['media_url']?.toString() ?? '').isNotEmpty);

    final messageContent = (_lightweightChatView && (isVoice || isMedia))
      ? _buildLightweightAttachmentContent(message, isMine)
      : (isVoice
        ? _buildVoiceContent(message, isMine)
        : (isMedia
          ? _buildMediaContent(message, isMine)
          : RichText(
            text: TextSpan(
              style: baseStyle,
              children: _buildMessageSpans(text, linkStyle),
            ),
            )));

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

  Widget _buildLightweightAttachmentContent(Map<String, dynamic> message, bool isMine) {
    final messageType =
        message['message_type']?.toString() ?? message['type']?.toString() ?? 'text';
    final audioUrl = message['audio_url']?.toString() ?? '';
    final mediaUrl = message['media_url']?.toString() ?? '';
    final contentType = message['media_content_type']?.toString();
    final videoThumbUrl = message['video_thumbnail_url']?.toString() ?? '';
    final localThumbBytes = message['local_thumb_bytes'] as Uint8List?;

    final textColor = isMine ? Colors.white : Colors.black87;
    final subTextColor = isMine ? Colors.white70 : Colors.black54;

    final isVoice = messageType == 'voice' || audioUrl.isNotEmpty;
    final isVideo =
        messageType == 'video' || ((contentType ?? '').toLowerCase().startsWith('video/'));
    final isImage = messageType == 'image' || (!isVideo && mediaUrl.isNotEmpty);

    void openMediaViewer() {
      if (mediaUrl.isEmpty) return;
      context.push(
        '/media-viewer',
        extra: ChatMediaViewerArgs(mediaUrl: mediaUrl, contentType: contentType),
      );
    }

    if (isVoice) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_none, color: textColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Voice message',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (audioUrl.isNotEmpty)
            TextButton(
              onPressed: () => _shareVoiceMessage(message),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Share', style: TextStyle(color: subTextColor)),
            ),
        ],
      );
    }

    if (mediaUrl.isEmpty) {
      return Text('Attachment', style: TextStyle(color: subTextColor));
    }

    if (isVideo) {
      Widget? preview;
      if (localThumbBytes != null && localThumbBytes.isNotEmpty) {
        preview = Image.memory(localThumbBytes, fit: BoxFit.cover);
      } else if (videoThumbUrl.isNotEmpty) {
        preview = CachedNetworkImage(
          imageUrl: videoThumbUrl,
          fit: BoxFit.cover,
          placeholder: (context, _) => Container(color: Colors.black12),
          errorWidget: (context, _, __) => Container(color: Colors.black12),
        );
      }

      return InkWell(
        onTap: openMediaViewer,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (preview != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(width: 88, height: 50, child: preview),
              )
            else
              Icon(Icons.videocam_outlined, color: textColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Video (tap to open)',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    if (isImage) {
      return InkWell(
        onTap: openMediaViewer,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, color: textColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Photo (tap to open)',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Text('Attachment', style: TextStyle(color: subTextColor));
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

  Widget _buildMediaContent(Map<String, dynamic> message, bool isMine) {
    final messageType =
        message['message_type']?.toString() ?? message['type']?.toString() ?? 'text';
    final mediaUrl = message['media_url']?.toString() ?? '';
    final contentType = message['media_content_type']?.toString();
    final videoThumbUrl = message['video_thumbnail_url']?.toString() ?? '';
    final localThumbBytes = message['local_thumb_bytes'] as Uint8List?;
    final localImageBytes = message['local_image_bytes'] as Uint8List?;
    final progressRaw = message['upload_progress'];
    final uploadProgress = progressRaw is num ? progressRaw.toDouble() : null;
    final durationRaw = message['video_duration_ms'];
    final videoDurationMs = durationRaw is int ? durationRaw : int.tryParse(durationRaw?.toString() ?? '');
    final uploading = (message['uploading'] == true) || (mediaUrl.isEmpty && (message['id'] is int) && (message['id'] as int) < 0);

    final isVideo = messageType == 'video' || (contentType ?? '').toLowerCase().startsWith('video/');
    final textColor = isMine ? Colors.white : Colors.black87;
    final subTextColor = isMine ? Colors.white70 : Colors.black54;
    final idRaw = message['id'];
    final tempId = idRaw is int ? idRaw : null;
    final cancelUpload = (tempId != null) ? _cancelUploadByTempId[tempId] : null;

    if (uploading) {
      Widget? preview;

      if (isVideo) {
        if (localThumbBytes != null && localThumbBytes.isNotEmpty) {
          preview = Image.memory(localThumbBytes, fit: BoxFit.cover);
        } else if (videoThumbUrl.isNotEmpty) {
          preview = CachedNetworkImage(imageUrl: videoThumbUrl, fit: BoxFit.cover);
        }
      } else {
        if (localImageBytes != null && localImageBytes.isNotEmpty) {
          preview = Image.memory(localImageBytes, fit: BoxFit.cover);
        }
      }

      final pct = (uploadProgress != null) ? (uploadProgress.clamp(0.0, 1.0) * 100).round() : null;

      if (preview == null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: uploadProgress,
                valueColor: AlwaysStoppedAnimation<Color>(subTextColor),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isVideo ? 'Uploading video…' : 'Uploading photo…',
              style: TextStyle(color: subTextColor),
            ),
            if (pct != null) ...[
              const SizedBox(width: 8),
              Text('$pct%', style: TextStyle(color: subTextColor)),
            ],
          ],
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220, maxWidth: 260),
          child: Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.center,
            children: [
              preview,
              Container(color: Colors.black.withOpacity(0.15)),
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  value: uploadProgress,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  backgroundColor: Colors.white24,
                ),
              ),
              if (cancelUpload != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: cancelUpload,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              if (pct != null)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Uploading $pct%',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              if (isVideo)
                Icon(Icons.play_circle_fill, color: Colors.white.withOpacity(0.85), size: 54),
            ],
          ),
        ),
      );
    }

    if (mediaUrl.isEmpty) {
      return Text('Missing media URL', style: TextStyle(color: subTextColor));
    }

    void openMediaViewer() {
      context.push(
        '/media-viewer',
        extra: ChatMediaViewerArgs(mediaUrl: mediaUrl, contentType: contentType),
      );
    }

    String formatDuration(int ms) {
      final totalSeconds = (ms / 1000).floor();
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;
      final mm = minutes.toString();
      final ss = seconds.toString().padLeft(2, '0');
      return '$mm:$ss';
    }

    if (isVideo) {
      if (videoThumbUrl.isNotEmpty) {
        return InkWell(
          onTap: openMediaViewer,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 260),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CachedNetworkImage(
                    imageUrl: videoThumbUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, imageUrl) => Container(
                      color: isMine ? Colors.white12 : Colors.black12,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(subTextColor),
                        ),
                      ),
                    ),
                    errorWidget: (context, imageUrl, error) => Container(
                      color: isMine ? Colors.white12 : Colors.black12,
                      padding: const EdgeInsets.all(12),
                      child: Text('Failed to load video preview', style: TextStyle(color: subTextColor)),
                    ),
                  ),
                  Icon(Icons.play_circle_fill, color: Colors.white.withOpacity(0.92), size: 54),
                  if (videoDurationMs != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          formatDuration(videoDurationMs),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }

      return InkWell(
        onTap: openMediaViewer,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_fill, color: textColor, size: 28),
            const SizedBox(width: 8),
            Text('Video', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return InkWell(
      onTap: openMediaViewer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220, maxWidth: 260),
          child: CachedNetworkImage(
            imageUrl: mediaUrl,
            fit: BoxFit.cover,
            placeholder: (context, imageUrl) => Container(
              color: isMine ? Colors.white12 : Colors.black12,
              alignment: Alignment.center,
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(subTextColor),
                ),
              ),
            ),
            errorWidget: (context, imageUrl, error) => Container(
              color: isMine ? Colors.white12 : Colors.black12,
              padding: const EdgeInsets.all(12),
              child: Text('Failed to load photo', style: TextStyle(color: subTextColor)),
            ),
          ),
        ),
      ),
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset),
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
            if (_sendingMedia)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.attach_file, color: Colors.grey),
                onPressed: _pendingVoicePath != null
                    ? null
                    : () {
                        showModalBottomSheet(
                          context: context,
                          builder: (context) {
                            return SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.photo),
                                    title: const Text('Photo'),
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      _pickAndSendMedia(isVideo: false);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.videocam),
                                    title: const Text('Video'),
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      _pickAndSendMedia(isVideo: true);
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
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
      ),
    );
  }
}
