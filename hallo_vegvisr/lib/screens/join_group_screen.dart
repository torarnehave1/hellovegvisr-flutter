import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/group_chat_service.dart';

class JoinGroupScreen extends StatefulWidget {
  final String inviteCode;

  const JoinGroupScreen({
    super.key,
    required this.inviteCode,
  });

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _authService = AuthService();
  final _chatService = GroupChatService();

  bool _loading = true;
  bool _joining = false;
  String? _error;
  Map<String, dynamic>? _inviteInfo;

  String? _userId;
  String? _phone;
  String? _email;

  @override
  void initState() {
    super.initState();
    _loadInviteInfo();
  }

  Future<void> _loadInviteInfo() async {
    // Load user credentials
    final userId = await _authService.getUserId();
    final phone = await _authService.getPhone();
    final email = await _authService.getEmail();

    setState(() {
      _userId = userId;
      _phone = phone;
      _email = email;
    });

    // Fetch invite info
    try {
      final info = await _chatService.getInviteInfo(widget.inviteCode);
      setState(() {
        _inviteInfo = info;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _joinGroup() async {
    if (_userId == null || _phone == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in first')),
        );
        context.go('/login');
      }
      return;
    }

    setState(() => _joining = true);

    try {
      final result = await _chatService.joinViaInvite(
        code: widget.inviteCode,
        userId: _userId!,
        phone: _phone!,
        email: _email,
      );

      if (!mounted) return;

      if (result['already_member'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are already a member of this group')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined ${result['group_name'] ?? 'group'}!')),
        );
      }

      // Navigate to the group chat
      context.go('/group-chat/${result['group_id']}', extra: result['group_name']);
    } catch (e) {
      setState(() => _joining = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4f6d7a),
        foregroundColor: Colors.white,
        title: const Text('Join Group'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _buildInviteInfo(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteInfo() {
    final groupName = _inviteInfo?['group_name'] ?? 'Unknown Group';
    final memberCount = _inviteInfo?['member_count'] ?? 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Group avatar
            CircleAvatar(
              radius: 50,
              backgroundColor: const Color(0xFF4f6d7a),
              child: Text(
                groupName[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Group name
            Text(
              groupName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Member count
            Text(
              '$memberCount members',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),

            // Join button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _joining ? null : _joinGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4f6d7a),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _joining
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Join Group',
                        style: TextStyle(fontSize: 18),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Cancel button
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
