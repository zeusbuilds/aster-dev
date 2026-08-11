import 'package:flutter/foundation.dart';

import 'wallet_asset.dart';
import 'wallet_balance.dart';

/// Cross-rail balances for the product assets configured in this deployment.
@immutable
final class WalletPortfolio {
  WalletPortfolio({required this.bitcoin, this.usdt}) {
    if (bitcoin.asset.kind != WalletAssetKind.bitcoin) {
      throw ArgumentError.value(bitcoin, 'bitcoin');
    }
    final configuredUsdt = usdt;
    if (configuredUsdt != null &&
        configuredUsdt.asset.kind != WalletAssetKind.usdt) {
      throw ArgumentError.value(configuredUsdt, 'usdt');
    }
  }

  final WalletBalance bitcoin;

  /// `null` only when RGB USDT is not configured for this environment.
  final WalletBalance? usdt;

  Iterable<WalletBalance> get balances sync* {
    yield bitcoin;
    final configuredUsdt = usdt;
    if (configuredUsdt != null) yield configuredUsdt;
  }

  WalletBalance? balanceFor(WalletAssetKind kind) => switch (kind) {
    WalletAssetKind.bitcoin => bitcoin,
    WalletAssetKind.usdt => usdt,
  };

  @override
  bool operator ==(Object other) =>
      other is WalletPortfolio &&
      other.bitcoin == bitcoin &&
      other.usdt == usdt;

  @override
  int get hashCode => Object.hash(bitcoin, usdt);
}
