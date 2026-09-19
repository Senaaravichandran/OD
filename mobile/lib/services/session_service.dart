import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

/// Keeps the signed-in user on the device so they stay logged in.
class SessionService {
  static const _userKey = 'smvec_user_v2';
  static const _tokenKey = 'smvec_token_v2';

  static Future<void> saveUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    await prefs.setString(_tokenKey, user.token);
  }

  static Future<AppUser?> loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_userKey);
      final token = prefs.getString(_tokenKey);
      if (raw == null || token == null) return null;
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>, token);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey);
  }
}
