import 'dart:async';
import 'dart:convert';

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/settings/data/repository/repository.dart';
import 'package:aster/features/settings/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/payment_flow_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('suppresses overlapping settings mutations', () async {
    SharedPreferences.setMockInitialValues({
      'aster.settings.v1.currency': 'USD',
      'aster.settings.v1.region': 'US',
      'aster.settings.v1.bitcoin_unit': 'btc',
      'aster.settings.v1.balances_visible': true,
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

  test('stale preference mutation cannot overwrite a rebuilt state', () async {
    SharedPreferences.setMockInitialValues({
      'aster.settings.v1.currency': 'USD',
      'aster.settings.v1.region': 'US',
      'aster.settings.v1.bitcoin_unit': 'btc',
      'aster.settings.v1.balances_visible': true,
    });
    final preferences = _DelayedPreferencesService(
      await SharedPreferences.getInstance(),
    );
    var repository = SettingsRepository(preferences, _CatalogAssetBundle());
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
    final staleMutation = container
        .read(settingsViewModelProvider.notifier)
        .selectCurrency('EUR');
    await preferences.writeStarted.future;

    repository = SettingsRepository(
      PreferencesService(await SharedPreferences.getInstance()),
      _CatalogAssetBundle(),
    );
    container.invalidate(settingsRepositoryProvider);
    final rebuilt = await container.read(settingsViewModelProvider.future);
    expect(rebuilt.snapshot.preferences.currencyCode, 'USD');

    preferences.releaseWrite.complete();
    expect(await staleMutation, isFalse);
    expect(
      container
          .read(settingsViewModelProvider)
          .requireValue
          .snapshot
          .preferences
          .currencyCode,
      'USD',
    );
  });

  test('stale health retry cannot overwrite a rebuilt configuration', () async {
    const services = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
    );
    final firstHarness = await PaymentFlowTestHarness.create(
      services: services,
    );
    final secondHarness = await PaymentFlowTestHarness.create(
      services: services,
    );
    addTearDown(firstHarness.dispose);
    addTearDown(secondHarness.dispose);
    firstHarness.engine.networkStatusError = const AppFailureException(
      AppFailure(
        code: 'node_temporarily_unavailable',
        kind: AppFailureKind.unavailable,
        userMessage: 'Node health is temporarily unavailable.',
        retryable: true,
      ),
    );
    secondHarness.engine.networkStatus = WalletNetworkStatus(
      environment: BlockchainEnvironment.regtest,
      blockHeight: 101,
      nodePublicKey:
          '020000000000000000000000000000000000000000000000000000000000000000',
      channelCount: 2,
      usableChannelCount: 1,
      peerCount: 3,
    );
    var repository = firstHarness.repository;
    final container = ProviderContainer(
      retry: applicationProviderRetryPolicy,
      overrides: [
        hapticFeedbackServiceProvider.overrideWithValue(
          const NoopHapticFeedbackService(),
        ),
        walletRepositoryProvider.overrideWith((ref) async => repository),
        walletServiceConfigurationProvider.overrideWithValue(services),
      ],
    );
    final subscription = container.listen(
      networkConfigurationViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    await container.read(networkConfigurationViewModelProvider.future);
    expect(
      container
          .read(networkConfigurationViewModelProvider)
          .requireValue
          .healthFailure
          ?.retryable,
      isTrue,
    );
    firstHarness.engine.networkStatusError = null;
    final gate = Completer<void>();
    firstHarness.engine.networkStatusGate = gate;
    final staleRetry = container
        .read(networkConfigurationViewModelProvider.notifier)
        .refreshHealth();
    await _waitFor(
      () =>
          firstHarness.engine.calls
              .where((call) => call == 'networkStatus')
              .length ==
          2,
    );

    repository = secondHarness.repository;
    container.invalidate(walletRepositoryProvider);
    final rebuilt = await container.read(
      networkConfigurationViewModelProvider.future,
    );
    expect(rebuilt.status?.blockHeight, 101);

    firstHarness.engine.networkStatusError = StateError('stale native failure');
    gate.complete();
    await staleRetry;
    expect(
      container
          .read(networkConfigurationViewModelProvider)
          .requireValue
          .status
          ?.blockHeight,
      101,
    );
  });

  test('terminal settings load failure rejects explicit retry', () async {
    var repositoryReads = 0;
    final container = ProviderContainer(
      retry: applicationProviderRetryPolicy,
      overrides: [
        settingsRepositoryProvider.overrideWith((ref) {
          repositoryReads += 1;
          throw const AppFailureException(
            AppFailure(
              code: 'settings_configuration_invalid',
              kind: AppFailureKind.configuration,
              userMessage: 'Settings are not configured.',
              retryable: false,
            ),
          );
        }),
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
    await _waitFor(() => container.read(settingsViewModelProvider).hasError);

    await container.read(settingsViewModelProvider.notifier).retry();

    expect(repositoryReads, 1);
    expect(container.read(settingsViewModelProvider).hasError, isTrue);
  });

  test('initial retry is inert for already-loaded settings', () async {
    SharedPreferences.setMockInitialValues({
      'aster.settings.v1.currency': 'USD',
      'aster.settings.v1.region': 'US',
      'aster.settings.v1.bitcoin_unit': 'btc',
      'aster.settings.v1.balances_visible': true,
    });
    final repository = SettingsRepository(
      PreferencesService(await SharedPreferences.getInstance()),
      _CatalogAssetBundle(),
    );
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
    final before = container.read(settingsViewModelProvider);

    await container.read(settingsViewModelProvider.notifier).retry();

    expect(
      identical(container.read(settingsViewModelProvider), before),
      isTrue,
    );
  });

  test('terminal network health failure rejects explicit retry', () async {
    const services = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
    );
    final harness = await PaymentFlowTestHarness.create(services: services);
    addTearDown(harness.dispose);
    harness.engine.networkStatusError = const AppFailureException(
      AppFailure(
        code: 'node_configuration_invalid',
        kind: AppFailureKind.configuration,
        userMessage: 'Node health is not configured.',
        retryable: false,
      ),
    );
    final container = ProviderContainer(
      retry: applicationProviderRetryPolicy,
      overrides: [
        hapticFeedbackServiceProvider.overrideWithValue(
          const NoopHapticFeedbackService(),
        ),
        walletRepositoryProvider.overrideWith(
          (ref) async => harness.repository,
        ),
        walletServiceConfigurationProvider.overrideWithValue(services),
      ],
    );
    final subscription = container.listen(
      networkConfigurationViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });
    final state = await container.read(
      networkConfigurationViewModelProvider.future,
    );
    expect(state.healthFailure?.retryable, isFalse);

    await container
        .read(networkConfigurationViewModelProvider.notifier)
        .refreshHealth();

    expect(
      harness.engine.calls.where((call) => call == 'networkStatus'),
      hasLength(1),
    );
  });

  test('confirmed foreground resume reloads healthy network status', () async {
    const services = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
    );
    final harness = await PaymentFlowTestHarness.create(services: services);
    addTearDown(harness.dispose);
    final lifecycle = _MutableWalletLifecycleViewModel();
    harness.engine.networkStatus = WalletNetworkStatus(
      environment: BlockchainEnvironment.regtest,
      blockHeight: 100,
      nodePublicKey:
          '020000000000000000000000000000000000000000000000000000000000000000',
      channelCount: 1,
      usableChannelCount: 1,
      peerCount: 1,
    );
    final container = ProviderContainer(
      retry: applicationProviderRetryPolicy,
      overrides: [
        walletLifecycleViewModelProvider.overrideWith(() => lifecycle),
        walletRepositoryProvider.overrideWith(
          (ref) async => harness.repository,
        ),
        walletServiceConfigurationProvider.overrideWithValue(services),
      ],
    );
    final subscription = container.listen(
      networkConfigurationViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      subscription.close();
      container.dispose();
    });

    final initial = await container.read(
      networkConfigurationViewModelProvider.future,
    );
    expect(initial.status?.blockHeight, 100);

    harness.engine.networkStatus = WalletNetworkStatus(
      environment: BlockchainEnvironment.regtest,
      blockHeight: 101,
      nodePublicKey:
          '020000000000000000000000000000000000000000000000000000000000000000',
      channelCount: 2,
      usableChannelCount: 1,
      peerCount: 2,
    );
    lifecycle.publishForeground(1);
    await container.pump();
    final resumed = await container.read(
      networkConfigurationViewModelProvider.future,
    );

    expect(resumed.status?.blockHeight, 101);
    expect(
      harness.engine.calls.where((call) => call == 'networkStatus'),
      hasLength(2),
    );
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for asynchronous state.');
}

final class _MutableWalletLifecycleViewModel extends WalletLifecycleViewModel {
  @override
  WalletLifecycleState build() => const WalletLifecycleState();

  void publishForeground(int generation) {
    state = WalletLifecycleState(foregroundGeneration: generation);
  }
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
