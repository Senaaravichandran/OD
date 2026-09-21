import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// Keeps a staff password session on the device.
///
/// Students are not stored here: Firebase already persists their session, and
/// their identity is re-read from the ID token on every call. Only the staff
/// password route produces something worth remembering, and what is kept is a
/// short-lived signed token plus the profile it resolved to - never a password.
class SessionService {
  static const _userKey = 'smvec_staff_user_v3';
  static const _tokenKey = 'smvec_staff_token_v3';

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
    } catch (_) {}
  }
}
