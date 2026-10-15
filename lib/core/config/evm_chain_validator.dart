import 'app_environment.dart';

/// Checks the deployment-approved BFA backing chain before native unlock.
abstract interface class EvmChainValidator {
  Future<void> verify(WalletServiceConfiguration services);
}
