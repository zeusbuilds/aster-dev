import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/onboarding_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  test('production container never retries provider build failures', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = createApplicationProviderContainer(preferences);
    addTearDown(container.dispose);
    var builds = 0;
    final failingProvider = FutureProvider<int>((ref) async {
      builds += 1;
      throw const AppFailureException(
        AppFailure(
          code: 'test_non_retryable_failure',
          kind: AppFailureKind.validation,
          userMessage: 'Test failure.',
          retryable: false,
        ),
      );
    });
    final subscription = container.listen(
      failingProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    expect(container.retry, same(applicationProviderRetryPolicy));
    expect(
      ProviderContainer.defaultRetry(
        0,
        const AppFailureException(
          AppFailure(
            code: 'test_default_retry',
            kind: AppFailureKind.validation,
            userMessage: 'Test failure.',
            retryable: false,
          ),
        ),
      ),
      const Duration(milliseconds: 200),
    );
    await expectLater(
      container.read(failingProvider.future),
      throwsA(isA<AppFailureException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(builds, 1);
  });

  test('bootstrap rejects a container with implicit retry', () async {
    final container = ProviderContainer();

    await expectLater(
      bootstrapApplicationContainer(container),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('preloads authoritative wallet state before returning', () async {
    final harness = await OnboardingTestHarness.create();
    addTearDown(harness.dispose);

    final container = await bootstrapApplicationContainer(harness.container);

    expect(container, same(harness.container));
    expect(container.read(walletViewModelProvider).hasValue, isTrue);
    expect(container.read(walletViewModelProvider).value?.activeWallet, isNull);
  });

  test(
    'authoritative empty bootstrap returns to unprotected Welcome',
    () async {
      final device = _SecuredDevice();
      final security = SecurityController(device);
      await security.initialize(hasWallet: true);
      expect(await security.unlock(), isTrue);
      security.updateWallet(_profile.id);
      // An interrupted deletion was classified as an existing wallet by the
      // public pre-auth registry. Bootstrap then finishes with no wallet left.
      expect(await security.authorize(SecurityPurpose.walletSetup), isNotNull);
      final harness = await OnboardingTestHarness.create(
        securityController: security,
      );
      addTearDown(harness.dispose);
      device.reasons.clear();

      await bootstrapApplicationContainer(harness.container);
      expect(
        harness.container.read(walletViewModelProvider).value?.wallets,
        isEmpty,
      );
      expect(security.canAccessWallet, isTrue);
      expect(security.appLockEnabled, isTrue);
      security.handleLifecycle(AppLifecycleState.paused);
      expect(security.isLocked, isFalse);
      security.handleLifecycle(AppLifecycleState.resumed);
      expect(await security.prepareForeground(), isTrue);
      expect(device.reasons, isEmpty);
    },
  );

  test('nonempty bootstrap preserves app-lock protection', () async {
    final device = _SecuredDevice();
    final security = SecurityController(device);
    final harness = await OnboardingTestHarness.create(
      securityController: security,
    );
    addTearDown(harness.dispose);
    final created = await harness.repository.createFromMnemonic(
      name: 'Wallet',
      mnemonic: validTestMnemonic,
    );
    expect(created, isA<AppSuccess<WalletRegistry>>());
    final registry = (created as AppSuccess<WalletRegistry>).value;
    security.updateWallet(registry.activeWalletId);
    device.reasons.clear();

    await bootstrapApplicationContainer(harness.container);
    security.handleLifecycle(AppLifecycleState.paused);
    expect(security.isLocked, isTrue);
    security.handleLifecycle(AppLifecycleState.resumed);
    expect(await security.prepareForeground(), isTrue);
    expect(device.reasons, ['Unlock Aster']);
  });

  test(
    'awaits runtime destruction when repository construction fails',
    () async {
      final engine = FakeWalletEngine();
      final container = ProviderContainer(
        retry: applicationProviderRetryPolicy,
        overrides: [
          walletEngineFactoryProvider.overrideWithValue(
            FakeWalletEngineFactory([engine]),
          ),
          walletDirectoryManagerProvider.overrideWith(
            (ref) async => FakeWalletDirectoryManager(),
          ),
          secureStorageServiceProvider.overrideWithValue(MemorySecureStore()),
          walletServiceConfigurationProvider.overrideWithValue(_services),
          walletRepositoryProvider.overrideWith((ref) async {
            final runtime = await ref.read(walletRuntimeProvider.future);
            final provisioned = await runtime.provision(
              profile: _profile,
              mnemonic: 'mnemonic words',
              databasePassword: 'password',
            );
            if (provisioned is AppFailureResult<void>) {
              throw StateError('Test runtime could not be provisioned.');
            }
            throw StateError('Injected repository construction failure.');
          }),
        ],
      );

      await expectLater(
        bootstrapApplicationContainer(container),
        throwsA(isA<StateError>()),
      );

      expect(engine.calls, containsAllInOrder(['provision', 'destroy']));
    },
  );

  test('preserves unknown outcome when bootstrap cleanup fails', () async {
    final engine = FakeWalletEngine()
      ..destroyError = const AppFailureException(
        AppFailure(
          code: 'test_native_outcome_unknown',
          kind: AppFailureKind.timeout,
          userMessage: 'Test operation outcome is unknown.',
          retryable: false,
          outcomeUnknown: true,
        ),
      );
    final container = ProviderContainer(
      retry: applicationProviderRetryPolicy,
      overrides: [
        walletEngineFactoryProvider.overrideWithValue(
          FakeWalletEngineFactory([engine]),
        ),
        walletDirectoryManagerProvider.overrideWith(
          (ref) async => FakeWalletDirectoryManager(),
        ),
        secureStorageServiceProvider.overrideWithValue(MemorySecureStore()),
        walletServiceConfigurationProvider.overrideWithValue(_services),
        walletRepositoryProvider.overrideWith((ref) async {
          final runtime = await ref.read(walletRuntimeProvider.future);
          await runtime.provision(
            profile: _profile,
            mnemonic: 'mnemonic words',
            databasePassword: 'password',
          );
          throw StateError('Injected repository construction failure.');
        }),
      ],
    );

    await expectLater(
      bootstrapApplicationContainer(container),
      throwsA(
        isA<AppFailureException>()
            .having(
              (error) => error.failure.requiresReconciliation,
              'requiresReconciliation',
              isTrue,
            )
            .having(
              (error) => error.failure.outcomeUnknown,
              'outcomeUnknown',
              isTrue,
            ),
      ),
    );

    expect(engine.calls, containsAllInOrder(['provision', 'destroy']));
  });

  test('requires reconciliation when bootstrap cleanup fails known', () async {
    final engine = FakeWalletEngine()
      ..destroyError = StateError('injected known destroy failure');
    final container = ProviderContainer(
      retry: applicationProviderRetryPolicy,
      overrides: [
        walletEngineFactoryProvider.overrideWithValue(
          FakeWalletEngineFactory([engine]),
        ),
        walletDirectoryManagerProvider.overrideWith(
          (ref) async => FakeWalletDirectoryManager(),
        ),
        secureStorageServiceProvider.overrideWithValue(MemorySecureStore()),
        walletServiceConfigurationProvider.overrideWithValue(_services),
        walletRepositoryProvider.overrideWith((ref) async {
          final runtime = await ref.read(walletRuntimeProvider.future);
          await runtime.provision(
            profile: _profile,
            mnemonic: 'mnemonic words',
            databasePassword: 'password',
          );
          throw StateError('Injected repository construction failure.');
        }),
      ],
    );

    await expectLater(
      bootstrapApplicationContainer(container),
      throwsA(
        isA<AppFailureException>()
            .having(
              (error) => error.failure.requiresReconciliation,
              'requiresReconciliation',
              isTrue,
            )
            .having(
              (error) => error.failure.outcomeUnknown,
              'outcomeUnknown',
              isFalse,
            ),
      ),
    );

    expect(engine.calls, containsAllInOrder(['provision', 'destroy']));
  });
}

const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
);

final _profile = WalletProfile(
  id: '11111111111111111111111111111111',
  name: 'Wallet',
  createdAt: DateTime.utc(2026, 8, 8),
  updatedAt: DateTime.utc(2026, 8, 8),
  environment: BlockchainEnvironment.regtest,
  state: WalletProfileState.provisioning,
  storageToken: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
);

final class _SecuredDevice implements DeviceAuthentication {
  final reasons = <String>[];

  @override
  Future<DeviceSecurityStatus> status() async => DeviceSecurityStatus.secured;

  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) async {
    reasons.add(reason);
    return DeviceAuthenticationResult.authenticated;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> setSensitive(bool value) async {}

  @override
  Stream<bool> get captureChanges => const Stream.empty();

  @override
  bool get isCaptured => false;
}
