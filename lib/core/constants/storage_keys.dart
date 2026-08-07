/// Storage key constants for SharedPreferences and SecureStorage
class StorageKeys {
  StorageKeys._();

  // Auth
  /// Key for storing access token in secure storage
  static const String accessToken = 'access_token';

  /// Key for storing refresh token in secure storage
  static const String refreshToken = 'refresh_token';

  /// Key for storing user ID in preferences
  static const String userId = 'user_id';

  // Preferences
  /// Key for storing theme preference
  static const String theme = 'theme';

  /// Key for storing language code preference
  static const String languageCode = 'language_code';

  /// Key for storing onboarding completion status
  static const String isOnboardingComplete = 'is_onboarding_complete';

  /// Key for storing balance visibility preference
  static const String isBalanceHidden = 'balance_hidden';

  // Settings
  /// Key for storing selected currency
  static const String selectedCurrency = 'selected_currency';

  /// Key for storing enabled currencies list
  static const String enabledCurrencies = 'enabled_currencies';

  /// Key for storing block explorer preference
  static const String blockExplorer = 'block_explorer';

  /// Key for storing electrum server preference
  static const String electrumServer = 'electrum_server';

  // Feature Flags
  /// Key for storing feature flags
  static const String featureFlags = 'feature_flags';

  // Wallet storage keys
  /// Key for storing active wallet ID
  static const String activeWalletId = 'active_wallet_id';

  /// Versioned, non-secret wallet profile registry.
  static const String walletRegistry = 'wallet_registry_v1';
}
