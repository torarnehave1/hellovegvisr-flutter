import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/knowledge_graph_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _knowledgeGraphService = KnowledgeGraphService();
  final _imagePicker = ImagePicker();

  String? _userPhone;
  String? _userEmail;
  String? _userId;
  String? _profileImageUrl;
  int _graphCount = 0;
  bool _loading = true;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);

    final phone = await _authService.getPhone();
    final email = await _authService.getEmail();
    final userId = await _authService.getUserId();

    setState(() {
      _userPhone = phone;
      _userEmail = email;
      _userId = userId;
    });

    // Load profile from server (includes profile_image_url)
    final profileResult = await _authService.getUserProfile();
    if (profileResult['success'] == true) {
      setState(() {
        _profileImageUrl = profileResult['profile_image_url'];
      });
    }

    // Load graph count
    if (phone != null) {
      final result = await _knowledgeGraphService.getMyGraphs(
        phone: phone,
        userId: userId,
      );
      if (result['success'] == true) {
        setState(() {
          _graphCount = (result['graphs'] as List?)?.length ?? 0;
        });
      }
    }

    setState(() => _loading = false);
  }

  Future<void> _pickAndUploadProfileImage() async {
    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() => _uploadingImage = true);

    try {
      // Upload image using knowledge graph service (same R2 bucket)
      final imageBytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name;

      // Determine MIME type from file extension
      String mimeType = 'image/jpeg';
      if (fileName.toLowerCase().endsWith('.png')) {
        mimeType = 'image/png';
      } else if (fileName.toLowerCase().endsWith('.gif')) {
        mimeType = 'image/gif';
      }

      final uploadResult = await _knowledgeGraphService.uploadImage(
        imageBytes,
        fileName,
        mimeType,
      );

      if (uploadResult['success'] == true && uploadResult['url'] != null) {
        final imageUrl = uploadResult['url'] as String;
        // Update profile with new image URL
        final updateResult = await _authService.updateProfileImage(imageUrl);
        if (updateResult['success'] == true) {
          setState(() {
            _profileImageUrl = imageUrl;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile image updated')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to save: ${updateResult['error']}')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload: ${uploadResult['error'] ?? 'Unknown error'}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  String _getInitials() {
    if (_userEmail != null && _userEmail!.isNotEmpty) {
      final parts = _userEmail!.split('@')[0].split('.');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return _userEmail![0].toUpperCase();
    }
    if (_userPhone != null && _userPhone!.isNotEmpty) {
      return _userPhone!.substring(_userPhone!.length - 2);
    }
    return 'HV';
  }

  String _getDisplayName() {
    if (_userEmail != null && _userEmail!.isNotEmpty) {
      return _userEmail!.split('@')[0].replaceAll('.', ' ').split(' ').map((word) =>
        word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : ''
      ).join(' ');
    }
    return 'Vegvisr User';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4f6d7a),
        foregroundColor: Colors.white,
        title: const Text('My Profile'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Profile header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF4f6d7a), Color(0xFF3a5260)],
                      ),
                    ),
                    child: Column(
                      children: [
                        // Large avatar with camera overlay
                        GestureDetector(
                          onTap: _uploadingImage ? null : _pickAndUploadProfileImage,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.white.withValues(alpha: 0.2),
                                backgroundImage: _profileImageUrl != null
                                    ? NetworkImage(_profileImageUrl!)
                                    : null,
                                child: _profileImageUrl == null
                                    ? Text(
                                        _getInitials(),
                                        style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4f6d7a),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: _uploadingImage
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.camera_alt,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Name
                        Text(
                          _getDisplayName(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Phone
                        Text(
                          _userPhone ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Stats
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.account_tree,
                            value: '$_graphCount',
                            label: 'Graphs',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            icon: Icons.calendar_today,
                            value: 'Jan 2026',
                            label: 'Member Since',
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Profile details
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Account Info',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4f6d7a),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  _buildInfoTile(
                    icon: Icons.phone,
                    title: 'Phone',
                    value: _userPhone ?? 'Not set',
                    onCopy: _userPhone,
                  ),
                  _buildInfoTile(
                    icon: Icons.email,
                    title: 'Email',
                    value: _userEmail ?? 'Not set',
                    onCopy: _userEmail,
                  ),
                  _buildInfoTile(
                    icon: Icons.fingerprint,
                    title: 'User ID',
                    value: _userId != null ? '${_userId!.substring(0, 8)}...' : 'Not set',
                    onCopy: _userId,
                  ),

                  const SizedBox(height: 24),

                  // Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Edit profile coming soon')),
                              );
                            },
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit Profile'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF4f6d7a),
                              side: const BorderSide(color: Color(0xFF4f6d7a)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4f6d7a).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF4f6d7a), size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4f6d7a),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    String? onCopy,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF4f6d7a).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF4f6d7a)),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[600],
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      trailing: onCopy != null
          ? IconButton(
              icon: const Icon(Icons.copy, size: 20),
              color: Colors.grey,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: onCopy));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$title copied to clipboard')),
                );
              },
            )
          : null,
    );
  }
}
