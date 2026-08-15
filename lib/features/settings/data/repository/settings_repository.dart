import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../../core/errors/errors.dart';
import '../../../../core/storage/preferences_service.dart';
import '../../../../shared/formatting/bitcoin_unit.dart';
import '../../../../shared/formatting/fiat_currency_policy.dart';
import '../../domain/models/models.dart';

/// Owns validated settings catalogs and serialized non-secret preferences.
final class SettingsRepository {
  SettingsRepository(this._preferences, this._assets);

  static const _currencyKey = 'utexo.settings.v1.currency';
  static const _regionKey = 'utexo.settings.v1.region';
  static const _bitcoinUnitKey = 'utexo.settings.v1.bitcoin_unit';
  static const _balancesVisibleKey = 'utexo.settings.v1.balances_visible';

  final PreferencesService _preferences;
  final AssetBundle _assets;

  Future<void> _operationTail = Future<void>.value();
  Future<_SettingsCatalog>? _catalogFuture;
  SettingsSnapshot? _snapshot;

  /// Loads validated catalogs and self-heals unsupported preference values to
  /// documented defaults. Failures are typed and contain no asset payloads.
  Future<AppResult<SettingsSnapshot>> load() => _enqueue(_loadUnsafe);

  /// Persists a selected ISO 4217 [code] after catalog validation.
  Future<AppResult<SettingsSnapshot>> selectCurrency(String code) {
    return _enqueue(() async {
      final current = await _requireSnapshot();
      if (current case AppFailureResult<SettingsSnapshot>()) return current;
      final snapshot = (current as AppSuccess<SettingsSnapshot>).value;
      if (!snapshot.currencies.any((item) => item.code == code)) {
        return const AppResult.failure(
          AppFailure(
            code: 'settings_currency_invalid',
            kind: AppFailureKind.validation,
            userMessage: 'That currency is not available.',
            retryable: false,
          ),
        );
      }
      return _persist(
        snapshot.copyWith(
          preferences: snapshot.preferences.copyWith(currencyCode: code),
        ),
        () => _preferences.setString(_currencyKey, code),
      );
    });
  }

  /// Persists a selected ISO 3166-1 alpha-2 region [code].
  Future<AppResult<SettingsSnapshot>> selectRegion(String code) {
    return _enqueue(() async {
      final current = await _requireSnapshot();
      if (current case AppFailureResult<SettingsSnapshot>()) return current;
      final snapshot = (current as AppSuccess<SettingsSnapshot>).value;
      if (!snapshot.regions.any((item) => item.code == code)) {
        return const AppResult.failure(
          AppFailure(
            code: 'settings_region_invalid',
            kind: AppFailureKind.validation,
            userMessage: 'That region is not available.',
            retryable: false,
          ),
        );
      }
      return _persist(
        snapshot.copyWith(
          preferences: snapshot.preferences.copyWith(regionCode: code),
        ),
        () => _preferences.setString(_regionKey, code),
      );
    });
  }

  /// Persists the app-wide Bitcoin display [unit].
  Future<AppResult<SettingsSnapshot>> selectBitcoinUnit(BitcoinUnit unit) {
    return _enqueue(() async {
      final current = await _requireSnapshot();
      if (current case AppFailureResult<SettingsSnapshot>()) return current;
      final snapshot = (current as AppSuccess<SettingsSnapshot>).value;
      return _persist(
        snapshot.copyWith(
          preferences: snapshot.preferences.copyWith(bitcoinUnit: unit),
        ),
        () => _preferences.setString(_bitcoinUnitKey, unit.storageValue),
      );
    });
  }

  /// Persists whether all balance values may be rendered and announced.
  Future<AppResult<SettingsSnapshot>> setBalancesVisible(bool visible) {
    return _enqueue(() async {
      final current = await _requireSnapshot();
      if (current case AppFailureResult<SettingsSnapshot>()) return current;
      final snapshot = (current as AppSuccess<SettingsSnapshot>).value;
      return _persist(
        snapshot.copyWith(
          preferences: snapshot.preferences.copyWith(balancesVisible: visible),
        ),
        () => _preferences.setBool(_balancesVisibleKey, visible),
      );
    });
  }

  Future<AppResult<SettingsSnapshot>> _loadUnsafe() async {
    try {
      final catalog = await _loadCatalog();
      final storedCurrency = await _preferences.getString(_currencyKey);
      final storedRegion = await _preferences.getString(_regionKey);
      final storedUnit = await _preferences.getString(_bitcoinUnitKey);
      final storedVisibility = await _preferences.getBool(_balancesVisibleKey);

      final currency =
          catalog.currencies.any((item) => item.code == storedCurrency)
          ? storedCurrency!
          : AppPreferences.defaults.currencyCode;
      final region = catalog.regions.any((item) => item.code == storedRegion)
          ? storedRegion!
          : AppPreferences.defaults.regionCode;
      final unit = _parseUnit(storedUnit);
      final preferences = AppPreferences(
        currencyCode: currency,
        regionCode: region,
        bitcoinUnit: unit,
        balancesVisible:
            storedVisibility ?? AppPreferences.defaults.balancesVisible,
      );

      await _repairIfNeeded(
        storedCurrency: storedCurrency,
        storedRegion: storedRegion,
        storedUnit: storedUnit,
        storedVisibility: storedVisibility,
        resolved: preferences,
      );
      final snapshot = SettingsSnapshot(
        preferences: preferences,
        currencies: catalog.currencies,
        regions: catalog.regions,
      );
      _snapshot = snapshot;
      return AppResult.success(snapshot);
    } catch (error, stackTrace) {
      return AppResult.failure(
        FailureMapper.from(
          error,
          stackTrace,
          fallbackCode: 'settings_load_failed',
        ),
      );
    }
  }

  Future<AppResult<SettingsSnapshot>> _requireSnapshot() async {
    final current = _snapshot;
    if (current != null) return AppResult.success(current);
    return _loadUnsafe();
  }

  Future<AppResult<SettingsSnapshot>> _persist(
    SettingsSnapshot next,
    Future<void> Function() write,
  ) async {
    try {
      await write();
      _snapshot = next;
      return AppResult.success(next);
    } catch (error, stackTrace) {
      return AppResult.failure(
        FailureMapper.from(
          error,
          stackTrace,
          fallbackCode: 'settings_write_failed',
        ),
      );
    }
  }

  Future<_SettingsCatalog> _loadCatalog() {
    return _catalogFuture ??= _readCatalogWithFailureReset();
  }

  Future<_SettingsCatalog> _readCatalogWithFailureReset() async {
    try {
      return await _readCatalog();
    } catch (_) {
      _catalogFuture = null;
      rethrow;
    }
  }

  Future<_SettingsCatalog> _readCatalog() async {
    final currencySource = await _assets.loadString(
      'assets/data/currencies.json',
    );
    final regionSource = await _assets.loadString('assets/data/countries.json');
    final currencies =
        _deduplicateCurrencies(
              _decodeList(
                currencySource,
                limit: 256,
                decode: FiatCurrency.fromJson,
              ),
            )
            .where((item) => FiatCurrencyPolicy.supportsMarketQuote(item.code))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final regions = _decodeList(
      regionSource,
      limit: 512,
      decode: Region.fromJson,
    )..sort((a, b) => a.name.compareTo(b.name));
    _requireUnique(regions.map((item) => item.code), 'region');
    if (!currencies.any(
          (item) => item.code == AppPreferences.defaults.currencyCode,
        ) ||
        !regions.any(
          (item) => item.code == AppPreferences.defaults.regionCode,
        )) {
      throw const FormatException('Default settings catalog entries missing.');
    }
    return _SettingsCatalog(currencies: currencies, regions: regions);
  }

  Future<void> _repairIfNeeded({
    required String? storedCurrency,
    required String? storedRegion,
    required String? storedUnit,
    required bool? storedVisibility,
    required AppPreferences resolved,
  }) async {
    if (storedCurrency != resolved.currencyCode) {
      await _preferences.setString(_currencyKey, resolved.currencyCode);
    }
    if (storedRegion != resolved.regionCode) {
      await _preferences.setString(_regionKey, resolved.regionCode);
    }
    if (storedUnit != resolved.bitcoinUnit.storageValue) {
      await _preferences.setString(
        _bitcoinUnitKey,
        resolved.bitcoinUnit.storageValue,
      );
    }
    if (storedVisibility != resolved.balancesVisible) {
      await _preferences.setBool(_balancesVisibleKey, resolved.balancesVisible);
    }
  }

  Future<AppResult<T>> _enqueue<T>(Future<AppResult<T>> Function() operation) {
    final completer = Completer<AppResult<T>>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.complete(
          AppResult.failure(FailureMapper.from(error, stackTrace)),
        );
      }
    });
    return completer.future;
  }

  static BitcoinUnit _parseUnit(String? value) {
    if (value == null) return AppPreferences.defaults.bitcoinUnit;
    try {
      return BitcoinUnit.parse(value);
    } on FormatException {
      return AppPreferences.defaults.bitcoinUnit;
    }
  }

  static List<T> _decodeList<T>(
    String source, {
    required int limit,
    required T Function(Map<String, Object?>) decode,
  }) {
    final value = jsonDecode(source);
    if (value is! List<Object?> || value.isEmpty || value.length > limit) {
      throw const FormatException('Invalid settings catalog.');
    }
    return value.map((item) {
      if (item is! Map<String, Object?>) {
        throw const FormatException('Invalid settings catalog entry.');
      }
      return decode(item);
    }).toList();
  }

  static void _requireUnique(Iterable<String> values, String kind) {
    final seen = <String>{};
    if (values.any((value) => !seen.add(value))) {
      throw FormatException('Duplicate $kind catalog code.');
    }
  }

  static List<FiatCurrency> _deduplicateCurrencies(
    List<FiatCurrency> currencies,
  ) {
    // A fiat currency can be legal tender in multiple countries, but the
    // persisted identity is its ISO code. Keep the catalog's first curated
    // presentation entry so one code always maps to exactly one selectable row.
    final byCode = <String, FiatCurrency>{};
    for (final currency in currencies) {
      byCode.putIfAbsent(currency.code, () => currency);
    }
    return byCode.values.toList();
  }
}

final class _SettingsCatalog {
  _SettingsCatalog({
    required List<FiatCurrency> currencies,
    required List<Region> regions,
  }) : currencies = List<FiatCurrency>.unmodifiable(currencies),
       regions = List<Region>.unmodifiable(regions);

  final List<FiatCurrency> currencies;
  final List<Region> regions;
}
