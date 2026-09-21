import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../advisor/review_sheet.dart';
import '../shared/request_tile.dart';

/// Every request in the department.
///
/// Anything still with a class advisor is shown but not actionable, and says
/// so - the HOD cannot sanction before the advisor has recommended, and the
/// server refuses it regardless of what the app displays.
class HodRequestsTab extends StatefulWidget {
  const HodRequestsTab({super.key});

  @override
  State<HodRequestsTab> createState() => _HodRequestsTabState();
}

class _HodRequestsTabState extends State<HodRequestsTab> {
  final _od = ODService();
  final _search = TextEditingController();
  String _filter = 'ACTIONABLE';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _od.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _od.removeListener(_onUpdate);
    _search.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  List<ODRequest> get _filtered {
    var list = switch (_filter) {
      'ACTIONABLE' => _od.allRequests.where((r) => r.isPendingHod).toList(),
      'WITH_ADVISOR' => _od.allRequests.where((r) => r.isPendingAdvisor).toList(),
      'APPROVED' => _od.allRequests.where((r) => r.isApproved).toList(),
      'REJECTED' => _od.allRequests.where((r) => r.isRejected).toList(),
      _ => _od.allRequests,
    };

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((r) =>
              r.studentName.toLowerCase().contains(q) ||
              r.registerNumber.toLowerCase().contains(q) ||
              r.eventName.toLowerCase().contains(q) ||
              r.advisorName.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  Future<void> _open(ODRequest r) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReviewSheet(request: r, isHod: true),
    );
    if (result != null && mounted) {
      showToast(
        context,
        result == 'approved' ? 'OD sanctioned.' : 'Request rejected.',
        error: result != 'approved',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _od.allRequests;
    final list = _filtered;

    return RefreshIndicator(
      onRefresh: _od.refresh,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search student, event or advisor',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip('Awaiting me', 'ACTIONABLE',
                    all.where((r) => r.isPendingHod).length),
                _chip('With advisor', 'WITH_ADVISOR',
                    all.where((r) => r.isPendingAdvisor).length),
                _chip('Approved', 'APPROVED', all.where((r) => r.isApproved).length),
                _chip('Rejected', 'REJECTED', all.where((r) => r.isRejected).length),
                _chip('All', 'ALL', all.length),
              ],
            ),
          ),
          Expanded(
            child: _od.isLoading && all.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList())
                : list.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          EmptyState(
                            icon: Icons.inbox_rounded,
                            title: 'Nothing here',
                            message: 'Try a different filter.',
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final r = list[i];
                          return Column(
                            children: [
                              RequestTile(
                                request: r,
                                onTap: () => _open(r),
                                actionLabel: r.isPendingHod ? 'Review & sanction' : null,
                              ),
                              if (r.isPendingAdvisor)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.tint(AppTheme.warning),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.hourglass_top_rounded,
                                            size: 14, color: AppTheme.warning),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Waiting for Class Advisor approval '
                                            '(${r.advisorName})',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: AppTheme.warning,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, int count) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text('$label ($count)'),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = value),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: selected ? AppTheme.primary : AppTheme.muted,
        ),
      ),
    );
  }
}
