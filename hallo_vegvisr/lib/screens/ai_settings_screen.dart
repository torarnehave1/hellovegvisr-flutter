import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  bool _aiEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadAiPreferences();
  }

  Future<void> _loadAiPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _aiEnabled = prefs.getBool('ai_enabled') ?? true;
    });
  }

  Future<void> _saveAiPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_enabled', _aiEnabled);
  }

  void _returnToMenu() {
    context.go('/?openDrawer=true');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _returnToMenu();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF4f6d7a),
          foregroundColor: Colors.white,
          title: const Text('AI Settings'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _returnToMenu,
          ),
        ),
        body: ListView(
          children: [
            const SizedBox(height: 8),
            _buildSectionHeader('AI Assistant'),
            SwitchListTile(
              secondary: const Icon(
                Icons.smart_toy_outlined,
                color: Color(0xFF4f6d7a),
              ),
              title: const Text('Enable AI Chat'),
              subtitle: const Text('Use AI assistance when creating graphs'),
              value: _aiEnabled,
              onChanged: (value) async {
                setState(() => _aiEnabled = value);
                await _saveAiPreferences();
              },
            ),
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
