import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);

  bool get isAuthError => statusCode == 401;
  bool get isConflict => statusCode == 409;

  /// The server looked at who this is and said no. The only kind of failure
  /// worth destroying a session over.
  bool get isRefused => statusCode == 401 || statusCode == 403;

  /// The request never reached the server, or never came back: a dropped
  /// connection, a timeout, a radio still waking up. Nothing has been said
  /// about the session, so nothing should be concluded about it.
  bool get isOffline => statusCode == null;

  @override
  String toString() => message;
}

/// JSON client for /api/v2. Every call is a single POST of
/// `{action, payload}`; the Firebase ID token rides in the Authorization
/// header and is refreshed automatically when the server says it expired.
class ApiClient {
  /// A staff session token, set after a password sign-in. Students never have
  /// one - they authenticate with Firebase on every call.
  static String? _staffToken;

  static void setStaffToken(String? token) => _staffToken = token;
  static void clearStaffToken() => _staffToken = null;
  static bool get hasStaffToken => _staffToken != null;

  static Future<Map<String, dynamic>> call(
    String action, {
    Map<String, dynamic> payload = const {},
    bool authenticated = true,
    bool retriedAfterRefresh = false,
  }) async {
    String? token = _staffToken;
    if (authenticated && token == null) {
      // Waited for, not merely asked. Firebase restores its session from disk
      // a moment after start-up, so currentUser is null for the first instant
      // of every launch - and the first call of every launch lands squarely in
      // it. Reading that null as "signed out" turned the opening sync into a
      // 401, which signs the person out and wipes their session: the app threw
      // people out precisely because it had just been opened.
      //
      // The wait happens once; after that this returns straight away.
      final user = await AuthService.ensureRestored();
      if (user == null) {
        throw ApiException('You are not signed in. Please sign in again.', 401);
      }

      token = await AuthService.idToken(force: retriedAfterRefresh);
      if (token == null) {
        throw ApiException(
          'Could not reach sign-in services. Check your connection.',
        );
      }
    }

    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(AppConfig.apiBaseUrl),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'action': action, 'payload': payload}),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException('The server took too long to respond. Please try again.');
    } catch (_) {
      throw ApiException('Could not reach the server. Check your connection.');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Unexpected server response (${res.statusCode}).', res.statusCode);
    }

    if (res.statusCode == 401 && !retriedAfterRefresh && _staffToken == null) {
      // The token may simply have aged out mid-session; mint a fresh one and
      // try once more before troubling the user.
      return call(
        action,
        payload: payload,
        authenticated: authenticated,
        retriedAfterRefresh: true,
      );
    }

    if (res.statusCode >= 400 || data['success'] != true) {
      throw ApiException(
        data['error']?.toString() ?? 'Something went wrong.',
        res.statusCode,
      );
    }
    return data;
  }

  /// Calls that work before anyone is signed in, such as the class list.
  static Future<Map<String, dynamic>> callPublic(
    String action, {
    Map<String, dynamic> payload = const {},
  }) =>
      call(action, payload: payload, authenticated: false);
}
