import 'package:flutter/material.dart';

import '../models/od_request.dart' show ClassSection, ClassYear;
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/clerk_session.dart';
import '../utils/validators.dart';

/// Collects the details the identity provider does not hold, the first time
/// someone signs in.
///
/// A student is never asked to pick an advisor. They pick their year, then the
/// section - and only the sections that year actually has - and the advisor
/// follows from the department's roster. That removes the whole class of
/// mistakes where a student attaches themselves to the wrong advisor.
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
  late String _role;
  int? _year;
  String? _section;
  List<ClassYear> _classes = [];
  bool _loadingClasses = true;
  String? _classesError;
  bool _busy = false;
  String? _error;

  /// The sections that exist in the chosen year.
  List<ClassSection> get _sectionsForYear {
    if (_year == null) return const [];
    final match = _classes.where((c) => c.year == _year);
    return match.isEmpty ? const [] : match.first.sections;
  }

  /// The advisor implied by the chosen year and section.
  ClassSection? get _resolvedClass {
    if (_section == null) return null;
    final match = _sectionsForYear.where((s) => s.section == _section);
    return match.isEmpty ? null : match.first;
  }

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole == UserRole.student ? 'STUDENT' : 'STAFF';
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() {
      _loadingClasses = true;
      _classesError = null;
    });
    try {
      final list = await ClerkSession.classes();
      if (mounted) {
        setState(() {
          _classes = list;
          _loadingClasses = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _classesError = e.message;
          _loadingClasses = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _rollNumber.dispose();
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
        rollNumber: _rollNumber.text.trim(),
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

                ..._classPickers(),

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

  /// Student: year and section come from the roster, and the advisor is shown
  /// rather than chosen.
  List<Widget> _classPickers() {
    if (_loadingClasses) {
      return const [
        Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Loading classes…'),
            ],
          ),
        ),
      ];
    }

    if (_classesError != null || _classes.isEmpty) {
      return [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _classesError ?? 'Could not load the class list.',
                style: TextStyle(color: Colors.red.shade900),
              ),
              TextButton(onPressed: _loadClasses, child: const Text('Try again')),
            ],
          ),
        ),
      ];
    }

    return [
      DropdownButtonFormField<int>(
        initialValue: _year,
        decoration: const InputDecoration(
          labelText: 'Year',
          border: OutlineInputBorder(),
        ),
        items: _classes
            .map((c) => DropdownMenuItem(value: c.year, child: Text(yearLabel(c.year))))
            .toList(),
        onChanged: (v) => setState(() {
          _year = v;
          _section = null; // sections differ per year
        }),
        validator: (v) => v == null ? 'Choose your year.' : null,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: _section,
        decoration: InputDecoration(
          labelText: 'Section',
          border: const OutlineInputBorder(),
          helperText: _year == null ? 'Choose your year first' : null,
        ),
        items: _sectionsForYear
            .map((s) => DropdownMenuItem(value: s.section, child: Text('Section ${s.section}')))
            .toList(),
        onChanged: _year == null ? null : (v) => setState(() => _section = v),
        validator: (v) => v == null ? 'Choose your section.' : null,
      ),
      const SizedBox(height: 16),
      _advisorPreview(),
    ];
  }

  /// Shows the advisor the chosen class implies. Read-only by design.
  Widget _advisorPreview() {
    final resolved = _resolvedClass;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: resolved == null ? const Color(0xFFF1F5F9) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: resolved == null ? const Color(0xFFE2E8F0) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.assignment_ind_outlined,
            size: 20,
            color: resolved == null ? Colors.black38 : const Color(0xFF3350B0),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your class advisor',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  resolved?.advisorName ?? 'Choose your year and section',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: resolved == null ? Colors.black45 : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
