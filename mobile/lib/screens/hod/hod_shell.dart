import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/od_service.dart';
import '../../widgets/role_shell.dart';
import '../reports/reports_tab.dart';
import '../shared/staff_profile_tab.dart';
import '../shared/students_tab.dart';
import 'hod_audit_tab.dart';
import 'hod_dashboard_tab.dart';
import 'hod_requests_tab.dart';

/// The HOD application: department-wide visibility, plus the audit trail.
class HodShell extends StatefulWidget {
  const HodShell({super.key, required this.user, required this.onSignOut});

  final AppUser user;
  final Future<void> Function() onSignOut;

  @override
  State<HodShell> createState() => _HodShellState();
}

class _HodShellState extends State<HodShell> {
  final _od = ODService();

  @override
  void initState() {
    super.initState();
    _od.addListener(_onUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _od.refresh());
  }

  @override
  void dispose() {
    _od.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = _od.user ?? widget.user;
    final actionable = _od.awaitingHod.length;

    return RoleShell(
      subtitle: 'Head of Department · IT',
      tabs: (goTo) => [
        ShellTab(
          title: 'Dashboard',
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
          body: HodDashboardTab(onOpenRequests: () => goTo('Requests')),
        ),
        ShellTab(
          title: 'Requests',
          label: 'Requests',
          icon: Icons.approval_outlined,
          selectedIcon: Icons.approval_rounded,
          badgeCount: actionable,
          body: const HodRequestsTab(),
        ),
        const ShellTab(
          title: 'Students',
          label: 'Students',
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_rounded,
          body: StudentsTab(),
        ),
        const ShellTab(
          title: 'Reports',
          label: 'Reports',
          icon: Icons.analytics_outlined,
          selectedIcon: Icons.analytics_rounded,
          body: ReportsTab(scope: ReportScope.hod),
        ),
        const ShellTab(
          title: 'Audit',
          label: 'Audit',
          icon: Icons.history_edu_outlined,
          selectedIcon: Icons.history_edu_rounded,
          body: HodAuditTab(),
        ),
        ShellTab(
          title: 'Profile',
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          body: StaffProfileTab(user: user, onSignOut: widget.onSignOut),
        ),
      ],
    );
  }
}
