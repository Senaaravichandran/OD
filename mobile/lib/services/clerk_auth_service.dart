import 'dart:convert';
import 'package:http/http.dart' as http;
import 'clerk_auth_io.dart' if (dart.library.html) 'clerk_auth_web.dart' as platform;

class ClerkAuthService {
  static const String clerkBaseUrl = 'https://renewing-roughy-6603.clerk.accounts.dev';

  /// Initiates genuine Clerk Google OAuth flow and redirects the browser
  /// directly to the Google Account Chooser screen.
  static Future<bool> initiateGoogleSignIn({String? customRedirect}) async {
    try {
      final origin = platform.getCurrentOrigin();
      final redirect = customRedirect ?? (origin.isNotEmpty ? origin : 'http://localhost:8080');

      final uri = Uri.parse('$clerkBaseUrl/v1/client/sign_ins');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'strategy=oauth_google&redirect_url=${Uri.encodeComponent(redirect)}',
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final authUrl = data['response']?['first_factor_verification']?['external_verification_redirect_url'];
        if (authUrl != null && authUrl.toString().isNotEmpty) {
          platform.launchUrlPlatform(authUrl.toString());
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Checks if there is already an active signed-in Clerk session
  static Future<Map<String, dynamic>?> checkActiveClerkSession() async {
    try {
      final uri = Uri.parse('$clerkBaseUrl/v1/client');
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final sessions = data['client']?['sessions'] as List?;
        if (sessions != null && sessions.isNotEmpty) {
          final activeSession = sessions.firstWhere(
            (s) => s['status'] == 'active',
            orElse: () => sessions.first,
          );
          if (activeSession != null && activeSession['user'] != null) {
            final user = activeSession['user'];
            final emailList = user['email_addresses'] as List?;
            final primaryEmailId = user['primary_email_address_id'];
            String email = '';
            if (emailList != null && emailList.isNotEmpty) {
              final primary = emailList.firstWhere(
                (e) => e['id'] == primaryEmailId,
                orElse: () => emailList.first,
              );
              email = primary['email_address'] ?? '';
            }
            final firstName = user['first_name'] ?? '';
            final lastName = user['last_name'] ?? '';
            final name = '$firstName $lastName'.trim();
            return {
              'email': email.toLowerCase(),
              'name': name.isNotEmpty ? name : email.split('@')[0].toUpperCase(),
            };
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
