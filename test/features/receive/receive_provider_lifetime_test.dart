import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/payment_flow_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PreferencesService> preferences() async {
    SharedPreferences.setMockInitialValues({});
    return PreferencesService(await SharedPreferences.getInstance());
  }

  test('production settings factory captures dependencies before an async disposal gap', () async {
    final gate = Completer<PreferencesService>();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        preferencesServiceProvider.overrideWith((ref) => gate.future),
        appAssetBundleProvider.overrideWithValue(PaymentSettingsAssetBundle()),
      ],
    );
    addTearDown(container.dispose);
    // This is the actual production settingsRepository factory, not an override.
    final pending = container.read(settingsRepositoryProvider.future);
    final outcome = pending.then<Object>(
      (value) => value,
      onError: (Object error) => error,
    );
    await container.pump();
    gate.complete(await preferences());
    await container.pump();
    final value = await outcome.timeout(const Duration(seconds: 2));
    expect(value.runtimeType.toString(), isNot('UnmountedRefException'));
    expect(value, isNot(isA<Exception>()));
  });

  test('Receive retains real settings dependencies over slow frames and request regeneration', () async {
    final harness = await PaymentFlowTestHarness.create(
      services: testRgbServices,
    );
    addTearDown(harness.dispose);
    final gate = Completer<PreferencesService>();
    var settingsDisposed = false;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        walletRepositoryProvider.overrideWith(
          (ref) async => harness.repository,
        ),
        preferencesServiceProvider.overrideWith((ref) {
          ref.onDispose(() => settingsDisposed = true);
          return gate.future;
        }),
        appAssetBundleProvider.overrideWithValue(PaymentSettingsAssetBundle()),
      ],
    );
    addTearDown(container.dispose);
    final provider = receiveFlowViewModelProvider(
      WalletPaymentTarget.usdtOnchain,
    );
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    for (var frame = 0; frame < 4; frame++) {
      await container.pump();
    }
    expect(settingsDisposed, isFalse);
    expect(
      harness.engine.calls.where((c) => c == 'createReceiveRequest:start'),
      isEmpty,
    );
    gate.complete(await preferences());
    final initial = await container.read(provider.future);
    expect(initial.request, isNotNull);
    await container.pump();
    expect(await container.read(provider.notifier).regenerate(), isTrue);
    expect(container.read(provider).hasError, isFalse);
    expect(settingsDisposed, isFalse);
    expect(
      harness.engine.calls.where((c) => c == 'createReceiveRequest:start'),
      hasLength(2),
    );
  });

  test('disposing a pending Receive generation cannot create a late native request', () async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(harness.dispose);
    final gate = Completer<PreferencesService>();
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        walletRepositoryProvider.overrideWith(
          (ref) async => harness.repository,
        ),
        preferencesServiceProvider.overrideWith((ref) => gate.future),
        appAssetBundleProvider.overrideWithValue(PaymentSettingsAssetBundle()),
      ],
    );
    addTearDown(container.dispose);
    final provider = receiveFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    await container.pump();
    final stale = container.read(provider.notifier);
    subscription.close();
    await container.pump();
    gate.complete(await preferences());
    await container.pump();
    expect(
      harness.engine.calls.where((c) => c == 'createReceiveRequest:start'),
      isEmpty,
    );
    // A stale UI callback is rejected without touching an unmounted Ref.
    await stale.retry();
    expect(
      harness.engine.calls.where((c) => c == 'createReceiveRequest:start'),
      isEmpty,
    );
    final active = container.listen(provider, (_, _) {}, fireImmediately: true);
    addTearDown(active.close);
    expect((await container.read(provider.future)).request, isNotNull);
    expect(
      harness.engine.calls.where((c) => c == 'createReceiveRequest:start'),
      hasLength(1),
    );
  });

  test('a settings dependency rebuild discards the previous generation before native entry', () async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(harness.dispose);
    final first = Completer<PreferencesService>();
    final second = Completer<PreferencesService>();
    var selected = first;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        walletRepositoryProvider.overrideWith(
          (ref) async => harness.repository,
        ),
        preferencesServiceProvider.overrideWith((ref) => selected.future),
        appAssetBundleProvider.overrideWithValue(PaymentSettingsAssetBundle()),
      ],
    );
    addTearDown(container.dispose);
    final provider = receiveFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.pump();
    selected = second;
    container.invalidate(preferencesServiceProvider);
    await container.pump();
    first.complete(await preferences());
    await container.pump();
    expect(
      harness.engine.calls.where((c) => c == 'createReceiveRequest:start'),
      isEmpty,
    );
    second.complete(await preferences());
    expect((await container.read(provider.future)).request, isNotNull);
    expect(
      harness.engine.calls.where((c) => c == 'createReceiveRequest:start'),
      hasLength(1),
    );
    expect(container.read(provider).hasError, isFalse);
  });
}
