import '../config/app_config.dart';

/// Returns an error message, or null when the email is a valid college email.
String? validateCollegeEmail(String email) {
  final e = email.trim().toLowerCase();
  if (e.isEmpty) return 'Enter your college email address.';
  if (e.contains(' ') || !e.endsWith(AppConfig.allowedDomain) || e.length <= AppConfig.allowedDomain.length) {
    return 'Only official ${AppConfig.allowedDomain} email addresses are allowed.';
  }
  return null;
}

/// Batch must look like "2023-2027" (a four-year span).
String? validateBatch(String batch) {
  final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(batch.trim());
  if (match == null) return 'Enter the batch in the format 2023-2027.';
  final start = int.parse(match.group(1)!);
  final end = int.parse(match.group(2)!);
  if (start < 2000 || end - start != 4) return 'Batch must span four years, e.g. 2023-2027.';
  return null;
}

String yearLabel(int year) {
  const labels = {1: 'I Year', 2: 'II Year', 3: 'III Year', 4: 'IV Year'};
  return labels[year] ?? 'Year $year';
}
