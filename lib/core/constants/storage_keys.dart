/// Versioned keys retained for wallet ownership and recovery detection.
abstract final class StorageKeys {
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
