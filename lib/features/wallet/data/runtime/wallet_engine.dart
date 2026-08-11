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
  Future<void> initialize({required String databasePassword, String? mnemonic});

  Future<void> reinitialize({required String databasePassword});
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

abstract interface class WalletEngineFactory {
  WalletEngine create(WalletEngineConfiguration configuration);
}

/// SDK-backed BIP39 generation and validation boundary.
abstract interface class WalletKeyGenerator {
  Future<String> generateMnemonic(BlockchainEnvironment environment);
  Future<void> validateMnemonic(String mnemonic);
}
