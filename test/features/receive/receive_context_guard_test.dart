import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retained QR cannot be copied, shared, edited or regenerated during a dependency reload', () async {
    final harness = await PaymentFlowTestHarness.create(
      services: testRgbServices,
    );
    addTearDown(harness.dispose);
    harness.engine.createdReceiveRequest = WalletReceiveRequest(
      route: testRgbRoute,
      encodedRequest: 'rgb:prior-witness-fixture',
      displayValue: 'rgb:prior-witness-fixture',
    );
    final preferences = Completer<PreferencesService>();
    SharedPreferences.setMockInitialValues({});
    var selectedPreferences = Future.value(
      PreferencesService(await SharedPreferences.getInstance()),
    );
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        walletRepositoryProvider.overrideWith(
          (ref) async => harness.repository,
        ),
        preferencesServiceProvider.overrideWith((ref) => selectedPreferences),
        appAssetBundleProvider.overrideWithValue(PaymentSettingsAssetBundle()),
        clipboardServiceProvider.overrideWithValue(harness.clipboard),
        shareServiceProvider.overrideWithValue(harness.share),
        hapticFeedbackServiceProvider.overrideWithValue(harness.haptics),
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
    final initial = await container.read(provider.future);
    final notifier = container.read(provider.notifier);

    selectedPreferences = preferences.future;
    container.invalidate(preferencesServiceProvider);
    await container.pump();
    final loading = container.read(provider);
    expect(loading.isLoading, isTrue);
    // Riverpod intentionally retains this value, but it is not current data.
    expect(loading.value?.request, initial.request);
    final callsBefore = List<String>.of(harness.engine.calls);

    expect(await notifier.copyRequest(), isA<AppFailureResult<void>>());
    expect(
      await notifier.shareRequest(),
      isA<AppFailureResult<ShareDisposition>>(),
    );
    notifier.updateAmount('1');
    expect(await notifier.applyAmount(), isFalse);
    expect(await notifier.regenerate(), isFalse);
    expect(container.read(provider).isLoading, isTrue);
    expect(harness.engine.calls, callsBefore);
    expect(harness.clipboard.text, isNull);
    expect(harness.share.sharedText, isNull);

    SharedPreferences.setMockInitialValues({});
    preferences.complete(
      PreferencesService(await SharedPreferences.getInstance()),
    );
    expect((await container.read(provider.future)).request, isNotNull);
    expect(
      harness.engine.calls.where(
        (call) => call == 'createReceiveRequest:start',
      ),
      hasLength(2),
    );
  });

  test('a retained Receive provider blocks old-wallet commands while selection changes', () async {
    final platform = await PaymentFlowTestHarness.create();
    addTearDown(platform.dispose);
    final first = FakeWalletEngine()
      ..createdReceiveRequest = _request('wallet-a');
    final second = FakeWalletEngine()
      ..createdReceiveRequest = _request('wallet-b')
      ..openPersistedGate = Completer<void>();
    final fixture = await _twoWalletContainer(platform, first, second);
    addTearDown(() async {
      fixture.container.dispose();
      await fixture.runtime.dispose();
    });
    final provider = receiveFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = fixture.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    expect(
      (await fixture.container.read(provider.future)).request?.encodedRequest,
      'bitcoin:wallet-a',
    );
    final notifier = fixture.container.read(provider.notifier);

    final switching = fixture.container
        .read(walletViewModelProvider.notifier)
        .switchWallet(_secondId);
    await _waitFor(() => second.calls.contains('openPersisted'));
    await fixture.container.pump();
    expect(await notifier.copyRequest(), isA<AppFailureResult<void>>());
    expect(
      await notifier.shareRequest(),
      isA<AppFailureResult<ShareDisposition>>(),
    );
    expect(await notifier.regenerate(), isFalse);
    expect(platform.clipboard.text, isNull);
    expect(platform.share.sharedText, isNull);
    expect(
      first.calls.where((call) => call == 'createReceiveRequest:start'),
      hasLength(1),
    );
    expect(second.calls, isNot(contains('createReceiveRequest:start')));

    second.openPersistedGate!.complete();
    expect(await switching, isTrue);
    await fixture.container.pump();
    final current = await fixture.container.read(provider.future);
    expect(current.request?.encodedRequest, 'bitcoin:wallet-b');
    expect(
      second.calls.where((call) => call == 'createReceiveRequest:start'),
      hasLength(1),
    );
  });

  test(
    'an old-wallet native completion cannot replace the new wallet request',
    () async {
      final platform = await PaymentFlowTestHarness.create();
      addTearDown(platform.dispose);
      final first = FakeWalletEngine()
        ..createdReceiveRequest = _request('wallet-a')
        ..createReceiveGate = Completer<void>();
      final second = FakeWalletEngine()
        ..createdReceiveRequest = _request('wallet-b');
      final fixture = await _twoWalletContainer(platform, first, second);
      addTearDown(() async {
        fixture.container.dispose();
        await fixture.runtime.dispose();
      });
      final provider = receiveFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final visibleRequests = <String>[];
      final subscription = fixture.container.listen(provider, (_, next) {
        if (!next.isLoading && !next.hasError && next.value?.request != null) {
          visibleRequests.add(next.value!.request!.encodedRequest);
        }
      }, fireImmediately: true);
      addTearDown(subscription.close);
      await _waitFor(() => first.calls.contains('createReceiveRequest:start'));

      final switching = fixture.container
          .read(walletViewModelProvider.notifier)
          .switchWallet(_secondId);
      await fixture.container.pump();
      first.createReceiveGate!.complete();
      expect(await switching, isTrue);
      await fixture.container.pump();
      final current = await fixture.container.read(provider.future);

      expect(current.request?.encodedRequest, 'bitcoin:wallet-b');
      expect(visibleRequests, isNot(contains('bitcoin:wallet-a')));
      expect(visibleRequests, contains('bitcoin:wallet-b'));
      expect(
        first.calls.where((call) => call == 'createReceiveRequest:start'),
        hasLength(1),
      );
      expect(
        second.calls.where((call) => call == 'createReceiveRequest:start'),
        hasLength(1),
      );
    },
  );
}

const _firstId = '11111111111111111111111111111111';
const _secondId = '22222222222222222222222222222222';
const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
);

WalletReceiveRequest _request(String marker) => WalletReceiveRequest(
  route: const PaymentRoute(
    asset: WalletAsset.bitcoin,
    rail: PaymentRail.onchain,
  ),
  encodedRequest: 'bitcoin:$marker',
  displayValue: marker,
);

Future<({ProviderContainer container, WalletRuntime runtime})>
_twoWalletContainer(
  PaymentFlowTestHarness platform,
  FakeWalletEngine first,
  FakeWalletEngine second,
) async {
  final documents = WalletProfileStore(MemoryWalletRegistryDocumentStore());
  final directories = FakeWalletDirectoryManager();
  final secrets = WalletSecretStore(MemorySecureStore());
  for (final (id, token) in [(_firstId, 'a' * 32), (_secondId, 'b' * 32)]) {
    final staged = await documents.stageProvision(
      WalletProfile(
        id: id,
        name: id == _firstId ? 'First fixture' : 'Second fixture',
        createdAt: DateTime.utc(2026, 10, 15),
        updatedAt: DateTime.utc(2026, 10, 15),
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: token,
      ),
    );
    expect(staged, isA<AppSuccess<WalletRegistry>>());
    expect(
      await documents.commitProvision(id),
      isA<AppSuccess<WalletRegistry>>(),
    );
    directories.storageTokens[id] = token;
    await secrets.write(
      id,
      WalletSecret(
        databasePassword: 'public-fixture-password',
        mnemonic: 'public fixture marker',
        storageToken: token,
      ),
    );
  }
  expect(
    await documents.setActive(_firstId),
    isA<AppSuccess<WalletRegistry>>(),
  );
  final registry = (await documents.read() as AppSuccess<WalletRegistry>).value;
  final runtime = WalletRuntime(
    FakeWalletEngineFactory([first, second]),
    directories,
    secrets,
    _services,
  );
  expect(
    await runtime.restore(registry.activeProfile!),
    isA<AppSuccess<void>>(),
  );
  final repository = WalletRepository(
    documents,
    runtime,
    FakeWalletKeyGenerator(),
    FakeWalletIdentityGenerator(walletId: '33333333333333333333333333333333'),
    _services,
  );
  final settings = await platform.container.read(
    settingsRepositoryProvider.future,
  );
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      walletRepositoryProvider.overrideWith((ref) async => repository),
      settingsRepositoryProvider.overrideWith((ref) async => settings),
      clipboardServiceProvider.overrideWithValue(platform.clipboard),
      shareServiceProvider.overrideWithValue(platform.share),
      hapticFeedbackServiceProvider.overrideWithValue(platform.haptics),
    ],
  );
  // The actual WalletViewModel reads the real two-profile repository. There is
  // no WalletViewModel override and no dependency cycle through Receive.
  expect(
    (await container.read(walletViewModelProvider.future)).activeWallet?.id,
    _firstId,
  );
  return (container: container, runtime: runtime);
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for the public test fixture operation.');
}
