/// API endpoint constants
class ApiEndpoints {
  ApiEndpoints._();

  // Base URLs
  static const String baseUrl = 'https://api.aster.wallet';
  static const String stagingBaseUrl = 'https://api-staging.aster.wallet';

  // Auth
  static const String login = '/api/v2/auth/login/';
  static const String verify = '/api/v1/auth/verify/';
  static const String user = '/api/v1/auth/user/';
  static const String resetAccount = '/api/v1/auth/user/email-reset/';

  // Wallet
  static const String wallet = '/api/v1/wallet/';
  static const String balance = '/api/v1/wallet/balance/';
  static const String transactions = '/api/v1/wallet/transactions/';

  // Exchange Rates
  static const String exchangeRates = '/api/v1/exrates/';
  static const String dailyPrice = '/api/v1/daily-price/';
  static const String lastDayPrices = '/api/v1/prices/last-day/';

  // Health
  static const String health = '/api/v1/health/';
}
