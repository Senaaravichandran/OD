import 'package:flutter/material.dart';

import '../models/user.dart';

/// The first screen of the app: who are you signing in as?
///
/// The choice only decides which sign-in options to offer. What a person is
/// actually allowed to do is decided by the server from their profile, never
/// by which button they pressed here.
class RolePickerScreen extends StatelessWidget {
  const RolePickerScreen({super.key, required this.onPick});

  final void Function(UserRole role) onPick;

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/college_logo.png', height: 88),
                const SizedBox(height: 24),
                const Text(
                  'SMVEC OD Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: primaryBlue,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Department of Information Technology',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 36),
                const Text(
                  'Continue as',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  icon: Icons.school_outlined,
                  title: 'Student',
                  subtitle: 'Raise OD requests and track approvals',
                  onTap: () => onPick(UserRole.student),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  icon: Icons.groups_outlined,
                  title: 'Class Advisor',
                  subtitle: 'Review your class’s OD requests',
                  onTap: () => onPick(UserRole.advisor),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  icon: Icons.verified_user_outlined,
                  title: 'HOD',
                  subtitle: 'Give final sanction on recommended ODs',
                  onTap: () => onPick(UserRole.hod),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: primaryBlue),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
