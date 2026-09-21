import 'package:flutter/material.dart';

import '../models/od_request.dart' show ClassSection, ClassYear;
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/od_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The first-run profile, for students only.
///
/// Staff never reach this screen: they are on the department roster already,
/// and nobody who is not on it can become an advisor.
///
/// A student is never asked to pick an advisor. They pick their year, then the
/// section - and only the sections that year actually runs - and the advisor
/// follows from the roster. That removes the whole class of mistakes where a
/// student attaches themselves to the wrong advisor.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    required this.email,
    required this.suggestedName,
    required this.onDone,
    required this.onCancel,
  });

  final String email;
  final String suggestedName;
  final Future<void> Function(AppUser user) onDone;
  final VoidCallback onCancel;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _registerNumber = TextEditingController();
  final _od = ODService();

  List<ClassYear> _classes = [];
  int? _year;
  String? _section;
  bool _loading = true;
  String? _loadError;
  bool _busy = false;
  String? _error;

  List<ClassSection> get _sectionsForYear {
    if (_year == null) return const [];
    final match = _classes.where((c) => c.year == _year);
    return match.isEmpty ? const [] : match.first.sections;
  }

  ClassSection? get _resolved {
    if (_section == null) return null;
    final match = _sectionsForYear.where((s) => s.section == _section);
    return match.isEmpty ? null : match.first;
  }

  @override
  void initState() {
    super.initState();
    _name.text = widget.suggestedName;
    _loadClasses();
  }

  @override
  void dispose() {
    _name.dispose();
    _registerNumber.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final classes = await _od.loadClasses(force: true);
      if (mounted) {
        setState(() {
          _classes = classes;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await _od.completeProfile(
        name: _name.text.trim(),
        registerNumber: _registerNumber.text.trim().toUpperCase(),
        year: _year!,
        section: _section!,
      );
      await widget.onDone(user);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete your profile'),
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onCancel,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.tint(AppTheme.primary),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_rounded,
                          size: 20, color: AppTheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Signed in as',
                              style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
                            ),
                            Text(
                              widget.email,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter your name.' : null,
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _registerNumber,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Register number',
                    prefixIcon: Icon(Icons.badge_outlined, size: 20),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter your register number.'
                      : null,
                ),
                const SizedBox(height: 14),

                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Loading classes…',
                            style: TextStyle(color: AppTheme.muted)),
                      ],
                    ),
                  )
                else if (_loadError != null)
                  ErrorBanner(message: _loadError!, onRetry: _loadClasses)
                else ...[
                  DropdownButtonFormField<int>(
                    initialValue: _year,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      prefixIcon: Icon(Icons.school_outlined, size: 20),
                    ),
                    items: _classes
                        .map((c) => DropdownMenuItem(
                              value: c.year,
                              child: Text('Year ${c.year}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _year = v;
                      _section = null; // sections differ per year
                    }),
                    validator: (v) => v == null ? 'Choose your year.' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _section,
                    decoration: InputDecoration(
                      labelText: 'Section',
                      prefixIcon: const Icon(Icons.group_outlined, size: 20),
                      helperText: _year == null ? 'Choose your year first' : null,
                    ),
                    items: _sectionsForYear
                        .map((s) => DropdownMenuItem(
                              value: s.section,
                              child: Text('Section ${s.section}'),
                            ))
                        .toList(),
                    onChanged:
                        _year == null ? null : (v) => setState(() => _section = v),
                    validator: (v) => v == null ? 'Choose your section.' : null,
                  ),
                  const SizedBox(height: 14),
                  _AdvisorPreview(resolved: _resolved),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 4),
                  ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 10),

                FilledButton(
                  onPressed: _busy || _loading ? null : _submit,
                  child: Text(_busy ? 'Saving…' : 'Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the advisor the chosen class implies. Read-only by design.
class _AdvisorPreview extends StatelessWidget {
  const _AdvisorPreview({required this.resolved});

  final ClassSection? resolved;

  @override
  Widget build(BuildContext context) {
    final known = resolved != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: known ? AppTheme.tint(AppTheme.primary) : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: known ? AppTheme.primary.withValues(alpha: 0.22) : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.assignment_ind_outlined,
            size: 20,
            color: known ? AppTheme.primary : AppTheme.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your class advisor',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  resolved?.advisorName ?? 'Choose your year and section',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: known ? AppTheme.ink : AppTheme.muted,
                  ),
                ),
                if (known) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Every OD you raise goes to them',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
