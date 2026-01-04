import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/group_chat_service.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String? groupName;

  const GroupChatScreen({
    Key? key,
    required this.groupId,
    this.groupName,
  }) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _authService = AuthService();
  final _chatService = GroupChatService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _pollTimer;

  String? _userId;
  String? _phone;
  String? _email;
  String? _groupImageUrl;
  bool _loading = true;
  int _lastMessageId = 0;
  final List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final userId = await _authService.getUserId();
    final phone = await _authService.getPhone();
    final email = await _authService.getEmail();
    setState(() {
      _userId = userId;
      _phone = phone;
      _email = email;
    });

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load messages: $e')),
        );
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
        setState(() {
          _messages.addAll(messages);
          _lastMessageId = _messages.last['id'] as int;
        });
        _scrollToBottom();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
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

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
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
          onTap: () => context.push('/group-info/${widget.groupId}', extra: widget.groupName),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                backgroundImage: _groupImageUrl != null
                    ? NetworkImage(_groupImageUrl!)
                    : null,
                child: _groupImageUrl == null
                    ? Text(
                        (widget.groupName ?? 'G')[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
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
                      final message =
                          _messages[_messages.length - 1 - index];
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
    final baseStyle = TextStyle(
      color: isMine ? Colors.white : Colors.black87,
    );
    final linkStyle = baseStyle.copyWith(
      color: isMine ? Colors.lightBlueAccent : Colors.blueAccent,
      decoration: TextDecoration.underline,
    );
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFF4f6d7a) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: RichText(
          text: TextSpan(
            style: baseStyle,
            children: _buildMessageSpans(text, linkStyle),
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
          recognizer: TapGestureRecognizer()
            ..onTap = () => _openLink(url),
        ),
      );
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }

    return spans;
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open link')),
      );
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
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFF4f6d7a)),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}
