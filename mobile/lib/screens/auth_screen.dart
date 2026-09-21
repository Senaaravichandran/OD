import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Sign-in options for one role.
///
/// Students get Google only: an OD is filed against a real, verified college
/// address, so there is no password door for them. Staff and the HOD also get
/// a password, because they need to sign in on shared devices.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.role,
    required this.onBack,
    required this.onFirebaseSignedIn,
    required this.onStaffSignedIn,
  });

  final UserRole role;
  final VoidCallback onBack;
  final Future<void> Function() onFirebaseSignedIn;
  final Future<void> Function(AppUser user) onStaffSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _showPassword = false;
  bool _obscure = true;
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
      final user = await AuthService.signInWithGoogle();
      if (user == null) {
        setState(() => _busy = false); // cancelled at the picker
        return;
      }
      await widget.onFirebaseSignedIn();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _passwordSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ApiClient.callPublic('PASSWORD_LOGIN', payload: {
        'email': _email.text.trim(),
        'password': _password.text,
      });
      final user = AppUser.fromJson(
        res['user'] as Map<String, dynamic>,
        staffToken: res['token']?.toString(),
      );
      await widget.onStaffSignedIn(user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _busy ? null : widget.onBack),
        title: Text('Sign in as $_roleLabel'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Image.asset('assets/app_icon.png', height: 88)),
              const SizedBox(height: 22),
              Text(
                _isStudent
                    ? 'Use your college ${AppConfig.allowedDomain} account.'
                    : 'Only the department’s listed staff can sign in here.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted, height: 1.45),
              ),
              const SizedBox(height: 28),

              OutlinedButton.icon(
                onPressed: _busy ? null : _google,
                icon: Image.asset(
                  'assets/app_icon.png',
                  height: 0,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),

              if (!_isStudent) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_showPassword)
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _showPassword = true),
                    child: const Text('Sign in with a password instead'),
                  )
                else
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _email,
                          readOnly: widget.role == UserRole.hod,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: widget.role == UserRole.hod
                                ? 'HOD email'
                                : 'Your official email',
                            hintText: 'name${AppConfig.allowedDomain}',
                            prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter your email address.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter your password.'
                              : null,
                          onFieldSubmitted: (_) => _busy ? null : _passwordSignIn(),
                        ),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _busy ? null : _passwordSignIn,
                          child: Text(_busy ? 'Signing in…' : 'Sign in'),
                        ),
                      ],
                    ),
                  ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 20),
                ErrorBanner(message: _error!),
              ],

              if (_busy) ...[
                const SizedBox(height: 22),
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
