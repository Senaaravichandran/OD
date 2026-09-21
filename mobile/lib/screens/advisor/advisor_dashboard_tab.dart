import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shared/request_tile.dart';
import 'review_sheet.dart';

/// What the advisor needs to see first: how much is waiting, and what to do.
class AdvisorDashboardTab extends StatefulWidget {
  const AdvisorDashboardTab({
    super.key,
    required this.user,
    required this.onOpenRequests,
  });

  final AppUser user;
  final VoidCallback onOpenRequests;

  @override
  State<AdvisorDashboardTab> createState() => _AdvisorDashboardTabState();
}

class _AdvisorDashboardTabState extends State<AdvisorDashboardTab> {
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
    final pending = all.where((r) => r.isPendingAdvisor).toList();
    final user = _od.user ?? widget.user;

    return RefreshIndicator(
      onRefresh: _od.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_od.lastError != null)
            ErrorBanner(message: _od.lastError!, onRetry: _od.refresh),

          _Greeting(user: user),
          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Students',
                  value: '${_od.students.length}',
                  icon: Icons.people_outline_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Pending review',
                  value: '${pending.length}',
                  icon: Icons.hourglass_top_rounded,
                  color: AppTheme.warning,
                  onTap: widget.onOpenRequests,
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
          const SizedBox(height: 22),

          SectionHeader(
            title: 'Waiting for you',
            trailing: pending.isEmpty
                ? null
                : TextButton(
                    onPressed: widget.onOpenRequests,
                    child: const Text('See all'),
                  ),
          ),

          if (_od.isLoading && all.isEmpty)
            const SkeletonList(count: 2)
          else if (pending.isEmpty)
            const EmptyState(
              icon: Icons.task_alt_rounded,
              title: 'Nothing waiting',
              message: 'Every request from your class has been reviewed.',
            )
          else
            for (final r in pending.take(5))
              RequestTile(
                request: r,
                actionLabel: 'Review',
                onTap: () async {
                  final result = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => ReviewSheet(request: r, isHod: false),
                  );
                  if (result != null && context.mounted) {
                    showToast(
                      context,
                      result == 'approved'
                          ? 'Approved and forwarded to the HOD.'
                          : 'Request rejected.',
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

class _Greeting extends StatelessWidget {
  const _Greeting({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(part, style: const TextStyle(fontSize: 12.5, color: Color(0xFFDBEAFE))),
          const SizedBox(height: 2),
          Text(
            user.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in user.classes)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    c.display,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
