import 'package:flutter/foundation.dart';

import '../../../../shared/formatting/bitcoin_unit.dart';
import '../../../market/domain/models/models.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/formatting/formatting.dart';
import '../../../wallet/presentation/models/models.dart';

/// Exact text values rendered by one Home asset row.
@immutable
final class HomeAssetDisplay {
  const HomeAssetDisplay({
    required this.kind,
    required this.title,
    required this.total,
    required this.available,
    required this.fiatContext,
  });

  final WalletAssetKind kind;
  final String title;
  final FormattedWalletAmount total;
  final FormattedWalletAmount available;
  final String fiatContext;
}

/// Formats cross-rail portfolio totals without floating-point money math.
final class HomeAssetDisplayFormatter {
  HomeAssetDisplayFormatter({WalletAmountDisplayFormatter? amountFormatter})
    : _amountFormatter = amountFormatter ?? WalletAmountDisplayFormatter();

  final WalletAmountDisplayFormatter _amountFormatter;

  HomeAssetDisplay format({
    required WalletBalance balance,
    required BitcoinUnit bitcoinUnit,
    required String currencyCode,
    required DateTime now,
    BitcoinMarketSnapshot? bitcoinMarket,
  }) {
    final isBitcoin = balance.asset.kind == WalletAssetKind.bitcoin;
    final route = PaymentRoute(
      asset: balance.asset,
      rail: isBitcoin ? PaymentRail.lightning : PaymentRail.onchain,
    );
    final totalUnits = isBitcoin
        ? balance.totalBitcoinMillisatoshis!
        : balance.totalAssetUnits;
    final availableUnits = isBitcoin
        ? balance.availableBitcoinMillisatoshis!
        : balance.availableAssetUnits;
    return HomeAssetDisplay(
      kind: balance.asset.kind,
      title: balance.asset.kind.displayName,
      total: _amountFormatter.format(
        units: totalUnits,
        route: route,
        bitcoinUnit: bitcoinUnit,
      ),
      available: _amountFormatter.format(
        units: availableUnits,
        route: route,
        bitcoinUnit: bitcoinUnit,
      ),
      fiatContext: _fiatContext(
        route: route,
        totalUnits: totalUnits,
        currencyCode: currencyCode,
        now: now,
        market: bitcoinMarket,
      ),
    );
  }

  static String _fiatContext({
    required PaymentRoute route,
    required int totalUnits,
    required String currencyCode,
    required DateTime now,
    required BitcoinMarketSnapshot? market,
  }) {
    if (market == null || market.quoteCurrency.code != currencyCode) {
      return '$currencyCode estimate unavailable';
    }
    final price = switch (route.asset.kind) {
      WalletAssetKind.bitcoin => market.currentBitcoinPrice,
      WalletAssetKind.usdt => market.currentUsdtPrice,
    };
    if (!(price?.isCurrentAt(now) ?? false)) {
      return '$currencyCode estimate unavailable';
    }
    final minorUnits = WalletFiatEstimate.minorUnits(
      units: totalUnits,
      route: route,
      assetPriceMinorUnits: price?.minorUnits,
    );
    if (minorUnits == null) return '$currencyCode estimate unavailable';
    final formatted = WalletFiatEstimate.formatMinorUnits(
      minorUnits: minorUnits,
      symbol: market.quoteCurrency.symbol,
      code: market.quoteCurrency.code,
      minorUnitDigits: market.quoteCurrency.minorUnitDigits,
    );
    return '$formatted estimated';
  }
}
