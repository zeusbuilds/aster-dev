/// Application-wide constants
class AppConstants {
  AppConstants._();

  // App Info
  /// Application name
  static const String appName = 'aster';

  /// Application version
  static const String appVersion = '1.0.0';

  // Timeouts
  /// Connection timeout duration for network requests
  static const Duration connectionTimeout = Duration(seconds: 30);

  /// Receive timeout duration for network requests
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// Send timeout duration for network requests
  static const Duration sendTimeout = Duration(seconds: 30);

  // Pagination
  /// Default number of items per page
  static const int defaultPageSize = 20;

  /// Maximum number of items per page
  static const int maxPageSize = 100;

  // Cache
  /// Default cache duration for cached data
  static const Duration defaultCacheDuration = Duration(minutes: 5);

  /// Long cache duration for rarely changing data
  static const Duration longCacheDuration = Duration(hours: 24);
}
