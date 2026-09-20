import 'package:app_links/app_links.dart';
import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'models/user.dart';
import 'screens/advisor_dashboard.dart';
import 'screens/auth_screen.dart';
import 'screens/hod_dashboard.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_sheet.dart';
import 'screens/registration_screen.dart';
import 'screens/role_picker_screen.dart';
import 'screens/student_dashboard.dart';
import 'services/notification_service.dart';
import 'services/od_service.dart';
import 'services/session_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const SMVECODApp());
}

class SMVECODApp extends StatelessWidget {
  const SMVECODApp({super.key});

  /// Where Google should send the user back to once they have signed in.
  ///
  /// Returning a link here makes the Clerk SDK open the sign-in page in the
  /// device browser instead of an in-app WebView. That matters: Google refuses
  /// OAuth from embedded WebViews ("this browser or app may not be secure"),
  /// so the WebView route works on some devices and silently stalls on others.
  /// The scheme is registered in AndroidManifest.xml and Info.plist.
  static Uri? _redirect(BuildContext context, clerk.Strategy strategy) {
    if (strategy.isOauth || strategy.isEmailLink) {
      return Uri(scheme: 'smvecod', host: 'auth', path: '/callback');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);
    const goldAccent = Color(0xFFD4A429);

    // Clerk owns Google sign-in for the whole app, so it wraps everything.
    return ClerkAuth(
      config: ClerkAuthConfig(
        publishableKey: AppConfig.clerkPublishableKey,
        redirectionGenerator: _redirect,
        // Carries the browser's callback back into the SDK so the session is
        // picked up when the user returns to the app.
        deepLinkStream: AppLinks().uriLinkStream.where(
              (uri) => uri.scheme == 'smvecod',
            ),
      ),
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
        home: const _AppGate(),
      ),
    );
  }
}

/// Drives the whole sign-in journey:
///
///   role picker -> per-role sign-in -> (first time) profile -> dashboard
///
/// The chosen role only decides which sign-in options to show. What someone can
/// actually do comes from the profile the server returns.
class _AppGate extends StatefulWidget {
  const _AppGate();

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  AppUser? _currentUser;
  UserRole? _pickedRole;
  ({String email, String regToken, UserRole role})? _pendingProfile;
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
    if (mounted) {
      setState(() {
        _currentUser = user;
        _pendingProfile = null;
      });
    }
  }

  Future<void> _onUserUpdated(AppUser user) async {
    await SessionService.saveUser(user);
    if (mounted) setState(() => _currentUser = user);
  }

  /// Drops the app session and returns to the role picker. Clerk's own session
  /// is signed out too when one exists.
  Future<void> _signOut(ClerkAuthState? authState) async {
    await SessionService.clear();
    await NotificationService.reset();
    ODService().setUser(null);
    if (mounted) {
      setState(() {
        _currentUser = null;
        _pickedRole = null;
        _pendingProfile = null;
      });
    }
    if (authState != null && authState.isSignedIn) {
      await authState.signOut();
    }
  }

  void _onSessionExpired() {
    if (_currentUser == null) return;
    SessionService.clear();
    ODService().setUser(null);
    if (mounted) {
      setState(() {
        _currentUser = null;
        _pickedRole = null;
        _pendingProfile = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your session has expired. Please sign in again.')),
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
        signedOutBuilder: (context, authState) => _buildFlow(context, authState, false),
        signedInBuilder: (context, authState) => _buildFlow(context, authState, true),
      ),
    );
  }

  Widget _buildFlow(BuildContext context, ClerkAuthState authState, bool clerkSignedIn) {
    // Already through the door.
    final user = _currentUser;
    if (user != null) return _dashboard(user, authState);

    // First sign-in: finish the profile.
    final pending = _pendingProfile;
    if (pending != null) {
      return RegistrationScreen(
        email: pending.email,
        regToken: pending.regToken,
        initialRole: pending.role,
        onRegistered: _onLogin,
        onCancel: () => _signOut(authState),
      );
    }

    // Signed in with Google but no app session yet: exchange the Clerk token.
    if (clerkSignedIn) {
      return LoginScreen(
        authState: authState,
        onLogin: _onLogin,
        onNeedsRegistration: (email, regToken) => setState(
          () => _pendingProfile = (
            email: email,
            regToken: regToken,
            role: _pickedRole ?? UserRole.student,
          ),
        ),
        onSignOut: () => _signOut(authState),
      );
    }

    // Not signed in anywhere: pick a role, then a sign-in method.
    final role = _pickedRole;
    if (role == null) {
      return RolePickerScreen(onPick: (r) => setState(() => _pickedRole = r));
    }

    return AuthScreen(
      role: role,
      onSignedIn: _onLogin,
      onNeedsRegistration: (email, regToken, pickedRole) => setState(
        () => _pendingProfile = (email: email, regToken: regToken, role: pickedRole),
      ),
      onBack: () => setState(() => _pickedRole = null),
    );
  }

  Widget _dashboard(AppUser user, ClerkAuthState authState) {
    switch (user.role) {
      case UserRole.student:
        return StudentDashboard(
          user: user,
          onLogout: () => _signOut(authState),
          onUserUpdated: _onUserUpdated,
          onOpenNotifications: () => _showNotifications(context),
        );
      case UserRole.advisor:
        return AdvisorDashboard(
          user: user,
          onLogout: () => _signOut(authState),
          onUserUpdated: _onUserUpdated,
          onOpenNotifications: () => _showNotifications(context),
        );
      case UserRole.hod:
        return HodDashboard(
          user: user,
          onLogout: () => _signOut(authState),
          onOpenNotifications: () => _showNotifications(context),
        );
    }
  }
}
