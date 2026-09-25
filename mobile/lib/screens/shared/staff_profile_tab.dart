import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../models/user.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../hod/manage_advisors_screen.dart';
import '../../widgets/common.dart';

/// Profile for an advisor or the HOD.
///
/// Staff details come from the department roster and are not editable in the
/// app - changing who advises which class is a department decision, not a
/// self-service one.
class StaffProfileTab extends StatelessWidget {
  const StaffProfileTab({
    super.key,
    required this.user,
    required this.onSignOut,
  });

  final AppUser user;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final od = ODService();
    final all = od.allRequests;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
                radius: 30,
                backgroundColor: AppTheme.accent,
                child: Text(
                  user.initials,
                  style: const TextStyle(
                    fontSize: 21,
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
                      user.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.roleDisplay,
                      style: const TextStyle(fontSize: 13, color: Color(0xFFDBEAFE)),
                    ),
                    Text(
                      user.department,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFFDBEAFE)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Requests seen',
                value: '${all.length}',
                icon: Icons.folder_outlined,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Students',
                value: '${od.students.length}',
                icon: Icons.people_outline_rounded,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        const SectionHeader(title: 'Account'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
            child: Column(
              children: [
                DetailRow(
                  label: 'Email',
                  value: user.email,
                  icon: Icons.alternate_email_rounded,
                ),
                const Divider(height: 16),
                DetailRow(
                  label: 'Role',
                  value: user.roleDisplay,
                  icon: Icons.badge_outlined,
                ),
                const Divider(height: 16),
                DetailRow(
                  label: 'Department',
                  value: user.department,
                  icon: Icons.apartment_outlined,
                ),
              ],
            ),
          ),
        ),

        if (user.classes.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader(title: 'Classes you advise'),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < user.classes.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.school_outlined, size: 20),
                    title: Text(
                      user.classes[i].display,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: user.classes[i].batch == null
                        ? null
                        : Text('Batch ${user.classes[i].batch}',
                            style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Managing the department's advisors is the HOD's job, and nobody
        // else's - the server refuses these actions for anyone but them, so
        // showing the door to an advisor would only be a dead end.
        if (user.role == UserRole.hod) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.manage_accounts_outlined,
                  size: 20, color: AppTheme.primary),
              title: const Text(
                'Change class advisor',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Add, update or remove a class advisor',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManageAdvisorsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        Card(
          child: ListTile(
            leading: const Icon(Icons.logout_rounded, size: 20, color: AppTheme.danger),
            title: const Text(
              'Sign out',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.danger,
              ),
            ),
            onTap: () async {
              final ok = await confirm(
                context,
                title: 'Sign out?',
                message: 'You will need to sign in again.',
                confirmLabel: 'Sign out',
                destructive: true,
              );
              if (ok) await onSignOut();
            },
          ),
        ),
        const SizedBox(height: 20),

        Center(
          child: Column(
            children: [
              Image.asset('assets/app_icon.png', height: 40),
              const SizedBox(height: 8),
              Text(
                '${AppConfig.appName} · ${AppConfig.department}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
