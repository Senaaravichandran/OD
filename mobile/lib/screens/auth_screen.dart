import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/od_request.dart' show AdvisorInfo;
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/clerk_session.dart';
import '../utils/validators.dart';

/// Sign-in options for one role.
///
/// Students get Google only: an OD is filed against a real, verified college
/// address, so there is no password door for them. Advisors and the HOD also
/// get a password, because they need to sign in on shared devices.
///
/// An advisor does not type an address - they pick themselves from the
/// department roster, which is also the only list of addresses the server will
/// accept as an advisor.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.role,
    required this.onSignedIn,
    required this.onNeedsRegistration,
    required this.onBack,
  });

  final UserRole role;
  final Future<void> Function(AppUser user) onSignedIn;
  final void Function(String email, String regToken, UserRole role) onNeedsRegistration;
  final VoidCallback onBack;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _password = TextEditingController();

  bool _showPasswordForm = false;
  bool _busy = false;
  String? _error;

  List<AdvisorInfo> _advisors = [];
  AdvisorInfo? _selectedAdvisor;
  bool _loadingAdvisors = false;

  bool get _isStudent => widget.role == UserRole.student;
  bool get _isAdvisor => widget.role == UserRole.advisor;

  String get _roleLabel => switch (widget.role) {
        UserRole.student => 'Student',
        UserRole.advisor => 'Class Advisor',
        UserRole.hod => 'HOD',
      };

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadAdvisors() async {
    setState(() => _loadingAdvisors = true);
    try {
      final list = await ClerkSession.advisors();
      if (mounted) {
        setState(() {
          _advisors = list;
          _loadingAdvisors = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loadingAdvisors = false;
        });
      }
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final authState = ClerkAuth.of(context, listen: false);
      await authState.ssoSignIn(context, clerk.Strategy.oauthGoogle);
      // On success the Clerk session changes and the gate above this screen
      // takes over, so there is nothing more to do here.
    } catch (err) {
      if (mounted) setState(() => _error = '$err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _passwordSignIn() async {
    final email = _isAdvisor ? _selectedAdvisor?.email : AppConfig.hodEmail;
    if (email == null) {
      setState(() => _error = 'Choose which class advisor you are.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ClerkSession.passwordLogin(
        role: _isAdvisor ? 'STAFF' : 'HOD',
        email: email,
        password: _password.text,
      );
      if (!mounted) return;
      if (result.needsRegistration) {
        widget.onNeedsRegistration(result.email ?? '', result.regToken!, widget.role);
      } else {
        await widget.onSignedIn(result.user!);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPasswordForm() {
    setState(() => _showPasswordForm = true);
    if (_isAdvisor && _advisors.isEmpty) _loadAdvisors();
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        leading: BackButton(onPressed: _busy ? null : widget.onBack),
        title: Text('Sign in as $_roleLabel'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/college_logo.png', height: 72),
              const SizedBox(height: 24),
              Text(
                _isAdvisor
                    ? 'Only the department’s listed class advisors can sign in here.'
                    : 'Use your official ${AppConfig.allowedDomain} account.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 28),

              OutlinedButton.icon(
                onPressed: _busy ? null : _google,
                icon: const Icon(Icons.g_mobiledata, size: 30),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  foregroundColor: Colors.black87,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),

              if (!_isStudent) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: TextStyle(color: Colors.grey.shade600)),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_showPasswordForm)
                  TextButton(
                    onPressed: _busy ? null : _openPasswordForm,
                    child: const Text('Sign in with a password instead'),
                  )
                else ...[
                  if (_isAdvisor) _advisorPicker() else _hodIdentity(),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _busy ? null : _passwordSignIn(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _busy ? null : _passwordSignIn,
                    child: Text(_busy ? 'Signing in…' : 'Sign in'),
                  ),
                ],
              ],

              if (_error != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
                ),
              ],

              if (_busy) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The advisor chooses their class rather than typing an address, so the
  /// address is always one the server will accept.
  Widget _advisorPicker() {
    if (_loadingAdvisors) {
      return const Row(
        children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Loading class advisors…'),
        ],
      );
    }
    if (_advisors.isEmpty) {
      return Row(
        children: [
          const Expanded(child: Text('Could not load the advisor list.')),
          TextButton(onPressed: _loadAdvisors, child: const Text('Retry')),
        ],
      );
    }
    return DropdownButtonFormField<AdvisorInfo>(
      initialValue: _selectedAdvisor,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'You are',
        border: OutlineInputBorder(),
      ),
      items: _advisors
          .map((a) => DropdownMenuItem(
                value: a,
                child: Text(
                  '${a.name} — ${yearLabel(a.year)} ${a.section}',
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: (v) => setState(() => _selectedAdvisor = v),
    );
  }

  Widget _hodIdentity() {
    return TextField(
      controller: TextEditingController(text: AppConfig.hodEmail),
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'HOD email',
        border: OutlineInputBorder(),
      ),
    );
  }
}
