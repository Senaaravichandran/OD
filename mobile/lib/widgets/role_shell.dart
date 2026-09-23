import 'package:flutter/material.dart';

import '../screens/notifications_sheet.dart';
import '../services/od_service.dart';
import '../theme.dart';

/// One tab of a role's application: its title, its place in the bar, and what
/// it shows.
///
/// These used to be three parallel lists - titles, destinations, bodies - kept
/// in step by hand. They drifted: a fourth tab was added to the student app
/// without a fourth title, so opening Profile read past the end of the titles
/// list and the whole screen went blank. Keeping the three together means the
/// mistake cannot be made again.
class ShellTab {
  const ShellTab({
    required this.title,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.body,
    this.badgeCount = 0,
  });

  /// Shown in the app bar while this tab is open.
  final String title;

  /// Shown under the icon in the navigation bar, and the name other tabs use
  /// to jump here.
  final String label;

  final IconData icon;
  final IconData selectedIcon;
  final Widget body;

  /// A count to show on the tab, such as requests awaiting review. Zero hides
  /// the badge.
  final int badgeCount;
}

/// Lets one tab open another, by name rather than by position - a dashboard
/// asks for 'Requests', not for tab 1, so reordering the bar cannot send it
/// somewhere else.
typedef ShellNavigate = void Function(String label);

/// The frame every role's application sits in: a branded app bar with the
/// notification bell, the tab bodies, and the navigation bar.
///
/// Bodies live in an IndexedStack so switching tabs keeps each one's scroll
/// position and any half-filled form.
class RoleShell extends StatefulWidget {
  const RoleShell({
    super.key,
    required this.tabs,
    required this.subtitle,
  });

  /// Built with a callback the tabs can use to open one another.
  final List<ShellTab> Function(ShellNavigate goTo) tabs;

  /// The line under the title - a student's class, an advisor's classes, or
  /// the department.
  final String subtitle;

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  final _od = ODService();
  int _tab = 0;

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

  static Widget _badged(ShellTab tab, IconData icon) => tab.badgeCount > 0
      ? Badge(label: Text('${tab.badgeCount}'), child: Icon(icon))
      : Icon(icon);

  void _openNotifications() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    late final List<ShellTab> tabs;

    void goTo(String label) {
      final i = tabs.indexWhere((t) => t.label == label);
      // A name that is not in the bar is a programming mistake, not something
      // to crash a running app over; staying put is the safe answer.
      if (i >= 0 && mounted) setState(() => _tab = i);
    }

    tabs = widget.tabs(goTo);

    // A role with no tabs would be a programming mistake, but it should not
    // take the screen down with it.
    if (tabs.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('This role has nothing to show.')),
      );
    }

    // Clamped rather than indexed blindly: if a role ever loses a tab while it
    // is open, fall back to the last one instead of going blank.
    final index = _tab.clamp(0, tabs.length - 1);
    final current = tabs[index];

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
                  Text(
                    current.title,
                    style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    widget.subtitle,
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
            onPressed: _openNotifications,
            tooltip: 'Notifications',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: index,
        children: [for (final t in tabs) t.body],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: _badged(t, t.icon),
              // Badged on both, so the count does not disappear the moment
              // you open the tab it belongs to - an advisor working through
              // the queue still wants to see how many are left.
              selectedIcon: _badged(t, t.selectedIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
