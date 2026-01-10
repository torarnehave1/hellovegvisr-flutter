import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/group_chat_service.dart';

class GroupChatListScreen extends StatefulWidget {
  const GroupChatListScreen({super.key});

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
  static const String _groupsCacheKey = 'cached_group_chats';

  String? _cacheBustedImageUrl(String? url, int? updatedAt) {
    if (url == null || url.isEmpty || updatedAt == null) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}v=$updatedAt';
  }

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    await _loadCachedGroups();
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

  Future<void> _loadCachedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_groupsCacheKey);
    if (cached == null || cached.isEmpty) return;
    try {
      final data = jsonDecode(cached);
      if (data is List) {
        setState(() {
          _groups = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (_) {
      // Ignore cache errors
    }
  }

  Future<void> _loadGroups() async {
    if (_userId == null || _phone == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Missing user session. Please log in again.'),
          ),
        );
      }
      return;
    }
    if (_groups.isEmpty) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final since = _groups.isEmpty
          ? null
          : _groups
                .map((g) => g['updated_at'])
                .whereType<int>()
                .fold<int?>(
                  null,
                  (maxValue, value) => maxValue == null
                      ? value
                      : (value > maxValue ? value : maxValue),
                );
      final groups = await _chatService.fetchGroups(
        userId: _userId!,
        phone: _phone!,
        email: _email,
        since: since,
      );
      if (since == null) {
        setState(() {
          _groups = groups;
          _loading = false;
        });
      } else if (groups.isNotEmpty) {
        final addedCount = groups.length;
        final byId = {for (final g in _groups) g['id']: g};
        for (final g in groups) {
          final id = g['id'];
          if (id != null) {
            byId[id] = {...(byId[id] ?? {}), ...g};
          }
        }
        final merged = byId.values.toList();
        merged.sort((a, b) {
          final aUpdated =
              a['updated_at'] as int? ?? a['created_at'] as int? ?? 0;
          final bUpdated =
              b['updated_at'] as int? ?? b['created_at'] as int? ?? 0;
          return bUpdated.compareTo(aUpdated);
        });
        setState(() {
          _groups = merged;
          _loading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Updated $addedCount chat${addedCount == 1 ? '' : 's'}',
              ),
            ),
          );
        }
      } else {
        setState(() {
          _loading = false;
        });
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_groupsCacheKey, jsonEncode(_groups));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load groups: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create group: $e')));
      }
    }
  }

  Future<void> _openPoweredByLink() async {
    final uri = Uri.parse('https://vegvisr.org');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4f6d7a),
        foregroundColor: Colors.white,
        title: const Text('Chats'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/?openDrawer=true'),
        ),
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
                  final rawImageUrl = group['image_url'] as String?;
                  final imageUrl = _cacheBustedImageUrl(
                    rawImageUrl != null && rawImageUrl.trim().isNotEmpty
                        ? rawImageUrl
                        : null,
                    group['updated_at'] as int?,
                  );
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF4f6d7a),
                      foregroundColor: Colors.white,
                      backgroundImage: imageUrl != null
                          ? NetworkImage(imageUrl)
                          : null,
                      child: imageUrl == null
                          ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: InkWell(
            onTap: _openPoweredByLink,
            child: const Text(
              'Powered by Vegvisr.org',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
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
