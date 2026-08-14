import 'package:flutter/foundation.dart';

import 'wallet_asset.dart';

/// Integer unit carried by a [WalletAmount].
enum WalletAmountUnit {
  /// Bitcoin's on-chain smallest unit.
  satoshi,

  /// Bitcoin Lightning's smallest accounting unit.
  millisatoshi,

  /// An RGB asset's contract-defined smallest unit.
  assetAtomic,
}

/// Non-negative monetary amount with explicit asset, rail, and unit identity.
///
/// Bitcoin Lightning values remain in millisatoshis. Callers must opt into
/// [wholeAssetUnits] when a display intentionally rounds down to sats.
@immutable
final class WalletAmount {
  WalletAmount._({
    required this.assetId,
    required this.rail,
    required this.unit,
    required this.units,
  }) {
    if (units < 0 || units > maxNativeUnits) {
      throw ArgumentError.value(
        units,
        'units',
        'Must fit a non-negative signed 64-bit native amount.',
      );
    }
  }

  /// Largest amount that can cross the SDK's signed 64-bit native boundary.
  static const int maxNativeUnits = 0x7fffffffffffffff;

  /// Number of Lightning millisatoshis in one Bitcoin satoshi.
  static const int millisatoshisPerSatoshi = 1000;

  factory WalletAmount.onchain({
    required WalletAssetId assetId,
    required int units,
  }) {
    return WalletAmount._(
      assetId: assetId,
      rail: PaymentRail.onchain,
      unit: assetId.protocol == WalletAssetProtocol.bitcoin
          ? WalletAmountUnit.satoshi
          : WalletAmountUnit.assetAtomic,
      units: units,
    );
  }

  factory WalletAmount.lightning({
    required WalletAssetId assetId,
    required int units,
  }) {
    return WalletAmount._(
      assetId: assetId,
      rail: PaymentRail.lightning,
      unit: assetId.protocol == WalletAssetProtocol.bitcoin
          ? WalletAmountUnit.millisatoshi
          : WalletAmountUnit.assetAtomic,
      units: units,
    );
  }

  final WalletAssetId assetId;
  final PaymentRail rail;
  final WalletAmountUnit unit;
  final int units;

  bool get isZero => units == 0;

  /// Whole asset-smallest units, rounding down only for millisatoshis.
  int get wholeAssetUnits => switch (unit) {
    WalletAmountUnit.millisatoshi => units ~/ millisatoshisPerSatoshi,
    WalletAmountUnit.satoshi || WalletAmountUnit.assetAtomic => units,
  };

  /// Sub-satoshi remainder for Bitcoin Lightning, otherwise zero.
  int get subSatoshiRemainder => switch (unit) {
    WalletAmountUnit.millisatoshi => units % millisatoshisPerSatoshi,
    WalletAmountUnit.satoshi || WalletAmountUnit.assetAtomic => 0,
  };

  @override
  bool operator ==(Object other) =>
      other is WalletAmount &&
      other.assetId == assetId &&
      other.rail == rail &&
      other.unit == unit &&
      other.units == units;

  @override
  int get hashCode => Object.hash(assetId, rail, unit, units);
}
