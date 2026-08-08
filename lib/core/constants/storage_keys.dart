/// Storage key constants for SharedPreferences and SecureStorage
class StorageKeys {
  StorageKeys._();

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
  /// Unreleased pre-ownership registry retained only for recovery detection.
  static const String legacyWalletRegistryV2 = 'utexo_wallet_registry_v2';

  /// Metadata-only registry used before native wallet ownership existed.
  ///
  /// It is detected but never deleted or promoted because it has no matching
  /// native credential contract and therefore cannot be migrated safely.
  static const String legacyWalletRegistryV1 = 'wallet_registry_v1';

  /// Prefix for one ownership-bound encrypted credential record per wallet.
  static const String walletSecretPrefix = 'utexo_wallet_secret_v2.';

  /// Unowned credential prefix retained only for recovery detection.
  static const String legacyWalletSecretPrefix = 'utexo_wallet_secret_v1.';
}
