import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/od_service.dart';
import '../../widgets/role_shell.dart';
import '../reports/reports_tab.dart';
import 'student_od_tab.dart';
import 'student_history_tab.dart';
import 'student_profile_tab.dart';

/// The student application: OD, Previous ODs, Reports, Profile.
class StudentShell extends StatefulWidget {
  const StudentShell({super.key, required this.user, required this.onSignOut});

  final AppUser user;
  final Future<void> Function() onSignOut;

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  final _od = ODService();

  @override
  void initState() {
    super.initState();
    _od.addListener(_onUpdate);
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

    return RoleShell(
      subtitle: user.classDisplay.isEmpty ? 'SMVEC-IT' : user.classDisplay,
      tabs: (goTo) => [
        ShellTab(
          title: 'On Duty',
          label: 'OD',
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment_rounded,
          body: StudentOdTab(user: user),
        ),
        const ShellTab(
          title: 'Previous ODs',
          label: 'Previous',
          icon: Icons.history_outlined,
          selectedIcon: Icons.history_rounded,
          body: StudentHistoryTab(),
        ),
        // The student's own record of what they entered and what came of it,
        // exportable the same way the advisor's and the HOD's are.
        const ShellTab(
          title: 'Reports',
          label: 'Reports',
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart_rounded,
          body: ReportsTab(scope: ReportScope.student),
        ),
        ShellTab(
          title: 'Profile',
          label: 'Profile',
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          body: StudentProfileTab(user: user, onSignOut: widget.onSignOut),
        ),
      ],
    );
  }
}
