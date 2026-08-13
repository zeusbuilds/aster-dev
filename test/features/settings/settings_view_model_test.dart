import 'dart:async';
import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/settings/data/repository/repository.dart';
import 'package:aster/features/settings/presentation/view_model/view_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('suppresses overlapping settings mutations', () async {
    SharedPreferences.setMockInitialValues({
      'utexo.settings.v1.currency': 'USD',
      'utexo.settings.v1.region': 'US',
      'utexo.settings.v1.bitcoin_unit': 'btc',
      'utexo.settings.v1.balances_visible': true,
    });
    final preferences = _DelayedPreferencesService(
      await SharedPreferences.getInstance(),
    );
    final repository = SettingsRepository(preferences, _CatalogAssetBundle());
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWith((ref) async => repository),
      ],
    );
    final subscription = container.listen(
      settingsViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    await container.read(settingsViewModelProvider.future);

    final notifier = container.read(settingsViewModelProvider.notifier);
    final first = notifier.selectCurrency('EUR');
    await preferences.writeStarted.future;
    final overlapping = await notifier.selectRegion('DE');

    expect(overlapping, isFalse);
    preferences.releaseWrite.complete();
    expect(await first, isTrue);
    final state = container.read(settingsViewModelProvider).requireValue;
    expect(state.snapshot.preferences.currencyCode, 'EUR');
    expect(state.snapshot.preferences.regionCode, 'US');
    expect(state.operation, isNull);
  });
}

final class _DelayedPreferencesService extends PreferencesService {
  _DelayedPreferencesService(super.preferences);

  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();

  @override
  Future<void> setString(String key, String value) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await releaseWrite.future;
    await super.setString(key, value);
  }
}

final class _CatalogAssetBundle extends CachingAssetBundle {
  static const _sources = {
    'assets/data/currencies.json':
        '[{"name":"United States Dollar","symbol":"\$","code":"USD","countryCode":"US"},'
        '{"name":"Euro","symbol":"€","code":"EUR","countryCode":"DE"}]',
    'assets/data/countries.json':
        '[{"name":"United States","code":"US"},'
        '{"name":"Germany","code":"DE"}]',
  };

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(_sources[key]!));
    return ByteData.sublistView(bytes);
  }
}
