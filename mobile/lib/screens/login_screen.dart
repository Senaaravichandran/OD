import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/clerk_session.dart';
import '../utils/validators.dart';

/// Shown once Clerk reports a signed-in user.
///
/// Clerk has already verified who they are, so all that is left is to trade the
/// Clerk session for an app session and, the first time only, collect the
/// details Clerk does not hold (register number, year, section).
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authState,
    required this.onLogin,
  });

  final ClerkAuthState authState;
  final Future<void> Function(AppUser user) onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = true;
  String? _error;
  String? _email;
  String? _regToken;

  @override
  void initState() {
    super.initState();
    _exchange();
  }

  Future<void> _exchange() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ClerkSession.exchange(widget.authState);
      if (!mounted) return;
      if (result.needsRegistration) {
        setState(() {
          _email = result.email;
          _regToken = result.regToken;
          _busy = false;
        });
      } else {
        await widget.onLogin(result.user!);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await widget.authState.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Signing you in…'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _exchange, child: const Text('Try again')),
                TextButton(
                  onPressed: _signOut,
                  child: const Text('Sign out and use another account'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _RegistrationForm(
      email: _email ?? '',
      regToken: _regToken!,
      onRegistered: widget.onLogin,
      onCancel: _signOut,
    );
  }
}

class _RegistrationForm extends StatefulWidget {
  const _RegistrationForm({
    required this.email,
    required this.regToken,
    required this.onRegistered,
    required this.onCancel,
  });

  final String email;
  final String regToken;
  final Future<void> Function(AppUser user) onRegistered;
  final Future<void> Function() onCancel;

  @override
  State<_RegistrationForm> createState() => _RegistrationFormState();
}

class _RegistrationFormState extends State<_RegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _rollNumber = TextEditingController();
  final _batch = TextEditingController();
  final _staffCode = TextEditingController();

  String _role = 'STUDENT';
  int? _year;
  String? _section;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final y = DateTime.now().year;
    _batch.text = '${y - 1}-${y + 3}';
  }

  @override
  void dispose() {
    _name.dispose();
    _rollNumber.dispose();
    _batch.dispose();
    _staffCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ClerkSession.register(
        regToken: widget.regToken,
        role: _role,
        name: _name.text.trim(),
        year: _year,
        section: _section,
        rollNumber: _role == 'STUDENT' ? _rollNumber.text.trim() : null,
        batch: _role == 'STAFF' ? _batch.text.trim() : null,
        staffCode: _role == 'STAFF' ? _staffCode.text : null,
      );
      await widget.onRegistered(user);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Image.asset('assets/college_logo.png', height: 72),
                const SizedBox(height: 20),
                const Text(
                  'Complete your profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Signed in as ${widget.email}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 24),

                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'STUDENT', label: Text('Student')),
                    ButtonSegment(value: 'STAFF', label: Text('Class Advisor')),
                  ],
                  selected: {_role},
                  onSelectionChanged: (s) => setState(() => _role = s.first),
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter your name.' : null,
                ),
                const SizedBox(height: 16),

                if (_role == 'STUDENT') ...[
                  TextFormField(
                    controller: _rollNumber,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Register number',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter your register number.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],

                DropdownButtonFormField<int>(
                  initialValue: _year,
                  decoration: const InputDecoration(
                    labelText: 'Year',
                    border: OutlineInputBorder(),
                  ),
                  items: AppConfig.years
                      .map((y) => DropdownMenuItem(value: y, child: Text(yearLabel(y))))
                      .toList(),
                  onChanged: (v) => setState(() => _year = v),
                  validator: (v) => v == null ? 'Choose your year.' : null,
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: _section,
                  decoration: const InputDecoration(
                    labelText: 'Section',
                    border: OutlineInputBorder(),
                  ),
                  items: AppConfig.sections
                      .map((s) => DropdownMenuItem(value: s, child: Text('Section $s')))
                      .toList(),
                  onChanged: (v) => setState(() => _section = v),
                  validator: (v) => v == null ? 'Choose your section.' : null,
                ),
                const SizedBox(height: 16),

                if (_role == 'STAFF') ...[
                  TextFormField(
                    controller: _batch,
                    decoration: const InputDecoration(
                      labelText: 'Batch',
                      hintText: '2023-2027',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => validateBatch(v ?? ''),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _staffCode,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Staff code',
                      helperText: 'Provided by the department',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Enter the staff code.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],

                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
                  ),
                  const SizedBox(height: 16),
                ],

                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Saving…' : 'Continue'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => widget.onCancel(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
