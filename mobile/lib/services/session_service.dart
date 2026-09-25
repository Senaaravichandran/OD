import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

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

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
      await prefs.remove(_tokenKey);
      await prefs.remove(_routeKey);
    } catch (_) {}
  }
}
