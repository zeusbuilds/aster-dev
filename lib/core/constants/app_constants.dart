/// Application-wide constants
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'aster';
  static const String appVersion = '1.0.0';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // Cache
  static const Duration defaultCacheDuration = Duration(minutes: 5);
  static const Duration longCacheDuration = Duration(hours: 24);
}
