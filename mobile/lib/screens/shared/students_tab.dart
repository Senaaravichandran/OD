import 'package:flutter/material.dart';

import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'student_detail_screen.dart';

/// The students visible to the caller.
///
/// For an advisor that is their own class; for the HOD it is the department.
/// The scoping is the server's, not this screen's - it lists whoever appears
/// in the requests it was given.
class StudentsTab extends StatefulWidget {
  const StudentsTab({super.key});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  final _od = ODService();
  final _search = TextEditingController();
  String _query = '';
  int? _yearFilter;

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

  @override
  Widget build(BuildContext context) {
    var students = _od.students;

    if (_yearFilter != null) {
      students = students.where((s) => s.year == _yearFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      students = students
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              s.registerNumber.toLowerCase().contains(q) ||
              s.email.toLowerCase().contains(q))
          .toList();
    }

    final years = _od.students.map((s) => s.year).toSet().toList()..sort();

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
                hintText: 'Search name, register no. or email',
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
          if (years.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip('All years', null),
                  for (final y in years) _chip('Year $y', y),
                ],
              ),
            ),
          Expanded(
            child: students.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      EmptyState(
                        icon: _query.isNotEmpty
                            ? Icons.person_search_rounded
                            : Icons.people_outline_rounded,
                        title: _query.isNotEmpty
                            ? 'No student matches "$_query"'
                            : 'No students yet',
                        message: _query.isNotEmpty
                            ? 'Try a different name or register number.'
                            : 'Students appear here once they raise an OD.',
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: students.length,
                    itemBuilder: (_, i) {
                      final s = students[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.tint(AppTheme.primary),
                            child: Text(
                              s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            s.name,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(
                                '${s.registerNumber} · ${s.classDisplay}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 6,
                                children: [
                                  StatusBadge(
                                    label: '${s.total} OD',
                                    color: AppTheme.primary,
                                    compact: true,
                                  ),
                                  if (s.approved > 0)
                                    StatusBadge(
                                      label: '${s.approved} approved',
                                      color: AppTheme.success,
                                      compact: true,
                                    ),
                                  if (s.won > 0)
                                    StatusBadge(
                                      label: '${s.won} won',
                                      color: AppTheme.accent,
                                      compact: true,
                                    ),
                                ],
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StudentDetailScreen(student: s),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int? year) {
    final selected = _yearFilter == year;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _yearFilter = year),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: selected ? AppTheme.primary : AppTheme.muted,
        ),
      ),
    );
  }
}
