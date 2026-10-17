import '../../domain/models/models.dart';

/// Product copy and visual assets for typed wallet asset identities.
extension WalletAssetKindDisplay on WalletAssetKind {
  String get displayName => switch (this) {
    WalletAssetKind.bitcoin => 'Bitcoin',
    WalletAssetKind.usdt => 'USDT',
  };

  String get iconAsset => switch (this) {
    WalletAssetKind.bitcoin => 'assets/icons/tokens/btc.svg',
    WalletAssetKind.usdt => 'assets/icons/tokens/usdt.svg',
  };
}

/// Product copy and visual identity for stable payment targets.
extension WalletPaymentTargetDisplay on WalletPaymentTarget {
  String get assetLabel => assetKind.displayName;

  String get sendTitle => 'Send $assetLabel';

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
}
