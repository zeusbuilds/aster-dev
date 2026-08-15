import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/wallet_fakes.dart';

void main() {
  test('ignores reload while the initial wallet read is active', () async {
    final harness = await _createHarness(delayRepository: true);
    final subscription = harness.container.listen(
      walletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      await harness.dispose();
    });

    await harness.container.read(walletViewModelProvider.notifier).reload();
    await harness.container.read(walletViewModelProvider.future);

    expect(harness.documents.readCount, 1);
  });

  test('retryable initial wallet failure can recover explicitly', () async {
    final harness = await _createHarness(
      readError: TimeoutException('temporary registry timeout'),
    );
    final subscription = harness.container.listen(
      walletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      await harness.dispose();
    });

    await expectLater(
      harness.container.read(walletViewModelProvider.future),
      throwsA(isA<AppFailureException>()),
    );
    harness.documents.readError = null;

    await harness.container.read(walletViewModelProvider.notifier).reload();

    expect(
      harness.container.read(walletViewModelProvider),
      isA<AsyncData<WalletState>>(),
    );
    expect(harness.documents.readCount, 2);
  });

  test('terminal initial wallet failure cannot be reloaded', () async {
    final harness = await _createHarness(
      readError: StateError('terminal registry state'),
    );
    final subscription = harness.container.listen(
      walletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      await harness.dispose();
    });

    await expectLater(
      harness.container.read(walletViewModelProvider.future),
      throwsA(isA<AppFailureException>()),
    );
    harness.documents.readError = null;

    await harness.container.read(walletViewModelProvider.notifier).reload();

    expect(
      harness.container.read(walletViewModelProvider),
      isA<AsyncError<WalletState>>(),
    );
    expect(harness.documents.readCount, 1);
  });

  test(
    'publishes switch progress and suppresses overlapping wallet changes',
    () async {
      final activationGate = Completer<void>();
      final engine = FakeWalletEngine()..initializeGate = activationGate;
      final harness = await _createHarness(
        seedWalletProfiles: true,
        engines: [engine],
      );
      final subscription = harness.container.listen(
        walletViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        await harness.dispose();
      });
      await harness.container.read(walletViewModelProvider.future);
      final notifier = harness.container.read(walletViewModelProvider.notifier);

      final switching = notifier.switchWallet(_secondWalletId);
      expect(
        harness.container.read(walletViewModelProvider).requireValue,
        isA<WalletState>()
            .having(
              (value) => value.activeWallet?.id,
              'active wallet',
              _firstWalletId,
            )
            .having(
              (value) => value.switchingWalletId,
              'switching wallet',
              _secondWalletId,
            ),
      );
      expect(await notifier.switchWallet(_secondWalletId), isFalse);
      expect(await notifier.switchWallet(_firstWalletId), isFalse);

      activationGate.complete();
      expect(await switching, isTrue);
      expect(engine.calls.where((call) => call == 'initialize'), hasLength(1));
      expect(
        harness.container.read(walletViewModelProvider).requireValue,
        isA<WalletState>()
            .having(
              (value) => value.activeWallet?.id,
              'active wallet',
              _secondWalletId,
            )
            .having(
              (value) => value.switchingWalletId,
              'switching wallet',
              isNull,
            )
            .having(
              (value) => value.operationFailure,
              'operation failure',
              isNull,
            ),
      );
      expect(await notifier.switchWallet(_secondWalletId), isFalse);
    },
  );

  test(
    'restores prior state when the requested wallet no longer exists',
    () async {
      final harness = await _createHarness(seedWalletProfiles: true);
      final subscription = harness.container.listen(
        walletViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        await harness.dispose();
      });
      final before = await harness.container.read(
        walletViewModelProvider.future,
      );
      final notifier = harness.container.read(walletViewModelProvider.notifier);

      expect(await notifier.switchWallet(_missingWalletId), isFalse);

      final after = harness.container
          .read(walletViewModelProvider)
          .requireValue;
      expect(after.wallets, before.wallets);
      expect(after.activeWallet, before.activeWallet);
      expect(after.switchingWalletId, isNull);
      expect(after.operationFailure?.code, 'wallet_profile_not_found');
      expect(after.operationFailure?.retryable, isFalse);
    },
  );

  test(
    'rejects adopting a committed registry without an active wallet',
    () async {
      final harness = await _createHarness();
      final subscription = harness.container.listen(
        walletViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        await harness.dispose();
      });
      await harness.container.read(walletViewModelProvider.future);

      expect(
        () => harness.container
            .read(walletViewModelProvider.notifier)
            .adoptCommittedRegistry(
              WalletRegistry(profiles: const [], activeWalletId: null),
            ),
        throwsArgumentError,
      );
    },
  );
}

Future<_WalletViewModelHarness> _createHarness({
  Object? readError,
  bool delayRepository = false,
  bool seedWalletProfiles = false,
  List<FakeWalletEngine> engines = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = PreferencesService(await SharedPreferences.getInstance());
  final documents = MemoryWalletRegistryDocumentStore()..readError = readError;
  final profiles = WalletProfileStore(documents, preferences);
  final secureStorage = MemorySecureStore();
  final secrets = WalletSecretStore(secureStorage);
  final directories = FakeWalletDirectoryManager();
  if (seedWalletProfiles) {
    await _storeWallet(
      profiles,
      secrets,
      directories,
      id: _firstWalletId,
      name: 'Primary Wallet',
      storageToken: _firstStorageToken,
    );
    await _storeWallet(
      profiles,
      secrets,
      directories,
      id: _secondWalletId,
      name: 'Savings Wallet',
      storageToken: _secondStorageToken,
    );
    final selected = await profiles.setActive(_firstWalletId);
    expect(selected, isA<AppSuccess<WalletRegistry>>());
  }
  final runtime = WalletRuntime(
    FakeWalletEngineFactory(engines),
    directories,
    secrets,
    _services,
  );
  final repository = WalletRepository(
    profiles,
    runtime,
    FakeWalletKeyGenerator(),
    FakeWalletIdentityGenerator(walletId: '11111111111111111111111111111111'),
    _services,
    const SuccessfulLegacyWalletSeedPreflight(),
  );
  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [
      walletRepositoryProvider.overrideWith((ref) async {
        if (delayRepository) await Future<void>.delayed(Duration.zero);
        return repository;
      }),
    ],
  );
  return _WalletViewModelHarness(
    container: container,
    repository: repository,
    documents: documents,
  );
}

Future<void> _storeWallet(
  WalletProfileStore profiles,
  WalletSecretStore secrets,
  FakeWalletDirectoryManager directories, {
  required String id,
  required String name,
  required String storageToken,
}) async {
  final timestamp = DateTime.utc(2026);
  final profile = WalletProfile(
    id: id,
    name: name,
    createdAt: timestamp,
    updatedAt: timestamp,
    environment: BlockchainEnvironment.regtest,
    state: WalletProfileState.provisioning,
    storageToken: storageToken,
  );
  expect(
    await profiles.stageProvision(profile),
    isA<AppSuccess<WalletRegistry>>(),
  );
  expect(
    await secrets.write(
      id,
      WalletSecret(
        databasePassword: 'test-database-password',
        mnemonic: _mnemonic,
        storageToken: storageToken,
      ),
    ),
    isA<AppSuccess<void>>(),
  );
  await directories.create(id, storageToken: storageToken);
  expect(await profiles.commitProvision(id), isA<AppSuccess<WalletRegistry>>());
}

final class _WalletViewModelHarness {
  const _WalletViewModelHarness({
    required this.container,
    required this.repository,
    required this.documents,
  });

  final ProviderContainer container;
  final WalletRepository repository;
  final MemoryWalletRegistryDocumentStore documents;

  Future<void> dispose() async {
    container.dispose();
    await repository.dispose();
  }
}

const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
);

const _firstWalletId = '11111111111111111111111111111111';
const _secondWalletId = '22222222222222222222222222222222';
const _missingWalletId = '33333333333333333333333333333333';
const _firstStorageToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _secondStorageToken = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
