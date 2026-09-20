import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/od_request.dart' show AdvisorInfo;
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/clerk_session.dart';
import '../utils/validators.dart';

/// Collects the details the identity provider does not hold, the first time
/// someone signs in.
///
/// For a student that includes their class advisor. The advisor is chosen once
/// and then stays fixed, so every OD they raise goes to the same person; it can
/// still be corrected later from the dashboard if they picked the wrong one.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    required this.email,
    required this.regToken,
    required this.initialRole,
    required this.onRegistered,
    required this.onCancel,
  });

  final String email;
  final String regToken;
  final UserRole initialRole;
  final Future<void> Function(AppUser user) onRegistered;
  final Future<void> Function() onCancel;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _rollNumber = TextEditingController();
  final _batch = TextEditingController();
  final _staffCode = TextEditingController();

  late String _role;
  int? _year;
  String? _section;
  String? _advisorEmail;
  List<AdvisorInfo> _advisors = [];
  bool _loadingAdvisors = true;
  bool _busy = false;
  String? _error;

  bool get _isStudent => _role == 'STUDENT';

  @override
  void initState() {
    super.initState();
    final y = DateTime.now().year;
    _batch.text = '${y - 1}-${y + 3}';
    _role = widget.initialRole == UserRole.student ? 'STUDENT' : 'STAFF';
    _loadAdvisors();
  }

  Future<void> _loadAdvisors() async {
    try {
      final list = await ClerkSession.advisors();
      if (mounted) {
        setState(() {
          _advisors = list;
          _loadingAdvisors = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAdvisors = false);
    }
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
    if (_isStudent && _advisorEmail == null) {
      setState(() => _error = 'Choose your class advisor.');
      return;
    }
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
        rollNumber: _isStudent ? _rollNumber.text.trim() : null,
        batch: _isStudent ? null : _batch.text.trim(),
        staffCode: _isStudent ? null : _staffCode.text,
        advisorEmail: _isStudent ? _advisorEmail : null,
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

                if (_isStudent) ...[
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

                if (_isStudent) _advisorField(),

                if (!_isStudent) ...[
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
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter the staff code.' : null,
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

  Widget _advisorField() {
    if (_loadingAdvisors) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Loading class advisors…'),
          ],
        ),
      );
    }

    if (_advisors.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No class advisors have registered yet.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your class advisor needs to sign in to the app once before you '
              'can be attached to them. Please try again after they have.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() => _loadingAdvisors = true);
                _loadAdvisors();
              },
              child: const Text('Check again'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: _advisorEmail,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Class advisor',
          helperText: 'Every OD you raise goes to this advisor',
          border: OutlineInputBorder(),
        ),
        items: _advisors
            .map((a) => DropdownMenuItem(
                  value: a.email,
                  child: Text(
                    '${a.name} — ${yearLabel(a.year)} ${a.section}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList(),
        onChanged: (v) => setState(() => _advisorEmail = v),
        validator: (v) => v == null ? 'Choose your class advisor.' : null,
      ),
    );
  }
}
