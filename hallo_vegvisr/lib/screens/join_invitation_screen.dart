import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/invitation_service.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import '../main.dart';

class JoinInvitationScreen extends StatefulWidget {
  final String inviteCode;

  const JoinInvitationScreen({super.key, required this.inviteCode});

  @override
  State<JoinInvitationScreen> createState() => _JoinInvitationScreenState();
}

class _JoinInvitationScreenState extends State<JoinInvitationScreen> {
  final _authService = AuthService();
  bool _isLoading = true;
  bool _isAccepting = false;
  InvitationDetails? _invitation;
  String? _userPhone;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadInvitation();
  }

  Future<void> _loadInvitation() async {
    setState(() => _isLoading = true);

    // Check login status
    _isLoggedIn = await _authService.isLoggedIn();
    if (_isLoggedIn) {
      _userPhone = await _authService.getPhone();
    }

    // Fetch invitation details
    final invitation = await InvitationService.getInvitationDetails(widget.inviteCode);

    if (mounted) {
      setState(() {
        _invitation = invitation;
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptInvitation() async {
    if (_userPhone == null) {
      // Save invite and redirect to login
      InvitationService.setPendingInvite(widget.inviteCode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to accept this invitation')),
        );
        context.go('/login');
      }
      return;
    }

    setState(() => _isAccepting = true);

    final result = await InvitationService.acceptInvitation(widget.inviteCode, _userPhone!);

    if (mounted) {
      setState(() => _isAccepting = false);

      if (result['success'] == true) {
        // Fetch new branding
        final branding = await BrandingService.fetchBrandingByPhone(_userPhone!);
        updateAppTheme(branding);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome to ${result['domain']}!'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to home
        context.go('/');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to accept invitation'),
            backgroundColor: Colors.red,
          ),
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
        title: const Text('Join Invitation'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/'),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading invitation...'),
          ],
        ),
      );
    }

    if (_invitation == null || !_invitation!.isValid) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Invalid Invitation',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _invitation?.errorMessage ?? 'This invitation is not valid.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Go to Home'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),

          // Brand logo
          if (_invitation!.logoUrl != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: CachedNetworkImage(
                imageUrl: _invitation!.logoUrl!,
                width: 120,
                height: 120,
                fit: BoxFit.contain,
                placeholder: (context, url) => const CircularProgressIndicator(),
                errorWidget: (context, url, error) => const Icon(
                  Icons.business,
                  size: 64,
                  color: Colors.grey,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF4f6d7a),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.business,
                size: 64,
                color: Colors.white,
              ),
            ),

          const SizedBox(height: 24),

          // Invitation text
          const Text(
            "You've been invited to join",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _invitation!.domain,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 16),

          // Role badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _getRoleColor(_invitation!.role).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _getRoleColor(_invitation!.role),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getRoleIcon(_invitation!.role),
                  size: 18,
                  color: _getRoleColor(_invitation!.role),
                ),
                const SizedBox(width: 8),
                Text(
                  'Joining as ${_invitation!.role}',
                  style: TextStyle(
                    color: _getRoleColor(_invitation!.role),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Login status
          if (!_isLoggedIn)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You need to log in to accept this invitation',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),

          if (_isLoggedIn && _userPhone != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Logged in as $_userPhone',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 32),

          // Accept button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isAccepting ? null : _acceptInvitation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4f6d7a),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isAccepting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _isLoggedIn ? 'Accept Invitation' : 'Log In to Accept',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 16),

          // Decline button
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Decline'),
          ),

          const SizedBox(height: 24),

          // Expiry info
          Text(
            'This invitation expires ${_formatExpiry(_invitation!.expiresAt)}',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.orange;
      case 'owner':
        return Colors.red;
      default:
        return const Color(0xFF4f6d7a);
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'owner':
        return Icons.verified_user;
      default:
        return Icons.person;
    }
  }

  String _formatExpiry(DateTime expiry) {
    final now = DateTime.now();
    final diff = expiry.difference(now);

    if (diff.inDays > 1) {
      return 'in ${diff.inDays} days';
    } else if (diff.inDays == 1) {
      return 'tomorrow';
    } else if (diff.inHours > 1) {
      return 'in ${diff.inHours} hours';
    } else if (diff.inMinutes > 1) {
      return 'in ${diff.inMinutes} minutes';
    } else {
      return 'soon';
    }
  }
}
