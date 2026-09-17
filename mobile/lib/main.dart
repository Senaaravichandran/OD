import 'package:flutter/material.dart';
import 'models/user.dart';
import 'screens/login_screen.dart';
import 'screens/student_dashboard.dart';
import 'screens/advisor_dashboard.dart';
import 'screens/hod_dashboard.dart';
import 'screens/notifications_sheet.dart';

void main() {
  runApp(const SMVECODApp());
}

class SMVECODApp extends StatefulWidget {
  const SMVECODApp({super.key});

  @override
  State<SMVECODApp> createState() => _SMVECODAppState();
}

class _SMVECODAppState extends State<SMVECODApp> {
  AppUser? _currentUser;

  void _onLogin(AppUser user) {
    setState(() {
      _currentUser = user;
    });
  }

  void _onLogout() {
    setState(() {
      _currentUser = null;
    });
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const NotificationsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);
    const goldAccent = Color(0xFFD4A429);

    return MaterialApp(
      title: 'SMVEC OD Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          secondary: goldAccent,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F8FD),
        fontFamily: 'Roboto',
      ),
      home: Builder(
        builder: (context) {
          if (_currentUser == null) {
            return LoginScreen(onLogin: _onLogin);
          }

          switch (_currentUser!.role) {
            case UserRole.student:
              return StudentDashboard(
                user: _currentUser!,
                onLogout: _onLogout,
                onOpenNotifications: () => _showNotifications(context),
              );
            case UserRole.advisor:
              return AdvisorDashboard(
                user: _currentUser!,
                onLogout: _onLogout,
                onOpenNotifications: () => _showNotifications(context),
              );
            case UserRole.hod:
              return HodDashboard(
                user: _currentUser!,
                onLogout: _onLogout,
                onOpenNotifications: () => _showNotifications(context),
              );
          }
        },
      ),
    );
  }
}
