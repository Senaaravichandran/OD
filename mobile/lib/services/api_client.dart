import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);

  bool get isAuthError => statusCode == 401;

  @override
  String toString() => message;
}

/// Minimal JSON client for /api/mobile. Every call is a single POST.
class ApiClient {
  static Future<Map<String, dynamic>> call(
    String action, {
    Map<String, dynamic> payload = const {},
    String? token,
  }) async {
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
          .timeout(const Duration(seconds: 20));
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

    if (res.statusCode >= 400 || data['success'] != true) {
      throw ApiException(data['error']?.toString() ?? 'Something went wrong.', res.statusCode);
    }
    return data;
  }
}
