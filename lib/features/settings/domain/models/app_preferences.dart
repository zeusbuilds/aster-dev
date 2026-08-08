import 'package:flutter/foundation.dart';

import '../../../../shared/formatting/bitcoin_unit.dart';

/// Durable, non-secret user display preferences.
@immutable
final class AppPreferences {
  const AppPreferences({
    required this.currencyCode,
    required this.regionCode,
    required this.bitcoinUnit,
    required this.balancesVisible,
  });

  static const defaults = AppPreferences(
    currencyCode: 'USD',
    regionCode: 'US',
    bitcoinUnit: BitcoinUnit.bitcoin,
    balancesVisible: true,
  );

  final String currencyCode;
  final String regionCode;
  final BitcoinUnit bitcoinUnit;
  final bool balancesVisible;

  AppPreferences copyWith({
    String? currencyCode,
    String? regionCode,
    BitcoinUnit? bitcoinUnit,
    bool? balancesVisible,
  }) {
    return AppPreferences(
      currencyCode: currencyCode ?? this.currencyCode,
      regionCode: regionCode ?? this.regionCode,
      bitcoinUnit: bitcoinUnit ?? this.bitcoinUnit,
      balancesVisible: balancesVisible ?? this.balancesVisible,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppPreferences &&
      other.currencyCode == currencyCode &&
      other.regionCode == regionCode &&
      other.bitcoinUnit == bitcoinUnit &&
      other.balancesVisible == balancesVisible;

  @override
  int get hashCode =>
      Object.hash(currencyCode, regionCode, bitcoinUnit, balancesVisible);
}
