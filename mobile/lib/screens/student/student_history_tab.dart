import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'od_card.dart';

/// Tab 2: everything this student has ever raised, with filters.
class StudentHistoryTab extends StatefulWidget {
  const StudentHistoryTab({super.key});

  @override
  State<StudentHistoryTab> createState() => _StudentHistoryTabState();
}

class _StudentHistoryTabState extends State<StudentHistoryTab> {
  final _od = ODService();
  final _search = TextEditingController();

  String _filter = 'ALL';
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
    var list = _od.allRequests;

    list = switch (_filter) {
      'APPROVED' => list.where((r) => r.isApproved).toList(),
      'REJECTED' => list.where((r) => r.isRejected).toList(),
      'PENDING' => list.where((r) => !r.isClosed).toList(),
      'WON' => list.where((r) => r.won).toList(),
      _ => list,
    };

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((r) {
        return r.eventName.toLowerCase().contains(q) ||
            r.eventType.toLowerCase().contains(q) ||
            (r.resultProjectName ?? '').toLowerCase().contains(q) ||
            (r.resultPrize ?? '').toLowerCase().contains(q) ||
            r.referenceNo.toLowerCase().contains(q);
      }).toList();
    }
    return list;
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
                hintText: 'Search event, project or prize',
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
                _chip('All', 'ALL', all.length),
                _chip('In review', 'PENDING', all.where((r) => !r.isClosed).length),
                _chip('Approved', 'APPROVED', all.where((r) => r.isApproved).length),
                _chip('Won', 'WON', all.where((r) => r.won).length),
                _chip('Rejected', 'REJECTED', all.where((r) => r.isRejected).length),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      EmptyState(
                        icon: _query.isNotEmpty
                            ? Icons.search_off_rounded
                            : Icons.history_rounded,
                        title: _query.isNotEmpty
                            ? 'Nothing matches "$_query"'
                            : 'No previous ODs',
                        message: _query.isNotEmpty
                            ? 'Try a different search or clear the filter.'
                            : 'Requests you raise will be listed here.',
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) =>
                        OdCard(request: list[i], showProgress: false),
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
