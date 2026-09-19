class AppConfig {
  /// Base URL of the mobile API (the Next.js route at /api/mobile).
  /// Override at build time:
  ///   `flutter build apk --dart-define=API_BASE_URL=https://your-app.vercel.app/api/mobile`
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://od-landing.vercel.app/api/mobile',
  );

  static const String allowedDomain = '@smvec.ac.in';
  static const String hodEmail = 'hodit@smvec.ac.in';

  static const List<int> years = [1, 2, 3, 4];
  static const List<String> sections = ['A', 'B', 'C', 'D', 'E', 'F'];
}
