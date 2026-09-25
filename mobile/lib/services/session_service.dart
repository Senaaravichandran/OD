import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// How somebody last got into the app.
///
/// Stated rather than inferred: start-up waits differently for each, and
/// guessing from whether a token happens to be present is what let a staff
/// session be filed as a Google one the moment its token went missing.
enum SignInRoute { google, staff }

/// Remembers, between launches, that somebody is signed in.
///
/// A staff password session is kept in full: the signed token and the profile
/// it resolved to - never a password. A student's session belongs to Firebase,
/// so all that is kept for them is the fact that they have one, which is what
/// tells start-up to wait for Firebase to finish restoring it rather than
/// believing the first "nobody is signed in" it hears.
class SessionService {
  static const _userKey = 'smvec_staff_user_v3';
  static const _tokenKey = 'smvec_staff_token_v3';
  static const _routeKey = 'smvec_signed_in_route_v1';
  static const _studentKey = 'smvec_student_user_v1';
  static const _signOutReasonKey = 'smvec_last_sign_out_reason_v1';

  /// The student's profile from last time.
  ///
  /// Their session itself belongs to Firebase - this is only so the app can
  /// open on their own screen while Firebase is still waking up, instead of
  /// showing a sign-in page to somebody who is signed in. Nothing here grants
  /// access: every call still carries a fresh Firebase token, and the server
  /// decides.
  static Future<void> saveStudent(AppUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_studentKey, jsonEncode(user.toJson()));
    } catch (_) {
      // A device that refuses storage just means a slower start-up.
    }
  }

  static Future<AppUser?> loadStudent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_studentKey);
      if (raw == null) return null;
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Why the last sign-out happened, kept so the sign-in screen can say.
  ///
  /// Being asked to sign in again with no explanation is the whole reason this
  /// took four attempts to find: every report was the same sentence, and the
  /// app knew more than it was saying.
  static Future<void> rememberSignOutReason(String reason) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_signOutReasonKey, reason);
    } catch (_) {}
  }

  static Future<String?> takeSignOutReason() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reason = prefs.getString(_signOutReasonKey);
      await prefs.remove(_signOutReasonKey);
      return reason;
    } catch (_) {
      return null;
    }
  }

  /// How the person got in last time: 'google' or 'staff'.
  static Future<void> rememberRoute(String route) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_routeKey, route);
    } catch (_) {
      // Storage refused. The app still works; start-up just falls back to
      // asking Firebase without waiting as long.
    }
  }

  static Future<String?> lastRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_routeKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveStaff(AppUser user) async {
    if (user.staffToken == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
      await prefs.setString(_tokenKey, user.staffToken!);
    } catch (_) {
      // A device that refuses storage just means signing in again next time.
    }
  }

  static Future<AppUser?> loadStaff() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_userKey);
      final token = prefs.getString(_tokenKey);
      if (raw == null || token == null) return null;
      return AppUser.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
        staffToken: token,
      );
    } catch (_) {
      return null;
    }
  }

  /// Forgets who was signed in. The sign-out reason is deliberately left
  /// behind, so the sign-in screen can still explain itself.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
      await prefs.remove(_tokenKey);
      await prefs.remove(_routeKey);
      await prefs.remove(_studentKey);
    } catch (_) {}
  }
}
