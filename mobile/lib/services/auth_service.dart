import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/app_config.dart';

/// Firebase identity for the app.
///
/// Students sign in with Google and nothing else - an OD is filed against a
/// real, verified college address. Staff and the HOD may instead exchange a
/// password with the server, which happens in [ApiClient], not here.
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    // Nudges Google's picker towards college accounts. The real restriction is
    // enforced by the server, which checks the verified address on every call.
    hostedDomain: 'smvec.ac.in',
  );

  static User? get currentUser => _auth.currentUser;
  static bool get isSignedIn => _auth.currentUser != null;
  static Stream<User?> get changes => _auth.authStateChanges();

  /// Who is signed in, once Firebase has finished restoring from disk.
  ///
  /// This is fiddlier than it looks, and getting it wrong is what kept sending
  /// people back to the sign-in screen on every launch.
  ///
  /// Firebase does keep the session on the device, but it restores it
  /// asynchronously. Reading currentUser straight after initializeApp() gives
  /// null, and - the part that caught us a second time - authStateChanges()
  /// does not wait either: it emits immediately with whatever the plugin has
  /// cached, which on a cold start is that same null. The restored user
  /// arrives afterwards, as a second event. Taking the first event therefore
  /// reports "signed out" for somebody who is perfectly well signed in.
  ///
  /// So when our own record says somebody was signed in, wait for a user
  /// rather than for an answer, and only conclude they are gone once a
  /// generous window has passed. When there is no such record, one event is
  /// enough and start-up stays quick.
  static Future<User?> restoreSession({required bool expectUser}) =>
      awaitRestore<User>(
        current: _auth.currentUser,
        changes: changes,
        expectUser: expectUser,
        fallback: () => _auth.currentUser,
      );

  /// The waiting rule on its own, with no Firebase in it, so the behaviour
  /// that has now been got wrong twice can be tested directly.
  ///
  /// [expectUser] says whether our own record claims somebody is signed in.
  /// When it does, a null is treated as "not yet" rather than as an answer.
  @visibleForTesting
  static Future<T?> awaitRestore<T extends Object>({
    required T? current,
    required Stream<T?> changes,
    required bool expectUser,
    T? Function()? fallback,
    Duration patient = const Duration(seconds: 10),
    Duration brief = const Duration(seconds: 3),
  }) async {
    if (current != null) return current;

    try {
      if (!expectUser) {
        return await changes.first.timeout(brief);
      }
      return await changes.firstWhere((v) => v != null).timeout(patient);
    } catch (err) {
      // Either the restore genuinely found nobody - the account was removed,
      // or the credentials were cleared - or the device is being unusually
      // slow. Fall back to whatever is known now; the sign-in screen is the
      // right answer if that is still nothing.
      debugPrint('no session restored after waiting: $err');
      return fallback?.call();
    }
  }

  /// Google sign-in. Returns the signed-in user, or null if the person backed
  /// out of the account picker.
  static Future<User?> signInWithGoogle() async {
    // Always start from a clean slate so the account chooser actually appears
    // rather than silently reusing whichever account signed in last.
    await _google.signOut();

    final account = await _google.signIn();
    if (account == null) return null; // cancelled

    final email = account.email.toLowerCase();
    if (!email.endsWith(AppConfig.allowedDomain)) {
      await _google.signOut();
      throw AuthFailure(
        'Use your college ${AppConfig.allowedDomain} account.\n\n'
        'You picked $email.',
      );
    }

    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
    );

    try {
      final result = await _auth.signInWithCredential(credential);
      return result.user;
    } on FirebaseAuthException catch (e) {
      await _google.signOut();
      throw AuthFailure(_describe(e));
    }
  }

  /// The ID token the API needs. Refreshed when [force] is set, which matters
  /// after a role change so the server sees the new claims.
  static Future<String?> idToken({bool force = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(force);
    } catch (err) {
      debugPrint('could not read ID token: $err');
      return null;
    }
  }

  static Future<void> signOut() async {
    // Google sign-out can fail when there is no network; the Firebase sign-out
    // is the one that must happen, so it is not allowed to be skipped.
    try {
      await _google.signOut();
    } catch (err) {
      debugPrint('google sign-out failed, continuing: $err');
    }
    await _auth.signOut();
  }

  /// Turns Firebase's error codes into something a student can act on.
  static String _describe(FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return 'This email is already registered with a different sign-in method.';
      case 'invalid-credential':
        return 'Google sign-in could not be completed. Please try again.';
      case 'user-disabled':
        return 'This account has been disabled. Contact the department.';
      case 'network-request-failed':
        return 'No internet connection. Check your network and try again.';
      case 'operation-not-allowed':
        return 'Google sign-in is not enabled for this app. Contact the department.';
      default:
        return e.message ?? 'Sign-in failed (${e.code}).';
    }
  }
}

class AuthFailure implements Exception {
  final String message;
  AuthFailure(this.message);
  @override
  String toString() => message;
}
