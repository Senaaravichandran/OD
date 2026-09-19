import 'package:flutter/material.dart';
import 'models/user.dart';
import 'screens/login_screen.dart';
import 'screens/student_dashboard.dart';
import 'screens/advisor_dashboard.dart';
import 'screens/hod_dashboard.dart';
import 'screens/notifications_sheet.dart';
import 'services/od_service.dart';
import 'services/session_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SMVECODApp());
}

class SMVECODApp extends StatefulWidget {
  const SMVECODApp({super.key});

  @override
  State<SMVECODApp> createState() => _SMVECODAppState();
}

class _SMVECODAppState extends State<SMVECODApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  AppUser? _currentUser;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    ODService().onSessionExpired = _onSessionExpired;
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final user = await SessionService.loadUser();
    if (!mounted) return;
    setState(() {
      _currentUser = user;
      _restoring = false;
    });
    ODService().setUser(user);
  }

  Future<void> _onLogin(AppUser user) async {
    await SessionService.saveUser(user);
    ODService().setUser(user);
    if (mounted) setState(() => _currentUser = user);
  }

  Future<void> _onUserUpdated(AppUser user) async {
    await SessionService.saveUser(user);
    if (mounted) setState(() => _currentUser = user);
  }

  Future<void> _onLogout() async {
    await SessionService.clear();
    ODService().setUser(null);
    if (mounted) setState(() => _currentUser = null);
  }

  void _onSessionExpired() {
    if (_currentUser == null) return;
    _onLogout();
    final ctx = _navigatorKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Your session has expired. Please log in again.')),
      );
    }
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
      navigatorKey: _navigatorKey,
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
          if (_restoring) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final user = _currentUser;
          if (user == null) {
            return LoginScreen(onLogin: _onLogin);
          }

          switch (user.role) {
            case UserRole.student:
              return StudentDashboard(
                user: user,
                onLogout: _onLogout,
                onOpenNotifications: () => _showNotifications(context),
              );
            case UserRole.advisor:
              return AdvisorDashboard(
                user: user,
                onLogout: _onLogout,
                onUserUpdated: _onUserUpdated,
                onOpenNotifications: () => _showNotifications(context),
              );
            case UserRole.hod:
              return HodDashboard(
                user: user,
                onLogout: _onLogout,
                onOpenNotifications: () => _showNotifications(context),
              );
          }
        },
      ),
    );
  }
}
