/// Storage key constants for SharedPreferences and SecureStorage
class StorageKeys {
  StorageKeys._();

  // Auth
  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String userId = 'user_id';

  // Preferences
  static const String theme = 'theme';
  static const String languageCode = 'language_code';
  static const String isOnboardingComplete = 'is_onboarding_complete';
  static const String isBalanceHidden = 'balance_hidden';

  // Settings
  static const String selectedCurrency = 'selected_currency';
  static const String enabledCurrencies = 'enabled_currencies';
  static const String blockExplorer = 'block_explorer';
  static const String electrumServer = 'electrum_server';

  // Feature Flags
  static const String featureFlags = 'feature_flags';

  // Wallet storage keys
  static const String activeWalletId = 'active_wallet_id';
  static const String walletSeedPrefix = 'wallet_seed_';
  
  // Helper method to generate seed storage key
  static String walletSeedKey(String walletId) => '$walletSeedPrefix$walletId';
}
