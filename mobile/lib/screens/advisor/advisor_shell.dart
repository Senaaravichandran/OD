import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../notifications_sheet.dart';
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
    final titles = ['Dashboard', 'Requests', 'Students', 'Reports', 'Profile'];
    final pending = _od.awaitingMyReview.length;

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
                  Text(
                    user.classes.isEmpty
                        ? 'Class Advisor'
                        : user.classes.map((c) => '${c.year}-${c.section}').join(', '),
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
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
          AdvisorDashboardTab(user: user, onOpenRequests: () => setState(() => _tab = 1)),
          const AdvisorRequestsTab(),
          const StudentsTab(),
          const ReportsTab(scope: ReportScope.advisor),
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
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.assignment_outlined),
            ),
            selectedIcon: const Icon(Icons.assignment_rounded),
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
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
