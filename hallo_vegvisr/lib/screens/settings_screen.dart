import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  bool _notificationsEnabled = true;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = '${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _authService.logout();
    if (mounted) {
      context.go('/login');
    }
  }

  void _returnToMenu() {
    context.go('/?openDrawer=true');
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _returnToMenu();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF4f6d7a),
          foregroundColor: Colors.white,
          title: const Text('Settings'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _returnToMenu,
          ),
        ),
        body: ListView(
          children: [
            const SizedBox(height: 8),

            // Notifications section
            _buildSectionHeader('Notifications'),
            SwitchListTile(
              secondary: const Icon(
                Icons.notifications_outlined,
                color: Color(0xFF4f6d7a),
              ),
              title: const Text('Push Notifications'),
              subtitle: const Text('Receive updates about your graphs'),
              value: _notificationsEnabled,
              onChanged: (value) {
                setState(() => _notificationsEnabled = value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value
                          ? 'Notifications enabled'
                          : 'Notifications disabled',
                    ),
                  ),
                );
              },
            ),

            const Divider(),

            // Appearance section
            _buildSectionHeader('Appearance'),
            ListTile(
              leading: const Icon(
                Icons.dark_mode_outlined,
                color: Color(0xFF4f6d7a),
              ),
              title: const Text('Dark Mode'),
              subtitle: const Text('Coming soon'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dark mode coming soon')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields, color: Color(0xFF4f6d7a)),
              title: const Text('Font Size'),
              subtitle: const Text('Default'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Font settings coming soon')),
                );
              },
            ),

            const Divider(),

            // Data & Storage section
            _buildSectionHeader('Data & Storage'),
            ListTile(
              leading: const Icon(
                Icons.storage_outlined,
                color: Color(0xFF4f6d7a),
              ),
              title: const Text('Storage Usage'),
              subtitle: const Text('Manage cached data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Storage management coming soon'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.download_outlined,
                color: Color(0xFF4f6d7a),
              ),
              title: const Text('Export Data'),
              subtitle: const Text('Download your graphs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Export feature coming soon')),
                );
              },
            ),

            const Divider(),

            // About section
            _buildSectionHeader('About'),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Color(0xFF4f6d7a)),
              title: const Text('App Version'),
              subtitle: Text(_appVersion.isEmpty ? 'Loading...' : _appVersion),
            ),
            ListTile(
              leading: const Icon(
                Icons.description_outlined,
                color: Color(0xFF4f6d7a),
              ),
              title: const Text('Terms of Service'),
              trailing: const Icon(Icons.open_in_new, size: 20),
              onTap: () async {
                final url = Uri.parse('https://www.vegvisr.org/terms');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.privacy_tip_outlined,
                color: Color(0xFF4f6d7a),
              ),
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.open_in_new, size: 20),
              onTap: () async {
                final url = Uri.parse('https://www.vegvisr.org/privacy');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline, color: Color(0xFF4f6d7a)),
              title: const Text('Help & Support'),
              trailing: const Icon(Icons.open_in_new, size: 20),
              onTap: () async {
                final url = Uri.parse('https://www.vegvisr.org/help');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),

            const Divider(),

            // Account section
            _buildSectionHeader('Account'),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),

            const SizedBox(height: 32),

            // Footer
            Center(
              child: Column(
                children: [
                  Text(
                    'Hallo Vegvisr',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Powered by VEGR.AI',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Made with love in Norway',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF4f6d7a),
        ),
      ),
    );
  }
}
