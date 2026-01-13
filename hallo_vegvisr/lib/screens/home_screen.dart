import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import '../services/invitation_service.dart';
import '../main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.openDrawer = false});

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
  BrandingConfig _branding = BrandingConfig.defaultBranding();

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadBranding();
    _maybeOpenDrawer();
  }

  Future<void> _loadBranding() async {
    final phone = await _authService.getPhone();
    if (phone != null) {
      final branding = await BrandingService.fetchBrandingByPhone(phone);
      if (mounted) {
        setState(() {
          _branding = branding;
        });
        // Update app theme using global function from main.dart
        updateAppTheme(branding);
      }
    }
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

  Future<void> _openPoweredByLink() async {
    final uri = Uri.parse('https://vegvisr.org');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open link')));
    }
  }

  /// Share invite link for the current brand
  Future<void> _shareInviteLink() async {
    // If the user is not inside a branded app, invite them to join Hallo Vegvisr itself.
    if (!_branding.hasCustomBranding || _branding.domain == null) {
      const webUrl = 'https://hallo.vegvisr.org';
      const androidApkUrl = 'https://apps.vegvisr.org/download/hallo-vegvisr.apk';

      await SharePlus.instance.share(
        ShareParams(
          text: 'Join me on Hallo Vegvisr!\n\nWeb: $webUrl\nAndroid: $androidApkUrl',
          subject: 'Invitation to Hallo Vegvisr',
        ),
      );
      return;
    }

    if (_userPhone == null || _userPhone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to invite users')),
      );
      return;
    }

    // Show loading
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Creating invite link...')));

    // Create invitation via API
    final result = await InvitationService.createInvitation(
      domain: _branding.domain!,
      phone: _userPhone!,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      final inviteCode = result['inviteCode'];
      final inviteUrl = 'https://vegvisr.org/join/$inviteCode';

      // Share the invite link
      await SharePlus.instance.share(
        ShareParams(
          text:
              'Join me on ${_branding.siteTitle ?? _branding.domain}!\n\n$inviteUrl',
          subject: 'Invitation to ${_branding.siteTitle ?? _branding.domain}',
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to create invite'),
          backgroundColor: Colors.red,
        ),
      );
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

  /// Build the logo widget - uses mobileAppLogo if available, then logoUrl, otherwise default SVG
  Widget _buildLogo() {
    final logoUrl = _branding.effectiveMobileLogoUrl;
    if (_branding.hasCustomBranding && logoUrl != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CachedNetworkImage(
            imageUrl: logoUrl,
            width: 140,
            fit: BoxFit.contain,
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) => SvgPicture.asset(
              'assets/Black.svg',
              width: 140,
              semanticsLabel: 'Vegvisr logo',
            ),
          ),
          // Show platform tag below the branded logo
          const SizedBox(height: 8),
          Text(
            'Powered by VEGR.AI',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }
    return SvgPicture.asset(
      'assets/Black.svg',
      width: 140,
      semanticsLabel: 'Vegvisr logo',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use branding colors and title
    final appBarColor = _branding.primaryColor;
    final appTitle = _branding.siteTitle ?? 'Hallo Vegvisr';

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
        title: Text(appTitle),
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
                color: _branding.hasCustomBranding
                    ? Colors.white
                    : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                boxShadow: _branding.hasCustomBranding
                    ? [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: _buildLogo(),
            ),
            const SizedBox(height: 16),
            Text(
              appTitle.toUpperCase(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            // Show slogan if available
            if (_branding.slogan != null && _branding.slogan!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _branding.slogan!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: _branding.primaryColor.withValues(alpha: 0.8),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
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
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDrawer() {
    // Use branding colors for drawer
    final primaryColor = _branding.primaryColor;
    final secondaryColor = _branding.secondaryColor;

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
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primaryColor, secondaryColor],
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
                  icon: Icons.smart_toy_outlined,
                  title: 'AI Settings',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/ai-settings');
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.smart_toy,
                  title: 'AI Assistant',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/graph-ai');
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.people_outline,
                  title: 'Invite Friends',
                  onTap: () {
                    Navigator.pop(context);
                    _shareInviteLink();
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
                const Divider(),
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
                // Add bottom padding to ensure logout is visible above system navigation
                const SizedBox(height: 32),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: InkWell(
              onTap: _openPoweredByLink,
              child: const Text(
                'Powered by VEGR.AI',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
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
      leading: Icon(icon, color: iconColor ?? _branding.primaryColor),
      title: Text(
        title,
        style: TextStyle(fontSize: 16, color: textColor ?? Colors.black87),
      ),
      onTap: onTap,
    );
  }
}
