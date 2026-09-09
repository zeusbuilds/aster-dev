import 'package:flutter/foundation.dart';

import '../../../../shared/formatting/bitcoin_unit.dart';
import '../../../../shared/formatting/fiat_amount_formatter.dart';
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
    this.fiatLabel,
  });

  final WalletAssetKind kind;
  final String title;
  final FormattedWalletAmount total;
  final FormattedWalletAmount available;
  final String fiatContext;

  /// Compact estimate for the two-line portfolio row. Accessibility retains
  /// the currency code and explicit estimate wording in [fiatContext].
  final String? fiatLabel;
}

/// Formats cross-rail portfolio totals without floating-point money math.
final class HomeAssetDisplayFormatter {
  HomeAssetDisplayFormatter({WalletAmountDisplayFormatter? amountFormatter})
    : _amountFormatter = amountFormatter ?? WalletAmountDisplayFormatter();

  final WalletAmountDisplayFormatter _amountFormatter;
  static final _fiatFormatter = FiatAmountFormatter();

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
    final fiat = _fiatContext(
      route: route,
      totalUnits: totalUnits,
      currencyCode: currencyCode,
      now: now,
      market: bitcoinMarket,
    );
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
      fiatContext: fiat.semantics,
      fiatLabel: fiat.label,
    );
  }

  static ({String label, String semantics}) _fiatContext({
    required PaymentRoute route,
    required int totalUnits,
    required String currencyCode,
    required DateTime now,
    required BitcoinMarketSnapshot? market,
  }) {
    final unavailable = (
      label: '$currencyCode estimate unavailable',
      semantics: '$currencyCode estimate unavailable',
    );
    if (market == null || market.quoteCurrency.code != currencyCode) {
      return unavailable;
    }
    final price = switch (route.asset.kind) {
      WalletAssetKind.bitcoin => market.currentBitcoinPrice,
      WalletAssetKind.usdt => market.currentUsdtPrice,
    };
    if (!(price?.isCurrentAt(now) ?? false)) {
      return unavailable;
    }
    final minorUnits = WalletFiatEstimate.minorUnits(
      units: totalUnits,
      route: route,
      assetPriceMinorUnits: price?.minorUnits,
    );
    if (minorUnits == null) return unavailable;
    final formatted = WalletFiatEstimate.formatMinorUnits(
      minorUnits: minorUnits,
      symbol: market.quoteCurrency.symbol,
      code: market.quoteCurrency.code,
      minorUnitDigits: market.quoteCurrency.minorUnitDigits,
    );
    final compact = _fiatFormatter.format(
      minorUnits: minorUnits,
      symbol: market.quoteCurrency.symbol,
      code: market.quoteCurrency.code,
      minorUnitDigits: market.quoteCurrency.minorUnitDigits,
      includeCurrencyCode: false,
    );
    return (label: '≈ $compact', semantics: '$formatted estimated');
  }
}
