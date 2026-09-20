import 'package:clerk_flutter/clerk_flutter.dart';

import '../models/od_request.dart' show AdvisorInfo, ClassYear;
import '../models/user.dart';
import 'api_client.dart';

/// Result of trading a Clerk session for an app session.
///
/// Either [user] is set (the profile already exists) or [needsRegistration] is
/// true and [regToken] carries the server's proof that Clerk verified this
/// email address.
class ClerkExchange {
  final AppUser? user;
  final bool needsRegistration;
  final String? email;
  final String? regToken;

  const ClerkExchange._({
    this.user,
    this.needsRegistration = false,
    this.email,
    this.regToken,
  });
}

/// Turns a Clerk sign-in into an app session.
///
/// Clerk is the only identity provider: it owns the email verification, so the
/// app never sends mail of its own. The Clerk session token is presented once
/// to CLERK_LOGIN, which returns the app token used for every later call.
class ClerkSession {
  /// Reads the current Clerk session token and exchanges it.
  static Future<ClerkExchange> exchange(ClerkAuthState authState) async {
    String jwt;
    try {
      final token = await authState.sessionToken();
      jwt = token.jwt;
    } catch (_) {
      throw ApiException('Could not read your sign-in. Please sign in again.', 401);
    }

    final res = await ApiClient.call('CLERK_LOGIN', token: jwt);

    if (res['needsRegistration'] == true) {
      return ClerkExchange._(
        needsRegistration: true,
        email: res['email']?.toString(),
        regToken: res['regToken']?.toString(),
      );
    }
    return ClerkExchange._(
      user: AppUser.fromJson(
        res['user'] as Map<String, dynamic>,
        res['token']?.toString() ?? '',
      ),
    );
  }

  /// Password sign-in, for staff and the HOD only.
  static Future<ClerkExchange> passwordLogin({
    required String role,
    required String email,
    required String password,
  }) async {
    final res = await ApiClient.call('PASSWORD_LOGIN', payload: {
      'role': role,
      'email': email,
      'password': password,
    });

    if (res['needsRegistration'] == true) {
      return ClerkExchange._(
        needsRegistration: true,
        email: res['email']?.toString(),
        regToken: res['regToken']?.toString(),
      );
    }
    return ClerkExchange._(
      user: AppUser.fromJson(
        res['user'] as Map<String, dynamic>,
        res['token']?.toString() ?? '',
      ),
    );
  }

  /// The class advisors a student can be attached to. Reachable without a
  /// session, because it is needed to finish registering.
  static Future<List<AdvisorInfo>> advisors() async {
    final res = await ApiClient.call('ADVISORS');
    return (res['advisors'] as List? ?? [])
        .map((e) => AdvisorInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The department's class structure: which sections exist in each year and
  /// which advisor holds each one. A student picks a class, not an advisor.
  static Future<List<ClassYear>> classes() async {
    final res = await ApiClient.call('ADVISORS');
    return (res['classes'] as List? ?? [])
        .map((e) => ClassYear.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Completes a first-time profile and returns the signed-in user.
  static Future<AppUser> register({
    required String regToken,
    required String role,
    required String name,
    int? year,
    String? section,
    String? rollNumber,
    String? batch,
    String? staffCode,
    String? advisorEmail,
  }) async {
    final res = await ApiClient.call('REGISTER', payload: {
      'regToken': regToken,
      'role': role,
      'name': name,
      if (year != null) 'year': year,
      if (section != null) 'section': section,
      if (rollNumber != null) 'rollNumber': rollNumber,
      if (batch != null) 'batch': batch,
      if (staffCode != null) 'staffCode': staffCode,
      if (advisorEmail != null) 'advisorEmail': advisorEmail,
    });
    return AppUser.fromJson(
      res['user'] as Map<String, dynamic>,
      res['token']?.toString() ?? '',
    );
  }
}
