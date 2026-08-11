import '../../../../shared/models/models.dart';
import '../../domain/models/models.dart';

/// Product copy and visual identity for stable payment targets.
extension WalletPaymentTargetDisplay on WalletPaymentTarget {
  String get assetLabel => switch (assetKind) {
    WalletAssetKind.bitcoin => 'Bitcoin',
    WalletAssetKind.usdt => 'USDT',
  };

  String get railLabel => switch ((assetKind, rail)) {
    (WalletAssetKind.bitcoin, PaymentRail.onchain) => 'On-chain',
    (WalletAssetKind.bitcoin, PaymentRail.lightning) => 'Lightning',
    (WalletAssetKind.usdt, PaymentRail.onchain) => 'RGB on-chain',
    (WalletAssetKind.usdt, PaymentRail.lightning) => 'RGB Lightning',
  };

  String get destinationLabel => switch (rail) {
    PaymentRail.onchain => 'Recipient address',
    PaymentRail.lightning => 'Lightning invoice',
  };

  String get destinationHint => switch (rail) {
    PaymentRail.onchain => 'Enter a Bitcoin or RGB payment address',
    PaymentRail.lightning => 'Enter a Lightning invoice',
  };

  String get requestLabel => switch (rail) {
    PaymentRail.onchain => 'Payment address',
    PaymentRail.lightning => 'Lightning invoice',
  };

  String get semanticLabel => '$assetLabel, $railLabel';

  AssetModel get assetModel => switch (assetKind) {
    WalletAssetKind.bitcoin => AssetModel.bitcoin,
    WalletAssetKind.usdt => AssetModel.usdt,
  };
}
