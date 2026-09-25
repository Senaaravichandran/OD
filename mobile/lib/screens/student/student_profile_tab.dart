import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../models/od_request.dart' show ClassSection, ClassYear;
import '../../models/user.dart';
import '../../services/api_client.dart';
import '../../services/od_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Tab 3: who the student is, and the one thing they may change.
///
/// Year, section and advisor are not free-text. They move together, validated
/// against the department's class list by the server, because the advisor is
/// derived from the class.
class StudentProfileTab extends StatefulWidget {
  const StudentProfileTab({
    super.key,
    required this.user,
    required this.onSignOut,
  });

  final AppUser user;
  final Future<void> Function() onSignOut;

  @override
  State<StudentProfileTab> createState() => _StudentProfileTabState();
}

class _StudentProfileTabState extends State<StudentProfileTab> {
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

  Future<void> _changeClass() => chooseClass(context);

  Future<void> _signOut() async {
    final ok = await confirm(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in with Google again.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (ok) await widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = _od.user ?? widget.user;
    final requests = _od.allRequests;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _ProfileHeader(user: user),
        const SizedBox(height: 18),

        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Total ODs',
                value: '${requests.length}',
                icon: Icons.folder_outlined,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Approved',
                value: '${requests.where((r) => r.isApproved).length}',
                icon: Icons.verified_rounded,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Won',
                value: '${requests.where((r) => r.won).length}',
                icon: Icons.emoji_events_outlined,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        const SectionHeader(title: 'Your details'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
            child: Column(
              children: [
                DetailRow(
                  label: 'Register number',
                  value: user.registerNumber ?? '-',
                  icon: Icons.badge_outlined,
                ),
                const Divider(height: 16),
                DetailRow(
                  label: 'Email',
                  value: user.email,
                  icon: Icons.alternate_email_rounded,
                ),
                const Divider(height: 16),
                DetailRow(
                  label: 'Department',
                  value: user.department,
                  icon: Icons.apartment_outlined,
                ),
                const Divider(height: 16),
                DetailRow(
                  label: 'Class',
                  value: user.classDisplay,
                  icon: Icons.school_outlined,
                ),
                const Divider(height: 16),
                DetailRow(
                  label: 'Class advisor',
                  value: user.advisorName ?? '-',
                  icon: Icons.assignment_ind_outlined,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined, size: 20),
                title: const Text('Correct my class',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'Your advisor follows from your class',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _changeClass,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout_rounded, size: 20, color: AppTheme.danger),
                title: const Text(
                  'Sign out',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.danger,
                  ),
                ),
                onTap: _signOut,
              ),
            ],
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            backgroundImage: (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                ? NetworkImage(user.photoUrl!)
                : null,
            child: (user.photoUrl == null || user.photoUrl!.isEmpty)
                ? Text(
                    user.initials,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  )
                : null,
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
                  user.registerNumber ?? '',
                  style: const TextStyle(fontSize: 13, color: Color(0xFFDBEAFE)),
                ),
                Text(
                  user.classDisplay,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFDBEAFE)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pick a class from the department's list. Only classes that exist appear.
class ClassPicker extends StatelessWidget {
  const ClassPicker({
    super.key,
    required this.classes,
    required this.currentYear,
    required this.currentSection,
  });

  final List<ClassYear> classes;
  final int? currentYear;
  final String? currentSection;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
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
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Choose your class',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Your class advisor follows from your class.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.muted),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final y in classes)
                  for (final s in y.sections)
                    _row(context, y.year, s),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int year, ClassSection s) {
    final isCurrent = year == currentYear && s.section == currentSection;
    return ListTile(
      title: Text(
        'Year $year · Section ${s.section}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(s.advisorName, style: const TextStyle(fontSize: 12.5)),
      trailing: isCurrent
          ? const Icon(Icons.check_circle_rounded, color: AppTheme.success)
          : const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.pop(context, (year: year, section: s.section)),
    );
  }
}


/// Lets a student say which class they are in, and sends them to that class's
/// advisor from then on.
///
/// Lives here rather than inside the profile tab because it is reached from
/// two places: the profile, where somebody is correcting a mistake, and the OD
/// tab, where their advisor has been removed and they are being asked to
/// choose again. Returns true if the class actually changed.
Future<bool> chooseClass(BuildContext context) async {
  final od = ODService();

  List<ClassYear> classes;
  try {
    classes = await od.loadClasses();
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message, error: true);
    return false;
  }
  if (!context.mounted) return false;

  final user = od.user;
  final picked = await showModalBottomSheet<({int year, String section})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ClassPicker(
      classes: classes,
      currentYear: user?.year,
      currentSection: user?.section,
    ),
  );
  if (picked == null || !context.mounted) return false;

  // Re-picking the same class is only a no-op when they still have an advisor;
  // a student whose advisor was removed is re-confirming, and that has to go
  // through so the server can attach them to whoever holds it now.
  final unchanged = picked.year == user?.year && picked.section == user?.section;
  if (unchanged && !(user?.needsClassUpdate ?? false)) return false;

  final ok = await confirm(
    context,
    title: 'Change your class?',
    message: 'New OD requests will go to the advisor for Year ${picked.year} '
        'Section ${picked.section}. Requests you have already sent stay with '
        'the advisor who received them.',
    confirmLabel: 'Change class',
  );
  if (!ok || !context.mounted) return false;

  try {
    final updated = await od.changeClass(year: picked.year, section: picked.section);
    if (context.mounted) {
      showToast(context, 'Class updated. Your advisor is now ${updated.advisorName}.');
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message, error: true);
    return false;
  }
}
