class AppConfig {
  /// Base URL of the mobile API (the Next.js route at /api/mobile).
  /// Override at build time:
  ///   `flutter build apk --dart-define=API_BASE_URL=https://your-app.vercel.app/api/mobile`
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://od-landing.vercel.app/api/mobile',
  );

  /// Clerk publishable key. This is a public value - it ships in the web
  /// bundle too - but it still differs between the development and production
  /// Clerk instances, so override it for a production build:
  ///   `flutter build apk --dart-define=CLERK_PUBLISHABLE_KEY=pk_live_...`
  static const String clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
    defaultValue: 'pk_test_cmVuZXdpbmctcm91Z2h5LTY2MDMuY2xlcmsuYWNjb3VudHMuZGV2JA',
  );

  static const String allowedDomain = '@smvec.ac.in';
  static const String hodEmail = 'hodit@smvec.ac.in';

  static const List<int> years = [1, 2, 3, 4];
  static const List<String> sections = ['A', 'B', 'C', 'D', 'E', 'F'];
}
