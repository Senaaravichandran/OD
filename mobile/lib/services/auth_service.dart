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
