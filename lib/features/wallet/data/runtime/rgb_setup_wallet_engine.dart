import '../../domain/models/models.dart';

/// Optional native capability; no SDK DTO crosses the application boundary.
abstract interface class RgbSetupWalletEngine {
  Future<RgbWalletSetupInventory> rgbSetupInventory();
  Future<List<RgbWalletSetupTransaction>> rgbSetupTransactions();
  Future<void> createRgbSetupOutputs(int feeRateSatPerVbyte);
}
