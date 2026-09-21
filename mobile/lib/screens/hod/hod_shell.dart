import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../notifications_sheet.dart';
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
  int _tab = 0;

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
    final titles = ['Dashboard', 'Requests', 'Students', 'Reports', 'Audit', 'Profile'];
    final actionable = _od.awaitingHod.length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/app_icon.png', height: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titles[_tab],
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                  const Text(
                    'Head of Department · IT',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _od.unreadCount > 0,
              label: Text('${_od.unreadCount}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const NotificationsSheet(),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          HodDashboardTab(onOpenRequests: () => setState(() => _tab = 1)),
          const HodRequestsTab(),
          const StudentsTab(),
          const ReportsTab(scope: ReportScope.hod),
          const HodAuditTab(),
          StaffProfileTab(user: user, onSignOut: widget.onSignOut),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: actionable > 0,
              label: Text('$actionable'),
              child: const Icon(Icons.approval_outlined),
            ),
            selectedIcon: const Icon(Icons.approval_rounded),
            label: 'Requests',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Students',
          ),
          const NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Reports',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_edu_outlined),
            selectedIcon: Icon(Icons.history_edu_rounded),
            label: 'Audit',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
