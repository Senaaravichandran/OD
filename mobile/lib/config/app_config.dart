class AppConfig {
  /// Base URL of the OD API (the Next.js route at /api/v2).
  /// Override at build time:
  ///   `flutter build apk --dart-define=API_BASE_URL=https://your-app.vercel.app/api/v2`
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://od-landing.vercel.app/api/v2',
  );

  static const String allowedDomain = '@smvec.ac.in';
  static const String hodEmail = 'hodit@smvec.ac.in';

  static const String appName = 'SMVEC-IT OD';
  static const String department = 'Department of Information Technology';

  /// Event types a student can raise an OD for.
  static const List<String> eventTypes = [
    'Hackathon',
    'Internship',
    'Paper Presentation',
    'Workshop',
    'Symposium',
    'Sports',
    'Other',
  ];

  /// Largest image we will upload, after compression.
  static const int maxUploadBytes = 10 * 1024 * 1024;

  /// Photos are resized to fit inside this before upload, which takes a
  /// typical 8-12 MB phone photo down to a few hundred kilobytes.
  static const int imageMaxDimension = 1600;
  static const int imageQuality = 80;
}
