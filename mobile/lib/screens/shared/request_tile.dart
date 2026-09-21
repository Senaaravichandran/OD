import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// One OD request as staff see it: who raised it, what for, and where it is.
class RequestTile extends StatelessWidget {
  const RequestTile({
    super.key,
    required this.request,
    required this.onTap,
    this.actionLabel,
    this.showStudent = true,
  });

  final ODRequest request;
  final VoidCallback onTap;
  final String? actionLabel;
  final bool showStudent;

  @override
  Widget build(BuildContext context) {
    final r = request;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showStudent) ...[
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.tint(AppTheme.primary),
                      child: Text(
                        _initials(r.studentName),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showStudent)
                          Text(
                            '${r.studentName} · ${r.registerNumber}',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(
                          r.eventName,
                          style: TextStyle(
                            fontSize: showStudent ? 13 : 14.5,
                            fontWeight: showStudent ? FontWeight.w500 : FontWeight.w800,
                            color: showStudent ? AppTheme.muted : AppTheme.ink,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusBadge(
                    label: r.statusDisplay,
                    color: r.statusColor,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _meta(Icons.category_outlined, r.eventType),
                  _meta(Icons.event_outlined, fmtDate(r.eventDate)),
                  if (showStudent)
                    _meta(Icons.school_outlined, 'Year ${r.year} · ${r.section}'),
                  if (r.isTeam)
                    _meta(Icons.groups_outlined, 'Team of ${r.teamMembers.length}'),
                  if (r.hasResult)
                    _meta(
                      r.won ? Icons.emoji_events_rounded : Icons.workspace_premium_outlined,
                      r.resultDisplay,
                    ),
                ],
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13.5, color: AppTheme.muted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11.5, color: AppTheme.muted)),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
