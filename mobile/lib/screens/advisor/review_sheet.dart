import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../services/api_client.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Review one OD request and decide on it.
///
/// Used by both the advisor and the HOD; [isHod] only changes the wording and
/// which endpoint is called. The server decides whether the decision is
/// allowed at all - an HOD acting before the advisor is refused there.
class ReviewSheet extends StatefulWidget {
  const ReviewSheet({
    super.key,
    required this.request,
    required this.isHod,
  });

  final ODRequest request;
  final bool isHod;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  final _remarks = TextEditingController();
  final _od = ODService();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    final r = widget.request;
    final ok = await confirm(
      context,
      title: approve
          ? (widget.isHod ? 'Sanction this OD?' : 'Approve and forward?')
          : 'Reject this OD?',
      message: approve
          ? (widget.isHod
              ? '${r.studentName} will be notified that the OD is sanctioned.'
              : 'It will go to the HOD for final sanction, and ${r.studentName} will be told.')
          : '${r.studentName} will be notified that the request was rejected.',
      confirmLabel: approve ? 'Approve' : 'Reject',
      destructive: !approve,
    );
    if (!ok || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.isHod) {
        await _od.hodDecide(
          requestId: r.id,
          approve: approve,
          remarks: _remarks.text.trim(),
        );
      } else {
        await _od.advisorDecide(
          requestId: r.id,
          approve: approve,
          remarks: _remarks.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, approve ? 'approved' : 'rejected');
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
    final r = widget.request;
    // The HOD can only act once the advisor has recommended. The server
    // enforces it; this keeps the button honest rather than failing on tap.
    final blocked = widget.isHod && r.isPendingAdvisor;

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
                      Text(
                        r.eventName,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        r.referenceNo,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StatusBadge(
                    label: r.statusDisplay,
                    color: r.statusColor,
                    icon: r.statusIcon,
                  ),
                  const SizedBox(height: 16),

                  const SectionHeader(title: 'Student'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Column(
                        children: [
                          DetailRow(label: 'Name', value: r.studentName),
                          DetailRow(label: 'Register no.', value: r.registerNumber),
                          DetailRow(label: 'Class', value: 'Year ${r.year} · Section ${r.section}'),
                          DetailRow(label: 'Email', value: r.studentEmail),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const SectionHeader(title: 'Event'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Column(
                        children: [
                          DetailRow(label: 'Type', value: r.eventType),
                          DetailRow(label: 'Date', value: '${fmtDate(r.eventDate)} · ${r.eventDay}'),
                          DetailRow(
                            label: 'Participation',
                            value: r.isTeam ? 'Team (${r.teamMembers.length})' : 'Individual',
                          ),
                          if (r.isTeam && r.teamMembers.isNotEmpty)
                            DetailRow(label: 'Members', value: r.teamMembers.join(', ')),
                          DetailRow(label: 'Raised on', value: fmtDateTime(r.createdAt)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const SectionHeader(title: 'Description'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        r.description,
                        style: const TextStyle(fontSize: 13.5, height: 1.5),
                      ),
                    ),
                  ),

                  if (r.advisorRemarks != null && r.advisorRemarks!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SectionHeader(title: 'Class advisor remarks'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.advisorName,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.muted),
                            ),
                            const SizedBox(height: 4),
                            Text(r.advisorRemarks!,
                                style: const TextStyle(fontSize: 13.5, height: 1.45)),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  if (blocked)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.tint(AppTheme.warning),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.hourglass_top_rounded,
                              size: 18, color: AppTheme.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Waiting for ${r.advisorName} to review. '
                              'You can sanction this once the class advisor has approved it.',
                              style: const TextStyle(
                                  fontSize: 12.5, color: AppTheme.warning, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (r.isClosed)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        'This request is closed (${r.statusDisplay}).',
                        style: const TextStyle(fontSize: 13, color: AppTheme.muted),
                      ),
                    )
                  else ...[
                    TextField(
                      controller: _remarks,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Remarks (optional)',
                        alignLabelWithHint: true,
                        hintText: 'Shown to the student with your decision',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : () => _decide(false),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.danger,
                              side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.4)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : () => _decide(true),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text(
                              _busy
                                  ? 'Saving…'
                                  : widget.isHod
                                      ? 'Approve OD'
                                      : 'Approve & forward',
                            ),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
