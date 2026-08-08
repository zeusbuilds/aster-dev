import 'package:flutter/foundation.dart';

import 'wallet_amount.dart';
import 'wallet_asset.dart';

/// Balance dimensions for one asset across on-chain and Lightning rails.
@immutable
final class WalletBalance {
  WalletBalance({
    required this.asset,
    required this.onchainSettled,
    required this.onchainFuture,
    required this.onchainSpendable,
    required this.onchainLocked,
    required this.lightningOwned,
    required this.lightningSpendable,
    required this.lightningReceivable,
  }) {
    final amounts = <WalletAmount>[
      onchainSettled,
      onchainFuture,
      onchainSpendable,
      onchainLocked,
      lightningOwned,
      lightningSpendable,
      lightningReceivable,
    ];
    if (amounts.any((amount) => amount.assetId != asset.id)) {
      throw const FormatException('Balance contains a different asset ID.');
    }
    if ([
      onchainSettled,
      onchainFuture,
      onchainSpendable,
      onchainLocked,
    ].any((amount) => amount.rail != PaymentRail.onchain)) {
      throw const FormatException('On-chain balance has the wrong rail.');
    }
    if ([
      lightningOwned,
      lightningSpendable,
      lightningReceivable,
    ].any((amount) => amount.rail != PaymentRail.lightning)) {
      throw const FormatException('Lightning balance has the wrong rail.');
    }
    if (BigInt.from(onchainSpendable.units) +
            BigInt.from(onchainLocked.units) !=
        BigInt.from(onchainSettled.units)) {
      throw const FormatException('On-chain balance invariants are invalid.');
    }
    if (lightningSpendable.units > lightningOwned.units) {
      throw const FormatException('Lightning balance invariants are invalid.');
    }
    _requireFitsNative(
      BigInt.from(onchainSettled.units) +
          BigInt.from(lightningOwned.wholeAssetUnits),
    );
    _requireFitsNative(
      BigInt.from(onchainSpendable.units) +
          BigInt.from(lightningSpendable.wholeAssetUnits),
    );
    if (asset.id.protocol == WalletAssetProtocol.bitcoin) {
      _requireFitsNative(
        BigInt.from(onchainSettled.units) * BigInt.from(1000) +
            BigInt.from(lightningOwned.units),
      );
      _requireFitsNative(
        BigInt.from(onchainSpendable.units) * BigInt.from(1000) +
            BigInt.from(lightningSpendable.units),
      );
    }
  }

  final WalletAsset asset;
  final WalletAmount onchainSettled;

  /// Projected balance after pending incoming and outgoing transfers settle.
  final WalletAmount onchainFuture;
  final WalletAmount onchainSpendable;

  /// Settled value that is not currently spendable, such as Bitcoin held in
  /// colored UTXOs or funds reserved by an in-flight operation.
  final WalletAmount onchainLocked;

  /// Locally owned value committed to Lightning channels.
  final WalletAmount lightningOwned;

  /// Amount currently spendable over usable Lightning channels.
  final WalletAmount lightningSpendable;

  /// Amount currently receivable over Lightning.
  final WalletAmount lightningReceivable;

  /// Signed change from settled to future on-chain balance.
  int get onchainPendingDeltaUnits =>
      onchainFuture.units - onchainSettled.units;

  /// Settled on-chain holdings plus whole Lightning asset units.
  ///
  /// For Bitcoin display this rounds sub-satoshi Lightning value down. Use
  /// [totalBitcoinMillisatoshis] when exact cross-rail accounting is required.
  int get totalAssetUnits =>
      onchainSettled.units + lightningOwned.wholeAssetUnits;

  /// Immediately spendable on-chain funds plus outbound channel liquidity.
  int get availableAssetUnits =>
      onchainSpendable.units + lightningSpendable.wholeAssetUnits;

  /// Exact Bitcoin total in millisatoshis, or `null` for RGB assets.
  int? get totalBitcoinMillisatoshis =>
      asset.id.protocol == WalletAssetProtocol.bitcoin
      ? onchainSettled.units * 1000 + lightningOwned.units
      : null;

  /// Exact spendable Bitcoin amount in millisatoshis, or `null` for RGB.
  int? get availableBitcoinMillisatoshis =>
      asset.id.protocol == WalletAssetProtocol.bitcoin
      ? onchainSpendable.units * 1000 + lightningSpendable.units
      : null;

  static void _requireFitsNative(BigInt value) {
    if (value > BigInt.from(WalletAmount.maxNativeUnits)) {
      throw const FormatException('Aggregate balance exceeds native bounds.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is WalletBalance &&
      other.asset == asset &&
      other.onchainSettled == onchainSettled &&
      other.onchainFuture == onchainFuture &&
      other.onchainSpendable == onchainSpendable &&
      other.onchainLocked == onchainLocked &&
      other.lightningOwned == lightningOwned &&
      other.lightningSpendable == lightningSpendable &&
      other.lightningReceivable == lightningReceivable;

  @override
  int get hashCode => Object.hash(
    asset,
    onchainSettled,
    onchainFuture,
    onchainSpendable,
    onchainLocked,
    lightningOwned,
    lightningSpendable,
    lightningReceivable,
  );
}
