import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// The department's action log, visible to the HOD only.
///
/// It is written by the server on every state change and is not editable from
/// the app by anyone.
class HodAuditTab extends StatefulWidget {
  const HodAuditTab({super.key});

  @override
  State<HodAuditTab> createState() => _HodAuditTabState();
}

class _HodAuditTabState extends State<HodAuditTab> {
  final _od = ODService();
  final _search = TextEditingController();
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

  static (IconData, Color) _look(String action) {
    if (action.contains('APPROVED')) {
      return (Icons.check_circle_outline_rounded, AppTheme.success);
    }
    if (action.contains('REJECTED')) {
      return (Icons.cancel_outlined, AppTheme.danger);
    }
    if (action.contains('CREATED')) {
      return (Icons.add_circle_outline_rounded, AppTheme.primary);
    }
    if (action.contains('RESULT')) {
      return (Icons.emoji_events_outlined, AppTheme.accent);
    }
    if (action.contains('LOGIN')) {
      return (Icons.login_rounded, AppTheme.muted);
    }
    return (Icons.info_outline_rounded, AppTheme.muted);
  }

  @override
  Widget build(BuildContext context) {
    var logs = _od.allAuditLogs;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      logs = logs
          .where((l) =>
              l.action.toLowerCase().contains(q) ||
              l.actor.toLowerCase().contains(q) ||
              l.details.toLowerCase().contains(q))
          .toList();
    }

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
                hintText: 'Search action or person',
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
          Expanded(
            child: logs.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      EmptyState(
                        icon: Icons.history_edu_outlined,
                        title: 'No activity yet',
                        message: 'Every approval, rejection and result is recorded here.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: logs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _AuditTile(entry: logs[i], look: _look),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry, required this.look});

  final AuditEntry entry;
  final (IconData, Color) Function(String) look;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = look(entry.action);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTheme.tint(color),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.actionLabel,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.ink,
                          ),
                        ),
                      ),
                      Text(
                        fmtRelative(entry.timestamp),
                        style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.actor,
                    style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                  if (entry.details.isNotEmpty && entry.details != '{}') ...[
                    const SizedBox(height: 5),
                    Text(
                      entry.details,
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
