import 'package:flutter/material.dart';

import '../../models/class_advisor.dart';
import '../../services/api_client.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// The HOD's roster of class advisors: add one, correct one, remove one.
///
/// Removing is a retirement, not a deletion. The OD requests an advisor
/// approved keep naming them, so last year's reports still read correctly;
/// what changes is that they can no longer sign in, their classes are
/// released, and the students in those classes are asked to choose again.
class ManageAdvisorsScreen extends StatefulWidget {
  const ManageAdvisorsScreen({super.key});

  @override
  State<ManageAdvisorsScreen> createState() => _ManageAdvisorsScreenState();
}

class _ManageAdvisorsScreenState extends State<ManageAdvisorsScreen> {
  final _od = ODService();

  List<ClassAdvisor>? _advisors;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final roster = await _od.advisorRoster();
      if (mounted) setState(() => _advisors = roster);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _apply(List<ClassAdvisor> roster) {
    if (mounted) setState(() => _advisors = roster);
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<List<ClassAdvisor>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdvisorEditor(existing: null, roster: _advisors ?? const []),
    );
    if (result != null) {
      _apply(result);
      if (mounted) showToast(context, 'Class advisor added.');
    }
  }

  Future<void> _edit(ClassAdvisor advisor) async {
    final result = await showModalBottomSheet<List<ClassAdvisor>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdvisorEditor(existing: advisor, roster: _advisors ?? const []),
    );
    if (result != null) {
      _apply(result);
      if (mounted) showToast(context, 'Class advisor updated.');
    }
  }

  Future<void> _remove(ClassAdvisor advisor) async {
    final holding = advisor.classes.isEmpty
        ? ''
        : '\n\n${advisor.classesLabel} will be left without an advisor, and '
            '${advisor.studentCount == 1 ? 'the student' : 'the ${advisor.studentCount} students'} '
            'in ${advisor.classes.length == 1 ? 'it' : 'them'} will be asked to choose again.';

    final ok = await confirm(
      context,
      title: 'Remove ${advisor.name}?',
      message: 'They will not be able to sign in any more.\n\n'
          'The ${advisor.requestCount == 1 ? 'OD' : '${advisor.requestCount} ODs'} '
          'they have already handled will keep their name, so past reports do '
          'not change.$holding',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await _od.removeAdvisor(advisor.id);
      _apply(result.roster);
      if (mounted) await _showRemoval(advisor, result.removal);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Says plainly who now needs looking after, rather than leaving the HOD to
  /// find out when a student cannot file an OD.
  Future<void> _showRemoval(ClassAdvisor advisor, AdvisorRemoval removal) async {
    if (removal.releasedClasses.isEmpty && removal.studentsToReassign.isEmpty) {
      showToast(context, '${advisor.name} has been removed.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Removed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${advisor.name} can no longer sign in.',
                style: const TextStyle(fontSize: 13.5, height: 1.4)),
            if (removal.releasedClasses.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Now without an advisor',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(removal.releasedClasses.join(', '),
                  style: const TextStyle(fontSize: 13, color: AppTheme.muted)),
            ],
            if (removal.studentsToReassign.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${removal.studentsToReassign.length} '
                '${removal.studentsToReassign.length == 1 ? 'student has' : 'students have'} '
                'been asked to choose their class again.',
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 6),
              ...removal.studentsToReassign.take(8).map(
                    (s) => Text('· $s',
                        style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                  ),
              if (removal.studentsToReassign.length > 8)
                Text('· and ${removal.studentsToReassign.length - 8} more',
                    style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
            ],
            const SizedBox(height: 12),
            const Text(
              'Assign someone to these classes so new requests have somewhere '
              'to go.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppTheme.muted),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final advisors = _advisors;
    final serving = advisors?.where((a) => a.isActive && !a.isHod).toList() ?? [];
    final hod = advisors?.where((a) => a.isHod).toList() ?? [];
    final retired = advisors?.where((a) => !a.isActive).toList() ?? [];

    // Which classes have nobody, so the gaps are visible rather than implied.
    final held = {
      for (final a in serving)
        for (final c in a.classes) c.key,
    };
    final gaps = [
      for (var year = 1; year <= 4; year++)
        for (final section in const ['A', 'B', 'C', 'D'])
          if (!held.contains('$year-$section')) '$year-$section',
    ];

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Class advisors')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add advisor'),
      ),
      body: advisors == null
          ? (_error != null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ErrorBanner(message: _error!),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Try again')),
                  ],
                )
              : const SkeletonList())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    const SizedBox(height: 12),
                  ],

                  if (gaps.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: AppTheme.tint(AppTheme.warning),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.report_problem_outlined,
                              size: 18, color: AppTheme.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No advisor for ${gaps.join(', ')}. Students in '
                              '${gaps.length == 1 ? 'that class' : 'those classes'} '
                              'cannot raise an OD until somebody is assigned.',
                              style: const TextStyle(
                                  fontSize: 12.5, color: AppTheme.warning, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),

                  SectionHeader(
                    title: 'Serving',
                    trailing: Text('${serving.length}',
                        style: const TextStyle(
                            fontSize: 12.5, color: AppTheme.muted)),
                  ),
                  if (serving.isEmpty)
                    const EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'No class advisors yet',
                      message: 'Add one so students have somewhere to send their ODs.',
                    ),
                  for (final a in serving)
                    _AdvisorTile(
                      advisor: a,
                      onEdit: _busy ? null : () => _edit(a),
                      onRemove: _busy ? null : () => _remove(a),
                    ),

                  if (hod.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const SectionHeader(title: 'Head of Department'),
                    for (final a in hod)
                      _AdvisorTile(
                        advisor: a,
                        onEdit: _busy ? null : () => _edit(a),
                        onRemove: null, // the department cannot remove its own head
                      ),
                  ],

                  if (retired.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SectionHeader(
                      title: 'Removed',
                      trailing: Text('${retired.length}',
                          style: const TextStyle(
                              fontSize: 12.5, color: AppTheme.muted)),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Kept so the ODs they approved still name them. Adding '
                        'the same address again brings the person back with '
                        'their history.',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.muted, height: 1.4),
                      ),
                    ),
                    for (final a in retired)
                      _AdvisorTile(advisor: a, onEdit: null, onRemove: null),
                  ],
                ],
              ),
            ),
    );
  }
}

class _AdvisorTile extends StatelessWidget {
  const _AdvisorTile({
    required this.advisor,
    required this.onEdit,
    required this.onRemove,
  });

  final ClassAdvisor advisor;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final retired = !advisor.isActive;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          advisor.name,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: retired ? AppTheme.muted : AppTheme.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (advisor.isHod) ...[
                        const SizedBox(width: 8),
                        StatusBadge(
                          label: 'HOD',
                          color: AppTheme.primary,
                          icon: Icons.verified_user_outlined,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    advisor.email,
                    style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  if (!advisor.isHod)
                    Text(
                      retired
                          ? 'Removed${advisor.retiredAt == null ? '' : ' · ${fmtDate(advisor.retiredAt!)}'}'
                          : advisor.classesLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: retired ? AppTheme.danger : AppTheme.primary,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    '${advisor.requestCount} OD${advisor.requestCount == 1 ? '' : 's'} handled'
                    '${advisor.isHod || retired ? '' : ' · ${advisor.studentCount} student${advisor.studentCount == 1 ? '' : 's'}'}',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            if (onEdit != null || onRemove != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (v) => v == 'edit' ? onEdit?.call() : onRemove?.call(),
                itemBuilder: (_) => [
                  if (onEdit != null)
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined, size: 19),
                        title: Text('Update details'),
                      ),
                    ),
                  if (onRemove != null)
                    const PopupMenuItem(
                      value: 'remove',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.person_remove_outlined,
                            size: 19, color: AppTheme.danger),
                        title: Text('Remove advisor',
                            style: TextStyle(color: AppTheme.danger)),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Adding a new advisor, or correcting an existing one.
///
/// The same sheet does both, because the fields are the same. The only
/// difference is that a new advisor must be given a password, while an
/// existing one keeps theirs unless the HOD types a new one.
class AdvisorEditor extends StatefulWidget {
  const AdvisorEditor({super.key, required this.existing, required this.roster});

  final ClassAdvisor? existing;
  final List<ClassAdvisor> roster;

  @override
  State<AdvisorEditor> createState() => _AdvisorEditorState();
}

class _AdvisorEditorState extends State<AdvisorEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _od = ODService();

  late Set<String> _classes;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  bool get _isNew => widget.existing == null;
  bool get _isHod => widget.existing?.isHod == true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _name.text = existing.name;
      _email.text = existing.email;
    }
    _classes = {for (final c in existing?.classes ?? const []) c.key};
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Who currently holds each class, so taking one is a visible decision
  /// rather than a surprise.
  String? _heldBy(String key) {
    for (final a in widget.roster) {
      if (!a.isActive || a.id == widget.existing?.id) continue;
      if (a.classes.any((c) => c.key == key)) return a.name;
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final classes = [
      for (final key in _classes)
        AdvisorClassRef(
          year: int.parse(key.split('-').first),
          section: key.split('-').last,
        ),
    ];

    try {
      final roster = _isNew
          ? await _od.createAdvisor(
              name: _name.text.trim(),
              email: _email.text.trim().toLowerCase(),
              password: _password.text,
              classes: classes,
            )
          : await _od.updateAdvisor(
              staffId: widget.existing!.id,
              name: _name.text.trim(),
              email: _email.text.trim().toLowerCase(),
              password: _password.text,
              classes: _isHod ? null : classes,
            );
      if (mounted) Navigator.pop(context, roster);
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
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isNew ? 'Add a class advisor' : 'Update ${widget.existing!.name}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _busy ? null : () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.badge_outlined, size: 20),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter their name.'
                          : null,
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Sign-in email',
                        helperText: 'They can sign in with this, by Google or by password.',
                        prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                      ),
                      validator: (v) {
                        final email = (v ?? '').trim();
                        if (email.isEmpty) return 'Enter their email address.';
                        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                          return 'That does not look like an email address.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: _isNew ? 'Password' : 'New password',
                        helperText: _isNew
                            ? 'At least 8 characters. Tell them what it is.'
                            : 'Leave blank to keep their current password.',
                        prefixIcon: const Icon(Icons.key_outlined, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      validator: (v) {
                        final password = v ?? '';
                        if (_isNew && password.isEmpty) {
                          return 'Give them a password.';
                        }
                        if (password.isNotEmpty && password.length < 8) {
                          return 'At least 8 characters.';
                        }
                        return null;
                      },
                    ),

                    if (!_isHod) ...[
                      const SizedBox(height: 20),
                      const SectionHeader(title: 'Classes they advise'),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Choosing a class that somebody else holds moves it '
                          'to this advisor.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.muted, height: 1.4),
                        ),
                      ),
                      for (var year = 1; year <= 4; year++) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 4),
                          child: Text(
                            'Year $year',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.muted),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final section in const ['A', 'B', 'C', 'D'])
                              _ClassChip(
                                label: section,
                                heldBy: _heldBy('$year-$section'),
                                selected: _classes.contains('$year-$section'),
                                onChanged: (on) => setState(() {
                                  if (on) {
                                    _classes.add('$year-$section');
                                  } else {
                                    _classes.remove('$year-$section');
                                  }
                                }),
                              ),
                          ],
                        ),
                      ],
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 20),

                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(
                        _busy
                            ? 'Saving…'
                            : _isNew
                                ? 'Add advisor'
                                : 'Save changes',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassChip extends StatelessWidget {
  const _ClassChip({
    required this.label,
    required this.heldBy,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final String? heldBy;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: onChanged,
      label: Text(
        heldBy == null ? label : '$label · $heldBy',
        style: const TextStyle(fontSize: 12.5),
      ),
      avatar: heldBy == null && !selected
          ? const Icon(Icons.person_off_outlined, size: 15, color: AppTheme.muted)
          : null,
      tooltip: heldBy == null ? 'Nobody holds this class' : 'Currently $heldBy',
    );
  }
}
