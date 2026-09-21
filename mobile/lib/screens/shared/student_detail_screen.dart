import 'package:flutter/material.dart';

import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'request_tile.dart';

/// One student's full record: who they are and every OD they have raised.
class StudentDetailScreen extends StatelessWidget {
  const StudentDetailScreen({super.key, required this.student});

  final StudentSummary student;

  @override
  Widget build(BuildContext context) {
    final od = ODService();
    final requests = od.requestsFor(student.registerNumber);
    final won = requests.where((r) => r.won).toList();

    return Scaffold(
      appBar: AppBar(title: Text(student.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, Color(0xFF1E3A8A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.accent,
                  child: Text(
                    student.name.isEmpty ? '?' : student.name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        student.registerNumber,
                        style: const TextStyle(fontSize: 13, color: Color(0xFFDBEAFE)),
                      ),
                      Text(
                        student.classDisplay,
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFFDBEAFE)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Total ODs',
                  value: '${requests.length}',
                  icon: Icons.folder_outlined,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Approved',
                  value: '${requests.where((r) => r.isApproved).length}',
                  icon: Icons.verified_rounded,
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Won',
                  value: '${won.length}',
                  icon: Icons.emoji_events_outlined,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          const SectionHeader(title: 'Details'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
              child: Column(
                children: [
                  DetailRow(
                    label: 'Email',
                    value: student.email,
                    icon: Icons.alternate_email_rounded,
                  ),
                  const Divider(height: 16),
                  DetailRow(
                    label: 'Class advisor',
                    value: student.advisorName,
                    icon: Icons.assignment_ind_outlined,
                  ),
                ],
              ),
            ),
          ),

          if (won.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionHeader(title: 'Achievements'),
            for (final r in won)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events_rounded,
                          color: Color(0xFFB45309), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.resultPrize ?? 'Won',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${r.resultProjectName ?? r.eventName} · ${r.eventName}',
                              style: const TextStyle(
                                  fontSize: 12.5, color: AppTheme.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],

          const SizedBox(height: 18),
          SectionHeader(
            title: 'OD history',
            trailing: Text(
              '${requests.length}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ),
          if (requests.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              title: 'No OD requests',
            )
          else
            for (final r in requests)
              RequestTile(
                request: r,
                showStudent: false,
                onTap: () {},
              ),
        ],
      ),
    );
  }
}
