import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../services/api_client.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Record what came of an approved OD: participated, or won.
///
/// Only reachable once the HOD has sanctioned the request - the server refuses
/// a result before that, and the database refuses it again.
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
  final _od = ODService();

  String _status = 'PARTICIPATED';
  bool _busy = false;
  String? _error;

  bool get _won => _status == 'WON';

  @override
  void initState() {
    super.initState();
    _projectName.text = widget.request.eventName;
  }

  @override
  void dispose() {
    _projectName.dispose();
    _prize.dispose();
    _prizeDetails.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
                        widget.request.eventName,
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
                      onSelectionChanged: (s) => setState(() => _status = s.first),
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

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 20),

                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_busy ? 'Saving…' : 'Submit result'),
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
