import 'dart:async';

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

  // If Firebase cannot start there is nothing the app can do, but it must say
  // so rather than die into a black screen - that is impossible to diagnose
  // from a phone.
  String? startupError;
  try {
    await Firebase.initializeApp();
  } catch (err) {
    startupError = 'Could not start sign-in services.\n\n$err';
  }

  // Notifications are optional; a device that refuses them still works.
  try {
    await NotificationService.init();
  } catch (_) {}

  runApp(startupError == null
      ? const SmvecOdApp()
      : _StartupFailureApp(message: startupError));
}

/// Shown when the app cannot start at all, so the reason is visible on the
/// device instead of a blank window.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 54, color: AppTheme.danger),
                const SizedBox(height: 18),
                const Text(
                  'SMVEC-IT OD could not start',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.muted, height: 1.45),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Please reinstall the latest APK, or contact the department.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
  ///
  /// Nobody should have to sign in twice. Both routes keep a session on the
  /// device, so the only thing this does is wait long enough to find it.
  Future<void> _boot() async {
    final staff = await SessionService.loadStaff();
    if (staff != null) {
      // Open straight onto their own screen, then confirm with the server
      // behind it. Waiting first would mean staring at the splash on a slow
      // connection for a session we already have.
      await _adopt(staff);
      if (mounted) setState(() => _booting = false);
      unawaited(_confirmStaffSession());
      return;
    }

    // Waited for, not merely read: Firebase restores a saved session a moment
    // after start-up, and asking too early makes a signed-in student look
    // signed out.
    if (await AuthService.restoreSession() != null) {
      await _exchangeFirebaseSession();
    }
    if (mounted) setState(() => _booting = false);
  }

  /// Checks a restored staff session and takes the renewed token with it.
  ///
  /// The server slides the expiry: a session that is getting on comes back
  /// with a fresh token, so somebody who keeps using the app is never asked
  /// for the password again. A session that has genuinely lapsed signs out.
  Future<void> _confirmStaffSession() async {
    try {
      final res = await ApiClient.call('SESSION');
      final renewed = res['token']?.toString();
      final user = AppUser.fromJson(
        res['user'] as Map<String, dynamic>,
        staffToken: renewed ?? _user?.staffToken,
      );
      await _adopt(user);
    } on ApiException catch (e) {
      // Only an expired session is worth signing out for. A flat battery of a
      // connection should not throw the person out of the app.
      if (e.isAuthError) await _signOut();
    }
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
