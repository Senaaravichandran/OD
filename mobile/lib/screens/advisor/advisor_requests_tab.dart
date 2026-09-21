import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shared/request_tile.dart';
import 'review_sheet.dart';

/// Every request assigned to this advisor's classes, with filters.
class AdvisorRequestsTab extends StatefulWidget {
  const AdvisorRequestsTab({super.key});

  @override
  State<AdvisorRequestsTab> createState() => _AdvisorRequestsTabState();
}

class _AdvisorRequestsTabState extends State<AdvisorRequestsTab> {
  final _od = ODService();
  final _search = TextEditingController();
  String _filter = 'PENDING';
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
      'PENDING' => _od.allRequests.where((r) => r.isPendingAdvisor).toList(),
      'FORWARDED' => _od.allRequests.where((r) => r.isPendingHod).toList(),
      'APPROVED' => _od.allRequests.where((r) => r.isApproved).toList(),
      'REJECTED' => _od.allRequests.where((r) => r.isRejected).toList(),
      _ => _od.allRequests,
    };

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((r) =>
          r.studentName.toLowerCase().contains(q) ||
          r.registerNumber.toLowerCase().contains(q) ||
          r.eventName.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  Future<void> _review(ODRequest r) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReviewSheet(request: r, isHod: false),
    );
    if (result != null && mounted) {
      showToast(
        context,
        result == 'approved'
            ? 'Approved and forwarded to the HOD.'
            : 'Request rejected.',
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
                hintText: 'Search student, register no. or event',
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
                _chip('Pending my review', 'PENDING',
                    all.where((r) => r.isPendingAdvisor).length),
                _chip('With HOD', 'FORWARDED', all.where((r) => r.isPendingHod).length),
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
                        children: [
                          EmptyState(
                            icon: _filter == 'PENDING'
                                ? Icons.inbox_rounded
                                : Icons.filter_list_off_rounded,
                            title: _filter == 'PENDING'
                                ? 'Nothing to review'
                                : 'No requests here',
                            message: _filter == 'PENDING'
                                ? 'New OD requests from your class will appear here.'
                                : 'Try a different filter.',
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: list.length,
                        itemBuilder: (_, i) => RequestTile(
                          request: list[i],
                          onTap: () => _review(list[i]),
                          actionLabel:
                              list[i].isPendingAdvisor ? 'Review' : null,
                        ),
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
