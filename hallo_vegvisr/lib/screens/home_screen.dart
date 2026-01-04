import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key, this.openDrawer = false}) : super(key: key);

  final bool openDrawer;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _userPhone;
  String? _userEmail;
  final _authService = AuthService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _drawerAutoOpened = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _maybeOpenDrawer();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openDrawer != widget.openDrawer) {
      _drawerAutoOpened = false;
    }
    _maybeOpenDrawer();
  }

  void _maybeOpenDrawer() {
    if (!widget.openDrawer || _drawerAutoOpened) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openDrawer();
      _drawerAutoOpened = true;
    });
  }

  Future<void> _loadUserInfo() async {
    final phone = await _authService.getPhone();
    final email = await _authService.getEmail();
    setState(() {
      _userPhone = phone;
      _userEmail = email;
    });
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Logged out')));
      context.go('/login');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4f6d7a),
        foregroundColor: Colors.white,
        title: const Text('Hallo Vegvisr'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: _buildDrawer(),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: SvgPicture.asset(
                'assets/Black.svg',
                width: 140,
                semanticsLabel: 'Vegvisr logo',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'HALLO VEGVISR',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (_userPhone != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.phone, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _userPhone!,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),
            const Text(
              'Swipe from left or tap menu to navigate',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/create-graph'),
        tooltip: 'Create Graph',
        backgroundColor: const Color(0xFF4f6d7a),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          // Header with user profile (Telegram-style)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
              top: 50,
              left: 16,
              right: 16,
              bottom: 16,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4f6d7a), Color(0xFF3a5260)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with initials
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: Text(
                        _getInitials(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Night mode toggle (like Telegram)
                    IconButton(
                      icon: const Icon(
                        Icons.dark_mode_outlined,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Dark mode coming soon'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // User name/email
                if (_userEmail != null && _userEmail!.isNotEmpty)
                  Text(
                    _userEmail!
                        .split('@')[0]
                        .replaceAll('.', ' ')
                        .split(' ')
                        .map(
                          (word) => word.isNotEmpty
                              ? '${word[0].toUpperCase()}${word.substring(1)}'
                              : '',
                        )
                        .join(' '),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                const SizedBox(height: 4),
                // Phone number
                Row(
                  children: [
                    Text(
                      _userPhone ?? 'Not logged in',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white.withValues(alpha: 0.8),
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Menu items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  icon: Icons.person_outline,
                  title: 'My Profile',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/profile');
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.add_circle_outline,
                  title: 'New Graph',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/create-graph');
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.folder_outlined,
                  title: 'My Graphs',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/my-graphs');
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.chat_bubble_outline,
                  title: 'Group Chats',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/group-chats');
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.bookmark_outline,
                  title: 'Saved',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Saved graphs coming soon')),
                    );
                  },
                ),
                const Divider(),
                _buildDrawerItem(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/settings');
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.people_outline,
                  title: 'Invite Friends',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Share feature coming soon'),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.help_outline,
                  title: 'Vegvisr Features',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Help coming soon')),
                    );
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.bug_report_outlined,
                  title: 'FCM Debug (token)',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/debug/fcm-token');
                  },
                ),
              ],
            ),
          ),

          // Logout at bottom
          const Divider(height: 1),
          _buildDrawerItem(
            icon: Icons.logout,
            title: 'Logout',
            iconColor: Colors.red,
            textColor: Colors.red,
            onTap: () {
              Navigator.pop(context);
              _logout();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? const Color(0xFF4f6d7a)),
      title: Text(
        title,
        style: TextStyle(fontSize: 16, color: textColor ?? Colors.black87),
      ),
      onTap: onTap,
    );
  }
}
