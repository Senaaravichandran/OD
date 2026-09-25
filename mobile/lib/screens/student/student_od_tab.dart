import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../models/user.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'attachments_sheet.dart';
import 'new_od_sheet.dart';
import 'od_card.dart';
import 'result_sheet.dart';
import 'student_profile_tab.dart';

/// Tab 1: the ODs that are still moving through the approval chain.
class StudentOdTab extends StatefulWidget {
  const StudentOdTab({super.key, required this.user});

  final AppUser user;

  @override
  State<StudentOdTab> createState() => _StudentOdTabState();
}

class _StudentOdTabState extends State<StudentOdTab> {
  final _od = ODService();

  @override
  void initState() {
    super.initState();
    _od.addListener(_onUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _od.refresh());
  }

  @override
  void dispose() {
    _od.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _newOd() async {
    final user = _od.user ?? widget.user;
    if (user.needsClassUpdate ||
        user.advisorName == null ||
        user.advisorName!.isEmpty) {
      // The server would refuse this anyway; saying why, and offering the fix,
      // beats a rejection they cannot act on.
      showToast(
        context,
        'Choose your class first - your advisor has changed.',
        error: true,
      );
      return;
    }
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NewOdSheet(user: user),
    );
    if (created == true && mounted) {
      showToast(context, 'OD submitted to ${user.advisorName}.');
    }
  }

  Future<void> _openAttachments(ODRequest request) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AttachmentsSheet(request: request),
    );
  }

  Future<void> _submitResult(ODRequest request) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ResultSheet(request: request),
    );
    if (done == true && mounted) showToast(context, 'Result recorded.');
  }

  @override
  Widget build(BuildContext context) {
    final active = _od.activeRequests;
    final awaitingResult = _od.allRequests
        .where((r) => r.canSubmitResult && !r.hasResult)
        .toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _od.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (_od.lastError != null)
              ErrorBanner(message: _od.lastError!, onRetry: _od.refresh),

            _SummaryRow(od: _od),
            const SizedBox(height: 20),

            // Their class advisor was removed by the department. Everything
            // they have filed still stands, but a new OD has nowhere to go
            // until they say which class they are in now.
            if ((_od.user ?? widget.user).needsClassUpdate) ...[
              const _ClassAdvisorGoneBanner(),
              const SizedBox(height: 16),
            ],

            if (awaitingResult.isNotEmpty) ...[
              const SectionHeader(title: 'Waiting for your result'),
              for (final r in awaitingResult)
                OdCard(
                  request: r,
                  showProgress: false,
                  onSubmitResult: () => _submitResult(r),
                  onAttachments: () => _openAttachments(r),
                ),
              const SizedBox(height: 12),
            ],

            SectionHeader(
              title: 'Active requests',
              trailing: Text(
                '${active.length}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            ),

            if (_od.isLoading && _od.allRequests.isEmpty)
              const SkeletonList()
            else if (active.isEmpty)
              EmptyState(
                icon: Icons.assignment_outlined,
                title: 'No active OD requests',
                message:
                    'Raise one when you have an event to attend. It goes to '
                    '${(_od.user ?? widget.user).advisorName ?? 'your class advisor'} first.',
                action: FilledButton.icon(
                  onPressed: _newOd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New OD request'),
                ),
              )
            else
              for (final r in active)
                OdCard(
                  request: r,
                  onSubmitResult: r.isApproved ? () => _submitResult(r) : null,
                  onAttachments: r.isApproved ? () => _openAttachments(r) : null,
                ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newOd,
        // Left tappable on purpose: a disabled button explains nothing, and
        // tapping this one says what to do about it.
        backgroundColor: (_od.user ?? widget.user).needsClassUpdate
            ? AppTheme.muted
            : null,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New OD'),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.od});

  final ODService od;

  @override
  Widget build(BuildContext context) {
    final all = od.allRequests;
    final pending = all.where((r) => !r.isClosed).length;
    final approved = all.where((r) => r.isApproved).length;
    final won = all.where((r) => r.won).length;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Total ODs',
            value: '${all.length}',
            icon: Icons.folder_outlined,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'In review',
            value: '$pending',
            icon: Icons.hourglass_top_rounded,
            color: AppTheme.warning,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Approved',
            value: '$approved',
            icon: Icons.verified_rounded,
            color: AppTheme.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Won',
            value: '$won',
            icon: Icons.emoji_events_outlined,
            color: AppTheme.accent,
          ),
        ),
      ],
    );
  }
}


/// Shown when the department has removed the student's class advisor.
///
/// It says what happened, what it means for them, and what to do - in that
/// order, because "your advisor was removed" on its own only worries people.
class _ClassAdvisorGoneBanner extends StatelessWidget {
  const _ClassAdvisorGoneBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.tint(AppTheme.warning),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, size: 19, color: AppTheme.warning),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Choose your class again',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Your class advisor has changed. The ODs you have already sent are '
            'unaffected, but a new one needs an advisor to go to.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: AppTheme.ink),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => chooseClass(context),
              icon: const Icon(Icons.school_outlined, size: 17),
              label: const Text('Choose my class'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
            ),
          ),
        ],
      ),
    );
  }
}
