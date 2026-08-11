import 'package:flutter/foundation.dart';

/// Payment rail used to move an asset.
enum PaymentRail { onchain, lightning }

/// Product asset identity independent from its protocol contract identifier.
enum WalletAssetKind { bitcoin, usdt }

/// Asset protocol independent from its payment rail.
enum WalletAssetProtocol { bitcoin, rgb }

/// Stable asset identity. RGB assets are identified by contract ID, never by
/// ticker text.
@immutable
final class WalletAssetId {
  const WalletAssetId._(this.protocol, this.value);

  const WalletAssetId.bitcoin()
    : this._(WalletAssetProtocol.bitcoin, 'bitcoin');

  factory WalletAssetId.rgb(String contractId) {
    final normalized = contractId.trim();
    if (normalized.isEmpty ||
        normalized.length > 512 ||
        normalized.contains(RegExp(r'\s'))) {
      throw ArgumentError.value(
        contractId,
        'contractId',
        'Must be a non-empty contract ID without whitespace.',
      );
    }
    return WalletAssetId._(WalletAssetProtocol.rgb, normalized);
  }

  final WalletAssetProtocol protocol;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is WalletAssetId &&
      other.protocol == protocol &&
      other.value == value;

  @override
  int get hashCode => Object.hash(protocol, value);

  @override
  String toString() => 'WalletAssetId(${protocol.name})';
}

/// App-owned asset metadata used by presentation and formatting.
@immutable
final class WalletAsset {
  const WalletAsset._({
    required this.kind,
    required this.id,
    required this.displayName,
    required this.symbol,
    required this.precision,
  });

  static const bitcoin = WalletAsset._(
    kind: WalletAssetKind.bitcoin,
    id: WalletAssetId.bitcoin(),
    displayName: 'Bitcoin',
    symbol: 'BTC',
    precision: 8,
  );

  factory WalletAsset.rgbUsdt({
    required String assetId,
    required int precision,
  }) {
    if (precision < 0 || precision > 18) {
      throw ArgumentError.value(
        precision,
        'precision',
        'Must be between 0 and 18.',
      );
    }
    return WalletAsset._(
      kind: WalletAssetKind.usdt,
      id: WalletAssetId.rgb(assetId),
      displayName: 'Tether USD',
      symbol: 'USDT',
      precision: precision,
    );
  }

  final WalletAssetKind kind;
  final WalletAssetId id;
  final String displayName;
  final String symbol;

  /// Decimal precision used only for formatting integer smallest units.
  final int precision;

  @override
  bool operator ==(Object other) =>
      other is WalletAsset &&
      other.kind == kind &&
      other.id == id &&
      other.displayName == displayName &&
      other.symbol == symbol &&
      other.precision == precision;

  @override
  int get hashCode => Object.hash(kind, id, displayName, symbol, precision);
}

/// Stable route identifier used in URLs, persisted UI state, and analytics.
///
/// This identifies a product choice without pretending that deployment-owned
/// RGB metadata is configured. Resolve it to a [PaymentRoute] before executing
/// a wallet operation.
enum WalletPaymentTarget {
  bitcoinOnchain(
    slug: 'bitcoin-onchain',
    assetKind: WalletAssetKind.bitcoin,
    rail: PaymentRail.onchain,
  ),
  bitcoinLightning(
    slug: 'bitcoin-lightning',
    assetKind: WalletAssetKind.bitcoin,
    rail: PaymentRail.lightning,
  ),
  usdtOnchain(
    slug: 'usdt-onchain',
    assetKind: WalletAssetKind.usdt,
    rail: PaymentRail.onchain,
  ),
  usdtLightning(
    slug: 'usdt-lightning',
    assetKind: WalletAssetKind.usdt,
    rail: PaymentRail.lightning,
  );

  const WalletPaymentTarget({
    required this.slug,
    required this.assetKind,
    required this.rail,
  });

  final String slug;
  final WalletAssetKind assetKind;
  final PaymentRail rail;

  static WalletPaymentTarget? tryParse(String? value) {
    if (value == null) return null;
    for (final target in values) {
      if (target.slug == value) return target;
    }
    return null;
  }
}

/// A supported asset and rail combination.
@immutable
final class PaymentRoute {
  const PaymentRoute({required this.asset, required this.rail});

  final WalletAsset asset;
  final PaymentRail rail;

  WalletPaymentTarget get target => switch ((asset.kind, rail)) {
    (WalletAssetKind.bitcoin, PaymentRail.onchain) =>
      WalletPaymentTarget.bitcoinOnchain,
    (WalletAssetKind.bitcoin, PaymentRail.lightning) =>
      WalletPaymentTarget.bitcoinLightning,
    (WalletAssetKind.usdt, PaymentRail.onchain) =>
      WalletPaymentTarget.usdtOnchain,
    (WalletAssetKind.usdt, PaymentRail.lightning) =>
      WalletPaymentTarget.usdtLightning,
  };

  @override
  bool operator ==(Object other) =>
      other is PaymentRoute && other.asset.id == asset.id && other.rail == rail;

  @override
  int get hashCode => Object.hash(asset.id, rail);
}

/// Availability of one product payment target in the active deployment.
@immutable
final class WalletPaymentCapability {
  const WalletPaymentCapability._({required this.target, this.route});

  factory WalletPaymentCapability.available(PaymentRoute route) {
    return WalletPaymentCapability._(target: route.target, route: route);
  }

  const WalletPaymentCapability.unavailable(WalletPaymentTarget target)
    : this._(target: target);

  final WalletPaymentTarget target;
  final PaymentRoute? route;

  bool get isAvailable => route != null;
}
