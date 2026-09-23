import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/od_service.dart';
import '../../widgets/role_shell.dart';
import '../reports/reports_tab.dart';
import '../shared/staff_profile_tab.dart';
import '../shared/students_tab.dart';
import 'advisor_dashboard_tab.dart';
import 'advisor_requests_tab.dart';

/// The class advisor application.
///
/// Everything here is already scoped by the server to the classes this advisor
/// holds - the app does not filter, it only displays what it was given.
class AdvisorShell extends StatefulWidget {
  const AdvisorShell({super.key, required this.user, required this.onSignOut});

  final AppUser user;
  final Future<void> Function() onSignOut;

  @override
  State<AdvisorShell> createState() => _AdvisorShellState();
}

class _AdvisorShellState extends State<AdvisorShell> {
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
    final pending = _od.awaitingMyReview.length;

    return RoleShell(
      subtitle: user.classes.isEmpty
          ? 'Class Advisor'
          : user.classes.map((c) => '${c.year}-${c.section}').join(', '),
      tabs: (goTo) => [
        ShellTab(
          title: 'Dashboard',
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
          body: AdvisorDashboardTab(
            user: user,
            onOpenRequests: () => goTo('Requests'),
          ),
        ),
        ShellTab(
          title: 'Requests',
          label: 'Requests',
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment_rounded,
          badgeCount: pending,
          body: const AdvisorRequestsTab(),
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
          body: ReportsTab(scope: ReportScope.advisor),
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
