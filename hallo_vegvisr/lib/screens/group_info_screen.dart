import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/group_chat_service.dart';
import '../services/knowledge_graph_service.dart';

class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  final String? groupName;

  const GroupInfoScreen({
    super.key,
    required this.groupId,
    this.groupName,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final _authService = AuthService();
  final _chatService = GroupChatService();
  final _knowledgeGraphService = KnowledgeGraphService();
  final _imagePicker = ImagePicker();

  String? _userId;
  String? _phone;
  String? _email;
  String? _userRole;
  String? _groupImageUrl;
  int? _groupUpdatedAt;
  bool _loading = true;
  bool _uploadingImage = false;
  List<Map<String, dynamic>> _members = [];
  String? _inviteLink;
  bool _creatingInvite = false;

  String? _cacheBustedImageUrl(String? url, int? updatedAt) {
    if (url == null || url.isEmpty || updatedAt == null) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}v=$updatedAt';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = await _authService.getUserId();
    final phone = await _authService.getPhone();
    final email = await _authService.getEmail();

    setState(() {
      _userId = userId;
      _phone = phone;
      _email = email;
    });

    await _loadGroupInfo();
    await _loadMembers();
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
      // Ignore - image URL is optional
    }
  }

  Future<void> _loadMembers() async {
    if (_userId == null || _phone == null) return;

    setState(() => _loading = true);

    try {
      final members = await _chatService.fetchMembers(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
      );

      // Find current user's role
      String? myRole;
      for (final m in members) {
        if (m['user_id'] == _userId) {
          myRole = m['role']?.toString();
          break;
        }
      }

      setState(() {
        _members = members;
        _userRole = myRole;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load members: $e')),
        );
      }
    }
  }

  Future<void> _createInviteLink() async {
    if (_userId == null || _phone == null) return;

    setState(() => _creatingInvite = true);

    try {
      final invite = await _chatService.createInviteLink(
        groupId: widget.groupId,
        userId: _userId!,
        phone: _phone!,
        email: _email,
      );

      setState(() {
        _inviteLink = invite['invite_link']?.toString();
        _creatingInvite = false;
      });

      _showInviteLinkDialog();
    } catch (e) {
      setState(() => _creatingInvite = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create invite link: $e')),
        );
      }
    }
  }

  void _showInviteLinkDialog() {
    if (_inviteLink == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _inviteLink!,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Share this link to invite people to the group. Link expires in 7 days.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _inviteLink!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied to clipboard')),
              );
              Navigator.pop(context);
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              Share.share(
                'Join my group on Hallo Vegvisr: $_inviteLink',
                subject: 'Join ${widget.groupName ?? "my group"} on Hallo Vegvisr',
              );
              Navigator.pop(context);
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }

  bool get _isOwnerOrAdmin => _userRole == 'owner' || _userRole == 'admin';

  Future<void> _pickAndUploadGroupImage() async {
    if (_userId == null || _phone == null) return;

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _uploadingImage = true);

      final bytes = await image.readAsBytes();
      final result = await _knowledgeGraphService.uploadImage(
        bytes,
        'group_${widget.groupId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        'image/jpeg',
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final imageUrl = result['url'] as String;

        // Update group with new image URL
        await _chatService.updateGroup(
          groupId: widget.groupId,
          userId: _userId!,
          phone: _phone!,
          email: _email,
          imageUrl: imageUrl,
        );

        setState(() {
          _groupImageUrl = imageUrl;
          _uploadingImage = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Group image updated')),
          );
        }
      } else {
        setState(() => _uploadingImage = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? 'Failed to upload image')),
          );
        }
      }
    } catch (e) {
      setState(() => _uploadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header with group avatar
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: const Color(0xFF4f6d7a),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF4f6d7a), Color(0xFF3a5260)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    GestureDetector(
                      onTap: _isOwnerOrAdmin && !_uploadingImage
                          ? _pickAndUploadGroupImage
                          : null,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 45,
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
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                          if (_uploadingImage)
                            const Positioned.fill(
                              child: CircleAvatar(
                                radius: 45,
                                backgroundColor: Colors.black38,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          if (_isOwnerOrAdmin && !_uploadingImage)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4f6d7a),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.groupName ?? 'Group',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${_members.length} members',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Action buttons
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.message,
                    label: 'Message',
                    onTap: () => Navigator.pop(context),
                  ),
                  _buildActionButton(
                    icon: Icons.notifications,
                    label: 'Mute',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mute coming soon')),
                      );
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.exit_to_app,
                    label: 'Leave',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Leave group coming soon')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Add Members button (only for owner/admin)
          if (_isOwnerOrAdmin)
            SliverToBoxAdapter(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4f6d7a).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.person_add, color: Color(0xFF4f6d7a)),
                ),
                title: const Text('Add Members'),
                subtitle: const Text('Create invite link'),
                trailing: _creatingInvite
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _creatingInvite ? null : _createInviteLink,
              ),
            ),
          // Members section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'Members',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4f6d7a),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_members.length}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Members list
          _loading
              ? const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final member = _members[index];
                      return _buildMemberTile(member);
                    },
                    childCount: _members.length,
                  ),
                ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF4f6d7a)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF4f6d7a)),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4f6d7a),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final memberId = member['user_id']?.toString() ?? '';
    final role = member['role']?.toString() ?? 'member';
    final isMe = memberId == _userId;

    // Get initials from user_id (last 2 chars)
    final initials = memberId.length >= 2
        ? memberId.substring(memberId.length - 2).toUpperCase()
        : 'U';

    String roleLabel = '';
    Color? roleColor;
    if (role == 'owner') {
      roleLabel = 'Owner';
      roleColor = Colors.orange;
    } else if (role == 'admin') {
      roleLabel = 'Admin';
      roleColor = Colors.blue;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isMe
            ? const Color(0xFF4f6d7a)
            : Colors.grey.shade300,
        child: Text(
          initials,
          style: TextStyle(
            color: isMe ? Colors.white : Colors.grey.shade700,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              isMe ? 'You' : 'User ${memberId.substring(0, 8)}...',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (roleLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: roleColor?.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                roleLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: roleColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        'Joined ${_formatTimestamp(member['joined_at'])}',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'unknown';
    try {
      final ms = timestamp is int ? timestamp : int.parse(timestamp.toString());
      final date = DateTime.fromMillisecondsSinceEpoch(ms);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        return 'today';
      } else if (diff.inDays == 1) {
        return 'yesterday';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (_) {
      return 'unknown';
    }
  }
}
