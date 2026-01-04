import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/group_chat_service.dart';

class GroupChatListScreen extends StatefulWidget {
  const GroupChatListScreen({Key? key}) : super(key: key);

  @override
  State<GroupChatListScreen> createState() => _GroupChatListScreenState();
}

class _GroupChatListScreenState extends State<GroupChatListScreen> {
  final _authService = AuthService();
  final _chatService = GroupChatService();
  bool _loading = true;
  String? _userId;
  String? _phone;
  String? _email;
  List<Map<String, dynamic>> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final userId = await _authService.getUserId();
    final phone = await _authService.getPhone();
    final email = await _authService.getEmail();
    setState(() {
      _userId = userId;
      _phone = phone;
      _email = email;
    });
    await _loadGroups();
  }

  Future<void> _loadGroups() async {
    if (_userId == null || _phone == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing user session. Please log in again.')),
        );
      }
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final groups = await _chatService.fetchGroups(
        userId: _userId!,
        phone: _phone!,
        email: _email,
      );
      setState(() {
        _groups = groups;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load groups: $e')),
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

  Future<void> _showCreateGroupDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Group'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Group name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) {
      return;
    }
    if (_userId == null || _phone == null) {
      return;
    }

    try {
      final group = await _chatService.createGroup(
        name: result,
        createdBy: _userId!,
        phone: _phone!,
        email: _email,
      );
      setState(() {
        _groups = [group, ..._groups];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
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
        title: const Text('Chats'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadGroups,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _groups.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final group = _groups[index];
                  final name = group['name']?.toString() ?? 'Unnamed group';
                  final imageUrl = group['image_url'] as String?;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF4f6d7a),
                      foregroundColor: Colors.white,
                      backgroundImage: imageUrl != null
                          ? NetworkImage(imageUrl)
                          : null,
                      child: imageUrl == null
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                            )
                          : null,
                    ),
                    title: Text(name),
                    subtitle: const Text('Tap to open chat'),
                    onTap: () async {
                      await context.push(
                        '/group-chat/${group['id']}',
                        extra: name,
                      );
                      if (mounted) {
                        await _loadGroups();
                      }
                    },
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateGroupDialog,
        backgroundColor: const Color(0xFF4f6d7a),
        foregroundColor: Colors.white,
        child: const Icon(Icons.edit),
      ),
    );
  }
}
