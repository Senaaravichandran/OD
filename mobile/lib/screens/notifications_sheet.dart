import 'package:flutter/material.dart';

import '../services/od_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The notification list, opened from the bell in every role's app bar.
class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key});

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  final _od = ODService();

  @override
  void initState() {
    super.initState();
    _od.addListener(_onUpdate);
    // Opening the list is what marks it read.
    WidgetsBinding.instance.addPostFrameCallback((_) => _od.markNotificationsRead());
  }

  @override
  void dispose() {
    _od.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  static (IconData, Color) _look(String title) {
    final t = title.toLowerCase();
    if (t.contains('sanction') || t.contains('approved')) {
      return (Icons.check_circle_outline_rounded, AppTheme.success);
    }
    if (t.contains('reject')) return (Icons.cancel_outlined, AppTheme.danger);
    if (t.contains('won')) return (Icons.emoji_events_outlined, AppTheme.accent);
    if (t.contains('new od') || t.contains('submitted')) {
      return (Icons.assignment_outlined, AppTheme.primary);
    }
    return (Icons.notifications_none_rounded, AppTheme.muted);
  }

  @override
  Widget build(BuildContext context) {
    final items = _od.allNotifications;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 10),
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Icon(Icons.notifications_none_rounded, size: 20),
                SizedBox(width: 10),
                Text(
                  'Notifications',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: items.isEmpty
                ? const EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: 'No notifications',
                    message: 'Approvals and rejections will show up here.',
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                    itemBuilder: (_, i) {
                      final n = items[i];
                      final (icon, color) = _look(n.title);
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.tint(color),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(icon, size: 17, color: color),
                        ),
                        title: Text(
                          n.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            n.message,
                            style: const TextStyle(fontSize: 12.5, height: 1.35),
                          ),
                        ),
                        trailing: Text(
                          fmtRelative(n.timestamp),
                          style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
