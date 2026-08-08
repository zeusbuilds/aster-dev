import 'dart:async';
import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/settings/data/repository/repository.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loads documented defaults and persists all selections', () async {
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
    );
    final repository = SettingsRepository(preferences, _validCatalog());

    final initial = await repository.load();
    expect(initial, isA<AppSuccess<SettingsSnapshot>>());
    final initialSnapshot = (initial as AppSuccess<SettingsSnapshot>).value;
    expect(initialSnapshot.preferences, AppPreferences.defaults);

    expect(
      await repository.selectCurrency('EUR'),
      isA<AppSuccess<SettingsSnapshot>>(),
    );
    expect(
      await repository.selectRegion('DE'),
      isA<AppSuccess<SettingsSnapshot>>(),
    );
    expect(
      await repository.selectBitcoinUnit(BitcoinUnit.sats),
      isA<AppSuccess<SettingsSnapshot>>(),
    );
    expect(
      await repository.setBalancesVisible(false),
      isA<AppSuccess<SettingsSnapshot>>(),
    );

    final restarted = SettingsRepository(preferences, _validCatalog());
    final restored = await restarted.load() as AppSuccess<SettingsSnapshot>;
    expect(restored.value.preferences.currencyCode, 'EUR');
    expect(restored.value.preferences.regionCode, 'DE');
    expect(restored.value.preferences.bitcoinUnit, BitcoinUnit.sats);
    expect(restored.value.preferences.balancesVisible, isFalse);
  });

  test('rejects values outside validated catalogs without writing', () async {
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
    );
    final repository = SettingsRepository(preferences, _validCatalog());
    await repository.load();

    final currency = await repository.selectCurrency('BTC');
    final region = await repository.selectRegion('ZZ');

    expect(currency, isA<AppFailureResult<SettingsSnapshot>>());
    expect(
      (currency as AppFailureResult<SettingsSnapshot>).failure.kind,
      AppFailureKind.validation,
    );
    expect(region, isA<AppFailureResult<SettingsSnapshot>>());
    expect(
      (region as AppFailureResult<SettingsSnapshot>).failure.kind,
      AppFailureKind.validation,
    );
  });

  test('maps malformed assets without retaining their payload', () async {
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
    );
    final assets = _MemoryAssetBundle({
      'assets/data/currencies.json': '[{"secret":"mnemonic material"}]',
      'assets/data/countries.json': _regions,
    });

    final result = await SettingsRepository(preferences, assets).load();

    expect(result, isA<AppFailureResult<SettingsSnapshot>>());
    final failure = (result as AppFailureResult<SettingsSnapshot>).failure;
    expect(failure.userMessage, isNot(contains('mnemonic')));
    expect(failure.cause.toString(), isNot(contains('mnemonic material')));
  });

  test('production catalogs satisfy repository invariants', () async {
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
    );

    final result = await SettingsRepository(preferences, rootBundle).load();

    expect(result, isA<AppSuccess<SettingsSnapshot>>());
    final snapshot = (result as AppSuccess<SettingsSnapshot>).value;
    expect(snapshot.currencies.length, greaterThan(80));
    expect(snapshot.regions.length, greaterThan(200));
    expect(
      snapshot.currencies.map((item) => item.code).toSet().length,
      snapshot.currencies.length,
    );
    expect(snapshot.selectedCurrency.code, 'USD');
    expect(snapshot.selectedRegion.code, 'US');
  });

  test('serializes concurrent preference writes', () async {
    final shared = await SharedPreferences.getInstance();
    await shared.setString('utexo.settings.v1.currency', 'USD');
    await shared.setString('utexo.settings.v1.region', 'US');
    await shared.setString('utexo.settings.v1.bitcoin_unit', 'btc');
    await shared.setBool('utexo.settings.v1.balances_visible', true);
    final preferences = _TrackingPreferencesService(shared);
    final repository = SettingsRepository(preferences, _validCatalog());
    await repository.load();

    final first = repository.selectCurrency('EUR');
    await preferences.firstWriteStarted.future;
    final second = repository.selectRegion('DE');
    preferences.releaseWrites.complete();

    expect(await first, isA<AppSuccess<SettingsSnapshot>>());
    expect(await second, isA<AppSuccess<SettingsSnapshot>>());
    expect(preferences.maxConcurrentWrites, 1);
  });
}

_MemoryAssetBundle _validCatalog() => _MemoryAssetBundle({
  'assets/data/currencies.json': _currencies,
  'assets/data/countries.json': _regions,
});

const _currencies = '''
[
  {"name":"United States Dollar","symbol":"\$","code":"USD","countryCode":"US"},
  {"name":"Euro","symbol":"€","code":"EUR","countryCode":"DE"}
]
''';

const _regions = '''
[
  {"name":"United States","code":"US"},
  {"name":"Germany","code":"DE"}
]
''';

final class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.sources);

  final Map<String, String> sources;

  @override
  Future<ByteData> load(String key) async {
    final source = sources[key];
    if (source == null) throw StateError('Missing test asset.');
    final bytes = Uint8List.fromList(utf8.encode(source));
    return ByteData.sublistView(bytes);
  }
}

final class _TrackingPreferencesService extends PreferencesService {
  _TrackingPreferencesService(super.preferences);

  final firstWriteStarted = Completer<void>();
  final releaseWrites = Completer<void>();
  var _concurrentWrites = 0;
  var maxConcurrentWrites = 0;

  @override
  Future<void> setString(String key, String value) async {
    _concurrentWrites += 1;
    maxConcurrentWrites = maxConcurrentWrites < _concurrentWrites
        ? _concurrentWrites
        : maxConcurrentWrites;
    if (!firstWriteStarted.isCompleted) firstWriteStarted.complete();
    await releaseWrites.future;
    try {
      await super.setString(key, value);
    } finally {
      _concurrentWrites -= 1;
    }
  }
}
