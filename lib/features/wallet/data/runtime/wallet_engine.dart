import '../../../../core/config/app_environment.dart';
import '../../domain/models/models.dart';

/// Native-wallet configuration owned by the app adapter boundary.
final class WalletEngineConfiguration {
  const WalletEngineConfiguration({
    required this.storageDirectory,
    required this.services,
  });

  final String storageDirectory;
  final WalletServiceConfiguration services;
}

/// Testable native wallet boundary. No SDK DTO crosses this interface.
abstract interface class WalletEngine {
  /// Initializes a newly provisioned native wallet store and unlocks it.
  ///
  /// This operation is valid exactly once for a new store. Persisted stores
  /// must be opened with [openPersisted] instead.
  Future<void> provision({
    required String databasePassword,
    required String mnemonic,
  });

  /// Recreates and unlocks the native node for an existing wallet store.
  Future<void> openPersisted({required String databasePassword});
  Future<void> sync();
  Future<void> shutdown();
  Future<void> destroy();
  Future<WalletBalance> getBalance(WalletAsset asset);
  Future<List<WalletActivity>> listActivity(WalletAsset asset);
  Future<WalletFeeRateEstimate> estimateFeeRate(int targetBlocks);
  Future<String> getBitcoinAddress();
  Future<WalletPaymentPreview> decodeInvoice(
    PaymentRoute route,
    String invoice,
  );
  Future<WalletReceiveRequest> createReceiveRequest(
    PaymentRoute route, {
    WalletAmount? amount,
  });
  Future<WalletSendResult> sendPayment(WalletSendCommand command);
  Future<WalletNetworkStatus> getNetworkStatus();
  Future<WalletPublicKeys> getPublicKeys();
}

/// Optional engine boundary for a native format that requires its signing
/// material on every reopen. Runtime reads it from the wallet-owned secure
/// record and supplies it only for this activation; engines must not retain it.
abstract interface class WalletMnemonicOpenEngine {
  Future<void> openPersistedWithMnemonic({
    required String databasePassword,
    required String mnemonic,
  });
}

abstract interface class WalletEngineFactory {
  WalletEngine create(WalletEngineConfiguration configuration);
}

/// SDK-backed BIP39 generation and validation boundary.
abstract interface class WalletKeyGenerator {
  Future<String> generateMnemonic(BlockchainEnvironment environment);
  Future<void> validateMnemonic(String mnemonic);
}
