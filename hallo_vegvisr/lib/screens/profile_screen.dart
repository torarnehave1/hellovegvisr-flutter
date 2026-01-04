import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  String? _userPhone;
  String? _userEmail;
  String? _userId;
  int _graphCount = 0;
  bool _loading = true;

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
                        // Large avatar
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          child: Text(
                            _getInitials(),
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
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
