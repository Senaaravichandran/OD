import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../services/api_client.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'attachments_sheet.dart';

/// Record what came of an approved OD: participated, or won.
///
/// Only reachable once the HOD has sanctioned the request - the server refuses
/// a result before that, and the database refuses it again.
///
/// A result is a claim, so it cannot be filed until the evidence is attached:
/// the certificate and a photo from the event, plus the prize photo for a win.
/// A supporting document stays optional. For a team entry, every member's
/// contribution has to be named - the department credits people, not rows.
class ResultSheet extends StatefulWidget {
  const ResultSheet({super.key, required this.request});

  final ODRequest request;

  @override
  State<ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<ResultSheet> {
  final _formKey = GlobalKey<FormState>();
  final _projectName = TextEditingController();
  final _prize = TextEditingController();
  final _prizeDetails = TextEditingController();
  final _description = TextEditingController();
  final _contributions = <String, TextEditingController>{};
  final _od = ODService();

  String _status = 'PARTICIPATED';
  bool _busy = false;
  String? _error;

  bool get _won => _status == 'WON';

  /// Read back from the service rather than held, so attaching a file inside
  /// this sheet is reflected the moment it lands.
  ODRequest get _request => _od.allRequests.firstWhere(
        (r) => r.id == widget.request.id,
        orElse: () => widget.request,
      );

  @override
  void initState() {
    super.initState();
    _projectName.text = widget.request.eventName;
    for (final m in widget.request.team) {
      _contributions[m.id] =
          TextEditingController(text: m.contribution ?? '');
    }
  }

  @override
  void dispose() {
    _projectName.dispose();
    _prize.dispose();
    _prizeDetails.dispose();
    _description.dispose();
    for (final c in _contributions.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _attach() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AttachmentsSheet(request: _request),
    );
    // The sheet refreshes the service on its way out; rebuild against it.
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final missing = _request.missingEvidenceFor(_status);
    if (missing.isNotEmpty) {
      setState(() => _error =
          'Attach ${missing.map(evidenceLabel).join(', ')} before submitting.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _od.submitResult(
        requestId: widget.request.id,
        status: _status,
        projectName: _projectName.text.trim(),
        prize: _won ? _prize.text.trim() : null,
        prizeDetails: _won ? _prizeDetails.text.trim() : null,
        description: _description.text.trim(),
        teamContributions: _request.isTeam
            ? [
                for (final m in _request.team)
                  {
                    'id': m.id,
                    'contribution': _contributions[m.id]?.text.trim() ?? '',
                  }
              ]
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

  static String evidenceLabel(String kind) => switch (kind) {
        'CERTIFICATE' => 'the certificate',
        'WINNING_PHOTO' => 'the prize photo',
        'EVENT_PHOTO' => 'a photo from the event',
        _ => 'a supporting document',
      };

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final missing = request.missingEvidenceFor(_status);
    final ready = missing.isEmpty;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Submit result',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        request.eventName,
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'PARTICIPATED',
                          label: Text('Participated'),
                          icon: Icon(Icons.workspace_premium_outlined, size: 17),
                        ),
                        ButtonSegment(
                          value: 'WON',
                          label: Text('Won'),
                          icon: Icon(Icons.emoji_events_outlined, size: 17),
                        ),
                      ],
                      selected: {_status},
                      onSelectionChanged: (s) => setState(() {
                        _status = s.first;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 18),

                    TextFormField(
                      controller: _projectName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Project / event name',
                        prefixIcon: Icon(Icons.lightbulb_outline_rounded, size: 20),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter the project or event name.'
                          : null,
                    ),

                    if (_won) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _prize,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Prize / position',
                          hintText: '1st Prize, Runner Up, Best Paper…',
                          prefixIcon: Icon(Icons.military_tech_outlined, size: 20),
                        ),
                        // The server and the database both refuse a win with
                        // no prize, so catch it here rather than round-trip.
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Tell us which prize you won.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _prizeDetails,
                        decoration: const InputDecoration(
                          labelText: 'Prize details (optional)',
                          hintText: 'Cash award, certificate, trophy…',
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _description,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        alignLabelWithHint: true,
                        hintText: 'Briefly, what did you build or present?',
                      ),
                    ),

                    // -- who did what ----------------------------------------
                    if (request.isTeam && request.team.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const SectionHeader(title: 'Who did what'),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          'The department credits people, not entries. Say what '
                          'each member contributed.',
                          style: TextStyle(
                              fontSize: 12.5, color: AppTheme.muted, height: 1.4),
                        ),
                      ),
                      for (final m in request.team) ...[
                        TextFormField(
                          controller: _contributions[m.id],
                          maxLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: m.name,
                            alignLabelWithHint: true,
                            hintText: 'Built the backend, presented the paper…',
                            prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Tell us what ${m.name} contributed.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],

                    // -- evidence --------------------------------------------
                    const SizedBox(height: 8),
                    SectionHeader(
                      title: 'Evidence',
                      trailing: TextButton.icon(
                        onPressed: _busy ? null : _attach,
                        icon: const Icon(Icons.attach_file_rounded, size: 17),
                        label: const Text('Attach'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    _EvidenceList(
                      request: request,
                      resultStatus: _status,
                      onAttach: _busy ? null : _attach,
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 20),

                    FilledButton(
                      onPressed: _busy || !ready ? null : _submit,
                      child: Text(
                        _busy
                            ? 'Saving…'
                            : ready
                                ? 'Submit result'
                                : 'Attach the evidence first',
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

/// The evidence checklist. Shows what is needed for the chosen outcome, what
/// has already arrived, and what is still missing - so the disabled submit
/// button is never a mystery.
class _EvidenceList extends StatelessWidget {
  const _EvidenceList({
    required this.request,
    required this.resultStatus,
    required this.onAttach,
  });

  final ODRequest request;
  final String resultStatus;
  final VoidCallback? onAttach;

  static const _title = {
    'CERTIFICATE': 'Certificate',
    'EVENT_PHOTO': 'Photo from the event',
    'WINNING_PHOTO': 'Prize photo',
    'SUPPORTING_DOCUMENT': 'Supporting document',
  };

  @override
  Widget build(BuildContext context) {
    final have = request.files.map((f) => f.kind).toSet();
    final required = ODRequest.evidenceFor(resultStatus);
    final optionalAttached = have.contains('SUPPORTING_DOCUMENT');

    return Column(
      children: [
        for (final kind in required)
          _row(
            context,
            title: _title[kind] ?? kind,
            attached: have.contains(kind),
            optional: false,
          ),
        _row(
          context,
          title: _title['SUPPORTING_DOCUMENT']!,
          attached: optionalAttached,
          optional: true,
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required String title,
    required bool attached,
    required bool optional,
  }) {
    final colour = attached
        ? AppTheme.success
        : optional
            ? AppTheme.muted
            : AppTheme.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: attached ? AppTheme.tint(AppTheme.success) : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: attached
              ? AppTheme.success.withValues(alpha: 0.28)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            attached
                ? Icons.check_circle_rounded
                : optional
                    ? Icons.remove_circle_outline_rounded
                    : Icons.radio_button_unchecked_rounded,
            size: 19,
            color: colour,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              optional && !attached ? '$title (optional)' : title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: attached ? FontWeight.w600 : FontWeight.w500,
                color: attached ? AppTheme.ink : AppTheme.muted,
              ),
            ),
          ),
          if (!attached)
            TextButton(
              onPressed: onAttach,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Add'),
            ),
        ],
      ),
    );
  }
}
