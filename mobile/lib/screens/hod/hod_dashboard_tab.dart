import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shared/request_tile.dart';
import '../advisor/review_sheet.dart';

/// Department-wide summary for the HOD.
class HodDashboardTab extends StatefulWidget {
  const HodDashboardTab({super.key, required this.onOpenRequests});

  final VoidCallback onOpenRequests;

  @override
  State<HodDashboardTab> createState() => _HodDashboardTabState();
}

class _HodDashboardTabState extends State<HodDashboardTab> {
  final _od = ODService();

  @override
  void initState() {
    super.initState();
    _od.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _od.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = _od.allRequests;
    final actionable = all.where((r) => r.isPendingHod).toList();
    final withAdvisor = all.where((r) => r.isPendingAdvisor).length;

    // Which event types are actually being used, busiest first.
    final byType = <String, int>{};
    for (final r in all) {
      byType[r.eventType] = (byType[r.eventType] ?? 0) + 1;
    }
    final types = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: _od.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_od.lastError != null)
            ErrorBanner(message: _od.lastError!, onRetry: _od.refresh),

          Row(
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
                  label: 'Students',
                  value: '${_od.students.length}',
                  icon: Icons.people_outline_rounded,
                  color: const Color(0xFF7C3AED),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Awaiting you',
                  value: '${actionable.length}',
                  icon: Icons.approval_rounded,
                  color: AppTheme.primary,
                  onTap: widget.onOpenRequests,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'With advisors',
                  value: '$withAdvisor',
                  icon: Icons.hourglass_top_rounded,
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Approved',
                  value: '${all.where((r) => r.isApproved).length}',
                  icon: Icons.verified_rounded,
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Rejected',
                  value: '${all.where((r) => r.isRejected).length}',
                  icon: Icons.cancel_outlined,
                  color: AppTheme.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Participated',
                  value: '${all.where((r) => r.resultStatus == 'PARTICIPATED').length}',
                  icon: Icons.workspace_premium_outlined,
                  color: const Color(0xFF0891B2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Won',
                  value: '${all.where((r) => r.won).length}',
                  icon: Icons.emoji_events_outlined,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          if (types.isNotEmpty) ...[
            const SectionHeader(title: 'Events'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  children: [
                    for (final t in types) _TypeBar(
                      label: t.key,
                      count: t.value,
                      total: all.length,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
          ],

          SectionHeader(
            title: 'Ready for your sanction',
            trailing: actionable.isEmpty
                ? null
                : TextButton(
                    onPressed: widget.onOpenRequests,
                    child: const Text('See all'),
                  ),
          ),

          if (_od.isLoading && all.isEmpty)
            const SkeletonList(count: 2)
          else if (actionable.isEmpty)
            EmptyState(
              icon: Icons.task_alt_rounded,
              title: 'Nothing awaiting sanction',
              message: withAdvisor > 0
                  ? '$withAdvisor request${withAdvisor == 1 ? ' is' : 's are'} '
                      'still with the class advisor.'
                  : 'Every recommended request has been decided.',
            )
          else
            for (final r in actionable.take(5))
              RequestTile(
                request: r,
                actionLabel: 'Review',
                onTap: () async {
                  final result = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => ReviewSheet(request: r, isHod: true),
                  );
                  if (result != null && context.mounted) {
                    showToast(
                      context,
                      result == 'approved' ? 'OD sanctioned.' : 'Request rejected.',
                      error: result != 'approved',
                    );
                  }
                },
              ),
        ],
      ),
    );
  }
}

/// A simple proportional bar, so the mix of event types reads at a glance
/// without pulling in a charting package.
class _TypeBar extends StatelessWidget {
  const _TypeBar({required this.label, required this.count, required this.total});

  final String label;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : count / total;
    final palette = [
      AppTheme.primary,
      AppTheme.accent,
      const Color(0xFF0891B2),
      const Color(0xFF7C3AED),
      AppTheme.success,
      AppTheme.warning,
      AppTheme.muted,
    ];
    final color = palette[AppConfig.eventTypes.indexOf(label).clamp(0, palette.length - 1)];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 13)),
              ),
              Text(
                '$count',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: AppTheme.surface,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
