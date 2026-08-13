import 'package:flutter/foundation.dart';

import 'app_preferences.dart';
import 'fiat_currency.dart';
import 'region.dart';

/// Atomic settings read model containing preferences and validated catalogs.
@immutable
final class SettingsSnapshot {
  SettingsSnapshot({
    required this.preferences,
    required List<FiatCurrency> currencies,
    required List<Region> regions,
  }) : currencies = List<FiatCurrency>.unmodifiable(currencies),
       regions = List<Region>.unmodifiable(regions) {
    _validateCatalog(
      values: this.currencies,
      selectedCode: preferences.currencyCode,
      codeOf: (currency) => currency.code,
      catalogName: 'currency',
    );
    _validateCatalog(
      values: this.regions,
      selectedCode: preferences.regionCode,
      codeOf: (region) => region.code,
      catalogName: 'region',
    );
  }

  final AppPreferences preferences;
  final List<FiatCurrency> currencies;
  final List<Region> regions;

  FiatCurrency get selectedCurrency =>
      currencies.singleWhere((item) => item.code == preferences.currencyCode);

  Region get selectedRegion =>
      regions.singleWhere((item) => item.code == preferences.regionCode);

  SettingsSnapshot copyWith({AppPreferences? preferences}) {
    return SettingsSnapshot(
      preferences: preferences ?? this.preferences,
      currencies: currencies,
      regions: regions,
    );
  }

  static void _validateCatalog<T>({
    required List<T> values,
    required String selectedCode,
    required String Function(T value) codeOf,
    required String catalogName,
  }) {
    if (values.isEmpty) {
      throw ArgumentError('$catalogName catalog must not be empty.');
    }
    final codes = values.map(codeOf).toList(growable: false);
    if (codes.toSet().length != codes.length) {
      throw ArgumentError('$catalogName catalog contains duplicate codes.');
    }
    if (!codes.contains(selectedCode)) {
      throw ArgumentError(
        'Selected $catalogName is not present in its catalog.',
      );
    }
  }
}
