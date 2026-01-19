/// API endpoint constants
class ApiEndpoints {
  ApiEndpoints._();

  // Base URLs
  /// Production API base URL
  static const String baseUrl = 'https://api.aster.wallet';

  /// Staging API base URL
  static const String stagingBaseUrl = 'https://api-staging.aster.wallet';

  // Auth
  /// Login endpoint
  static const String login = '/api/v2/auth/login/';

  /// Email verification endpoint
  static const String verify = '/api/v1/auth/verify/';

  /// User information endpoint
  static const String user = '/api/v1/auth/user/';

  /// Account reset endpoint
  static const String resetAccount = '/api/v1/auth/user/email-reset/';

  // Wallet
  /// Wallet operations endpoint
  static const String wallet = '/api/v1/wallet/';

  /// Wallet balance endpoint
  static const String balance = '/api/v1/wallet/balance/';

  /// Wallet transactions endpoint
  static const String transactions = '/api/v1/wallet/transactions/';

  // Exchange Rates
  /// Exchange rates endpoint
  static const String exchangeRates = '/api/v1/exrates/';

  /// Daily price endpoint
  static const String dailyPrice = '/api/v1/daily-price/';

  /// Last day prices endpoint
  static const String lastDayPrices = '/api/v1/prices/last-day/';

  // Health
  /// Health check endpoint
  static const String health = '/api/v1/health/';
}
