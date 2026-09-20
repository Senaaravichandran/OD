import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/clerk_session.dart';

/// Sign-in options for one role.
///
/// Students get Google only: an OD is filed against a real, verified college
/// address, so there is no password door for them. Staff and the HOD also get
/// a password, because they need to sign in on shared devices and during
/// testing.
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
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _showPasswordForm = false;
  bool _busy = false;
  String? _error;

  bool get _isStudent => widget.role == UserRole.student;

  String get _roleLabel => switch (widget.role) {
        UserRole.student => 'Student',
        UserRole.advisor => 'Class Advisor',
        UserRole.hod => 'HOD',
      };

  @override
  void initState() {
    super.initState();
    if (widget.role == UserRole.hod) _email.text = AppConfig.hodEmail;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ClerkSession.passwordLogin(
        role: widget.role == UserRole.hod ? 'HOD' : 'STAFF',
        email: _email.text.trim(),
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
                'Use your official ${AppConfig.allowedDomain} account.',
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
                    onPressed: _busy ? null : () => setState(() => _showPasswordForm = true),
                    child: const Text('Sign in with a password instead'),
                  )
                else ...[
                  TextField(
                    controller: _email,
                    readOnly: widget.role == UserRole.hod,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: widget.role == UserRole.hod
                          ? 'HOD email'
                          : 'Your college email',
                      hintText: 'name${AppConfig.allowedDomain}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
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
}
