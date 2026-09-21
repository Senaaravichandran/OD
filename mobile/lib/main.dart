import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'models/user.dart';
import 'screens/advisor/advisor_shell.dart';
import 'screens/auth_screen.dart';
import 'screens/hod/hod_shell.dart';
import 'screens/registration_screen.dart';
import 'screens/role_picker_screen.dart';
import 'screens/student/student_shell.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/od_service.dart';
import 'services/push_service.dart';
import 'services/session_service.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.init();
  runApp(const SmvecOdApp());
}

class SmvecOdApp extends StatelessWidget {
  const SmvecOdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AppGate(),
    );
  }
}

/// Decides what to show:
///
///   role picker -> sign in -> (first time) profile -> the role's app
///
/// The role someone taps only decides which sign-in options appear. What they
/// are actually allowed to do comes from the profile the server returns.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  final _od = ODService();

  AppUser? _user;
  UserRole? _pickedRole;
  bool _booting = true;
  bool _exchanging = false;
  String? _error;
  ({String email, String name})? _needsProfile;

  @override
  void initState() {
    super.initState();
    _od.onSessionExpired = _onSessionExpired;
    _boot();
  }

  /// On launch: a staff password session is restored from the device, and a
  /// Firebase session is resumed by asking the server who we are.
  Future<void> _boot() async {
    final staff = await SessionService.loadStaff();
    if (staff != null) {
      await _adopt(staff);
      if (mounted) setState(() => _booting = false);
      return;
    }

    if (AuthService.isSignedIn) {
      await _exchangeFirebaseSession();
    }
    if (mounted) setState(() => _booting = false);
  }

  /// Trades the current Firebase session for a profile.
  Future<void> _exchangeFirebaseSession() async {
    setState(() {
      _exchanging = true;
      _error = null;
    });
    try {
      final res = await ApiClient.call('SESSION');
      if (res['needsRegistration'] == true) {
        setState(() {
          _needsProfile = (
            email: res['email']?.toString() ?? '',
            name: res['name']?.toString() ?? '',
          );
          _user = null;
        });
      } else {
        await _adopt(AppUser.fromJson(res['user'] as Map<String, dynamic>));
      }
    } on ApiException catch (e) {
      // The server refused this account - wrong domain, or disabled. Signing
      // out is the only way forward, so make that the offered action.
      setState(() => _error = e.message);
      await AuthService.signOut();
    } finally {
      if (mounted) setState(() => _exchanging = false);
    }
  }

  Future<void> _adopt(AppUser user) async {
    _od.setUser(user);
    if (user.staffToken != null) await SessionService.saveStaff(user);
    await PushService.start();
    if (mounted) {
      setState(() {
        _user = user;
        _needsProfile = null;
        _error = null;
      });
    }
  }

  Future<void> _signOut() async {
    await PushService.stop();
    await SessionService.clear();
    await NotificationService.reset();
    ApiClient.clearStaffToken();
    await AuthService.signOut();
    _od.setUser(null);
    if (mounted) {
      setState(() {
        _user = null;
        _pickedRole = null;
        _needsProfile = null;
        _error = null;
      });
    }
  }

  void _onSessionExpired() {
    if (_user == null) return;
    _signOut();
    if (mounted) {
      showToast(context, 'Your session expired. Please sign in again.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_booting || _exchanging) return const _Splash();

    if (_error != null && _user == null) {
      return _ErrorGate(message: _error!, onRetry: () => setState(() => _error = null));
    }

    final pending = _needsProfile;
    if (pending != null) {
      return RegistrationScreen(
        email: pending.email,
        suggestedName: pending.name,
        onDone: _adopt,
        onCancel: _signOut,
      );
    }

    final user = _user;
    if (user != null) {
      switch (user.role) {
        case UserRole.student:
          return StudentShell(user: user, onSignOut: _signOut);
        case UserRole.advisor:
          return AdvisorShell(user: user, onSignOut: _signOut);
        case UserRole.hod:
          return HodShell(user: user, onSignOut: _signOut);
      }
    }

    final role = _pickedRole;
    if (role == null) {
      return RolePickerScreen(onPick: (r) => setState(() => _pickedRole = r));
    }

    return AuthScreen(
      role: role,
      onBack: () => setState(() => _pickedRole = null),
      onFirebaseSignedIn: _exchangeFirebaseSession,
      onStaffSignedIn: _adopt,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/app_icon.png', height: 96),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'Signing you in…',
              style: TextStyle(color: AppTheme.muted, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorGate extends StatelessWidget {
  const _ErrorGate({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block_rounded, size: 52, color: AppTheme.danger),
              const SizedBox(height: 18),
              const Text(
                'Cannot sign you in',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted, height: 1.45),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Back to sign in')),
            ],
          ),
        ),
      ),
    );
  }
}
