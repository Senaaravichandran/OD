import 'package:flutter/material.dart';

import '../../models/od_request.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'od_progress.dart';

/// One OD request, shown to the student who raised it.
class OdCard extends StatelessWidget {
  const OdCard({
    super.key,
    required this.request,
    this.onSubmitResult,
    this.showProgress = true,
  });

  final ODRequest request;
  final VoidCallback? onSubmitResult;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final r = request;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.eventName,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${r.eventType} · ${fmtDate(r.eventDate)}'
                        '${r.eventDay.isEmpty ? '' : ' · ${r.eventDay}'}',
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                StatusBadge(
                  label: r.statusDisplay,
                  color: r.statusColor,
                  icon: r.statusIcon,
                  compact: true,
                ),
              ],
            ),

            if (r.referenceNo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                r.referenceNo,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.muted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],

            if (r.isTeam && r.teamMembers.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  const Icon(Icons.groups_outlined, size: 15, color: AppTheme.muted),
                  for (final m in r.teamMembers)
                    Text(
                      m,
                      style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                    ),
                ],
              ),
            ],

            if (showProgress) ...[
              const SizedBox(height: 16),
              OdProgress(request: r),
            ],

            if (r.advisorRemarks != null && r.advisorRemarks!.isNotEmpty)
              _Remark(
                who: r.advisorName,
                role: 'Class Advisor',
                text: r.advisorRemarks!,
                rejected: r.isRejectedByAdvisor,
              ),
            if (r.hodRemarks != null && r.hodRemarks!.isNotEmpty)
              _Remark(
                who: 'HOD',
                role: 'Head of Department',
                text: r.hodRemarks!,
                rejected: r.isRejectedByHod,
              ),

            if (r.hasResult) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppTheme.tint(r.won ? AppTheme.accent : AppTheme.primary),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      r.won ? Icons.emoji_events_rounded : Icons.workspace_premium_outlined,
                      size: 18,
                      color: r.won ? const Color(0xFFB45309) : AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.resultDisplay,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          if (r.resultProjectName != null &&
                              r.resultProjectName!.isNotEmpty)
                            Text(
                              r.resultProjectName!,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.muted),
                            ),
                        ],
                      ),
                    ),
                    if (r.files.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.attach_file_rounded,
                              size: 14, color: AppTheme.muted),
                          Text(
                            '${r.files.length}',
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.muted),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],

            // Only offered once the HOD has sanctioned it - the server refuses
            // a result before that, so showing it earlier would be a lie.
            if (r.canSubmitResult && !r.hasResult && onSubmitResult != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onSubmitResult,
                  icon: const Icon(Icons.emoji_events_outlined, size: 18),
                  label: const Text('Submit result'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Remark extends StatelessWidget {
  const _Remark({
    required this.who,
    required this.role,
    required this.text,
    required this.rejected,
  });

  final String who;
  final String role;
  final String text;
  final bool rejected;

  @override
  Widget build(BuildContext context) {
    final color = rejected ? AppTheme.danger : AppTheme.muted;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: rejected ? AppTheme.tint(AppTheme.danger) : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: rejected
                ? AppTheme.danger.withValues(alpha: 0.25)
                : AppTheme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$who · $role',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.ink, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
