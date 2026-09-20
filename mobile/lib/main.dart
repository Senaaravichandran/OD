import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'models/user.dart';
import 'screens/advisor_dashboard.dart';
import 'screens/hod_dashboard.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_sheet.dart';
import 'screens/student_dashboard.dart';
import 'services/od_service.dart';
import 'services/session_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SMVECODApp());
}

class SMVECODApp extends StatelessWidget {
  const SMVECODApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);
    const goldAccent = Color(0xFFD4A429);

    // Clerk owns sign-in for the whole app, so it wraps everything.
    return ClerkAuth(
      config: ClerkAuthConfig(publishableKey: AppConfig.clerkPublishableKey),
      child: MaterialApp(
        title: 'SMVEC OD Management',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: ClerkSdkLocalizations.localizationsDelegates,
        supportedLocales: ClerkSdkLocalizations.supportedLocales,
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
        home: const _AuthGate(),
      ),
    );
  }
}

/// Decides what to show based on the Clerk session.
///
/// Signed out -> Clerk's own sign-in UI. Signed in -> [LoginScreen] trades the
/// Clerk session for an app session (and collects a profile the first time),
/// after which the role dashboards take over.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
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

  /// Clears the app session. Clerk's own session is signed out separately by
  /// whichever widget triggered this.
  Future<void> _clearAppSession() async {
    await SessionService.clear();
    ODService().setUser(null);
    if (mounted) setState(() => _currentUser = null);
  }

  Future<void> _onLogout(ClerkAuthState authState) async {
    await _clearAppSession();
    await authState.signOut();
  }

  void _onSessionExpired() {
    if (_currentUser == null) return;
    _clearAppSession();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
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
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ClerkErrorListener(
      child: ClerkAuthBuilder(
        signedOutBuilder: (context, authState) {
          // The app session cannot outlive the Clerk session.
          if (_currentUser != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _clearAppSession());
          }
          return const Scaffold(body: SafeArea(child: ClerkAuthentication()));
        },
        signedInBuilder: (context, authState) {
          final user = _currentUser;
          if (user == null) {
            return LoginScreen(authState: authState, onLogin: _onLogin);
          }

          switch (user.role) {
            case UserRole.student:
              return StudentDashboard(
                user: user,
                onLogout: () => _onLogout(authState),
                onOpenNotifications: () => _showNotifications(context),
              );
            case UserRole.advisor:
              return AdvisorDashboard(
                user: user,
                onLogout: () => _onLogout(authState),
                onUserUpdated: _onUserUpdated,
                onOpenNotifications: () => _showNotifications(context),
              );
            case UserRole.hod:
              return HodDashboard(
                user: user,
                onLogout: () => _onLogout(authState),
                onOpenNotifications: () => _showNotifications(context),
              );
          }
        },
      ),
    );
  }
}
