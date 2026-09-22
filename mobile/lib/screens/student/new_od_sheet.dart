import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../models/user.dart';
import '../../services/api_client.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Raise a new OD request.
///
/// The advisor is not a field. It comes from the student's class on the
/// server, so an OD cannot be routed to someone else's advisor by editing the
/// request - the screen only shows where it is going.
class NewOdSheet extends StatefulWidget {
  const NewOdSheet({super.key, required this.user});

  final AppUser user;

  @override
  State<NewOdSheet> createState() => _NewOdSheetState();
}

class _NewOdSheetState extends State<NewOdSheet> {
  final _formKey = GlobalKey<FormState>();
  final _eventName = TextEditingController();
  final _description = TextEditingController();
  final _members = <TextEditingController>[];
  final _od = ODService();

  String _eventType = AppConfig.eventTypes.first;
  String _submissionType = 'SOLO';
  DateTime _eventDate = DateTime.now().add(const Duration(days: 3));
  int _dayCount = 1;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _members.add(TextEditingController(
      text: '${widget.user.name} (${widget.user.registerNumber ?? ''})',
    ));
  }

  @override
  void dispose() {
    _eventName.dispose();
    _description.dispose();
    for (final c in _members) {
      c.dispose();
    }
    super.dispose();
  }

  /// The last day the OD covers. One day means it ends where it starts.
  DateTime get _endDate => _eventDate.add(Duration(days: _dayCount - 1));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'First day of the event',
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  /// Picking the last day instead sets the number of days, so the two
  /// controls can never disagree.
  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _eventDate,
      lastDate: _eventDate.add(const Duration(days: 29)),
      helpText: 'Last day of the event',
    );
    if (picked == null) return;
    final days = picked.difference(_eventDate).inDays + 1;
    setState(() => _dayCount = days.clamp(1, 30));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _od.createOd(
        eventType: _eventType,
        eventName: _eventName.text.trim(),
        eventDate: _eventDate,
        eventEndDate: _endDate,
        dayCount: _dayCount,
        eventDay: weekdayOf(_eventDate),
        description: _description.text.trim(),
        submissionType: _submissionType,
        teamMembers: _submissionType == 'TEAM'
            ? _members.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList()
            : const [],
      );
      if (mounted) Navigator.pop(context, true);
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
          const _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'New OD request',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
                    _AdvisorLine(user: widget.user),
                    const SizedBox(height: 16),

                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'SOLO',
                          label: Text('Individual'),
                          icon: Icon(Icons.person_outline_rounded, size: 17),
                        ),
                        ButtonSegment(
                          value: 'TEAM',
                          label: Text('Team'),
                          icon: Icon(Icons.groups_outlined, size: 17),
                        ),
                      ],
                      selected: {_submissionType},
                      onSelectionChanged: (s) =>
                          setState(() => _submissionType = s.first),
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _eventType,
                      decoration: const InputDecoration(
                        labelText: 'Event type',
                        prefixIcon: Icon(Icons.category_outlined, size: 20),
                      ),
                      items: AppConfig.eventTypes
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => _eventType = v!),
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _eventName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Event name',
                        prefixIcon: Icon(Icons.event_outlined, size: 20),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the event name.'
                          : null,
                    ),
                    const SizedBox(height: 14),

                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(10),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'First day',
                          prefixIcon: Icon(Icons.calendar_today_outlined, size: 19),
                        ),
                        child: Text(
                          '${fmtDate(_eventDate)} · ${weekdayOf(_eventDate)}',
                          style: const TextStyle(fontSize: 14.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    _DayCount(
                      days: _dayCount,
                      onChanged: (d) => setState(() => _dayCount = d),
                    ),
                    const SizedBox(height: 14),

                    InkWell(
                      onTap: _pickEndDate,
                      borderRadius: BorderRadius.circular(10),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Last day',
                          prefixIcon: const Icon(Icons.event_available_outlined, size: 19),
                          // The last day follows from the first day and the
                          // count; tapping it is a shortcut, not a third
                          // independent value.
                          helperText: _dayCount == 1
                              ? 'A one-day event'
                              : '$_dayCount days of OD',
                        ),
                        child: Text(
                          '${fmtDate(_endDate)} · ${weekdayOf(_endDate)}',
                          style: const TextStyle(fontSize: 14.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (_submissionType == 'TEAM') ...[
                      _TeamMembers(
                        controllers: _members,
                        onAdd: () {
                          if (_members.length < 5) {
                            setState(() => _members.add(TextEditingController()));
                          }
                        },
                        onRemove: (i) {
                          if (_members.length > 1) {
                            setState(() => _members.removeAt(i).dispose());
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                    ],

                    TextFormField(
                      controller: _description,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        alignLabelWithHint: true,
                        hintText: 'What is the event, and why do you need the OD?',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Add a short description.'
                          : null,
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 20),

                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_busy ? 'Submitting…' : 'Submit request'),
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

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.border,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _AdvisorLine extends StatelessWidget {
  const _AdvisorLine({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_ind_outlined, size: 19, color: AppTheme.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Goes to',
                    style: TextStyle(fontSize: 11, color: AppTheme.muted)),
                Text(
                  user.advisorName ?? 'Your class advisor',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
          ),
          Text(
            user.classDisplay,
            style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _TeamMembers extends StatelessWidget {
  const _TeamMembers({
    required this.controllers,
    required this.onAdd,
    required this.onRemove,
  });

  final List<TextEditingController> controllers;
  final VoidCallback onAdd;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Team members',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            if (controllers.length < 5)
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controllers[i],
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: i == 0 ? 'You' : 'Member ${i + 1}',
                      prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
                    ),
                  ),
                ),
                if (controllers.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                    color: AppTheme.danger,
                    onPressed: () => onRemove(i),
                  ),
              ],
            ),
          ),
        const Text(
          'Up to 5 members, including you.',
          style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
        ),
      ],
    );
  }
}


/// How many days the OD covers. A stepper rather than a text field: the
/// answer is almost always one to three, and typing invites "0" and "1O".
class _DayCount extends StatelessWidget {
  const _DayCount({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Number of days',
        prefixIcon: Icon(Icons.date_range_outlined, size: 19),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              days == 1 ? '1 day' : '$days days',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
            onPressed: days > 1 ? () => onChanged(days - 1) : null,
            tooltip: 'One day fewer',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
            onPressed: days < 30 ? () => onChanged(days + 1) : null,
            tooltip: 'One day more',
          ),
        ],
      ),
    );
  }
}
