import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/wallet_fakes.dart';

void main() {
  const walletId = '11111111111111111111111111111111';
  const secondWalletId = '22222222222222222222222222222222';
  const storageToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const secondStorageToken = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const services = WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
  );

  test('normalizes and validates every generated recovery phrase', () async {
    final keyGenerator = FakeWalletKeyGenerator()
      ..generatedMnemonic =
          '  ABANDON abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon ABOUT  ';
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      _FailingRegistrationStore(),
      runtime,
      keyGenerator,
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.generateMnemonic();

    expect(result, isA<AppSuccess<String>>());
    expect(
      (result as AppSuccess<String>).value,
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about',
    );
    expect(keyGenerator.validatedMnemonics, [result.value]);
  });

  test(
    'rejects malformed recovery material returned by the generator',
    () async {
      final keyGenerator = FakeWalletKeyGenerator()
        ..generatedMnemonic = 'not twelve words';
      final runtime = WalletRuntime(
        FakeWalletEngineFactory(const []),
        FakeWalletDirectoryManager(),
        WalletSecretStore(MemorySecureStore()),
        services,
      );
      addTearDown(runtime.dispose);
      final repository = WalletRepository(
        _FailingRegistrationStore(),
        runtime,
        keyGenerator,
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const SuccessfulLegacyWalletSeedPreflight(),
      );

      final result = await repository.generateMnemonic();

      expect(result, isA<AppFailureResult<String>>());
      expect(
        (result as AppFailureResult<String>).failure.code,
        'wallet_mnemonic_generation_invalid',
      );
      expect(keyGenerator.validatedMnemonics, isEmpty);
    },
  );

  test('commits metadata only after native provisioning succeeds', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final profileStore = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      PreferencesService(preferences),
    );
    final rawSecrets = MemorySecureStore();
    final engine = FakeWalletEngine();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.createFromMnemonic(
      mnemonic: '  MNEMONIC   WORDS  ',
      name: '  Main Wallet  ',
    );

    final profile = (result as AppSuccess<WalletProfile>).value;
    expect(profile.name, 'Main Wallet');
    expect(profile.state, WalletProfileState.ready);
    expect(engine.initializedMnemonic, 'mnemonic words');
    final registry =
        (await profileStore.read() as AppSuccess<WalletRegistry>).value;
    expect(registry.activeWalletId, walletId);
    expect(rawSecrets.values, hasLength(1));
  });

  test('rolls back native data when metadata commit fails', () async {
    final profileStore = _FailingRegistrationStore();
    final rawSecrets = MemorySecureStore();
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([FakeWalletEngine()]),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.createFromMnemonic(
      mnemonic: 'mnemonic words',
      name: 'Main Wallet',
    );

    expect(result, isA<AppFailureResult<WalletProfile>>());
    expect(rawSecrets.values, isEmpty);
    expect(directories.removed, [walletId]);
  });

  test(
    'preserves resources and quarantines runtime when commit is unknown',
    () async {
      final profileStore = _FailingRegistrationStore(outcomeUnknown: true);
      final rawSecrets = MemorySecureStore();
      final directories = FakeWalletDirectoryManager();
      final engine = FakeWalletEngine();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([engine]),
        directories,
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(runtime.dispose);
      final repository = WalletRepository(
        profileStore,
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const SuccessfulLegacyWalletSeedPreflight(),
      );

      final result = await repository.createFromMnemonic(
        mnemonic: 'mnemonic words',
        name: 'Main Wallet',
      );

      expect(result, isA<AppFailureResult<WalletProfile>>());
      expect(
        (result as AppFailureResult<WalletProfile>).failure.outcomeUnknown,
        isTrue,
      );
      expect(rawSecrets.values, hasLength(1));
      expect(directories.storageTokens, contains(walletId));
      expect(directories.removed, isEmpty);
      expect(engine.calls, contains('destroy'));
      expect(runtime.snapshot.phase, WalletRuntimePhase.disposed);
    },
  );

  test('stages uncertain credential writes for startup recovery', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final documents = MemoryWalletRegistryDocumentStore();
    final profileStore = WalletProfileStore(
      documents,
      PreferencesService(preferences),
    );
    final key = 'utexo_wallet_secret_v2.$walletId';
    final rawSecrets = MemorySecureStore()
      ..writeError = StateError('injected write response failure')
      ..commitWriteBeforeError = true
      ..readErrors[key] = StateError('injected verification failure');
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );
    addTearDown(repository.dispose);

    final result = await repository.createFromMnemonic(
      mnemonic: 'mnemonic words',
      name: 'Main Wallet',
    );
    final staged =
        (await profileStore.read() as AppSuccess<WalletRegistry>).value;

    expect(result, isA<AppFailureResult<WalletProfile>>());
    expect(
      (result as AppFailureResult<WalletProfile>).failure.outcomeUnknown,
      isTrue,
    );
    expect(staged.provisioningProfiles, hasLength(1));
    expect(rawSecrets.values, hasLength(1));
    expect(directories.storageTokens, contains(walletId));

    rawSecrets
      ..writeError = null
      ..readErrors.clear();
    expect(await repository.bootstrap(), isA<AppSuccess<WalletRegistry>>());
    final recovered =
        (await profileStore.read() as AppSuccess<WalletRegistry>).value;
    expect(recovered.profiles, isEmpty);
    expect(rawSecrets.values, isEmpty);
    expect(directories.storageTokens, isEmpty);
  });

  test('wallet ID collision cannot overwrite an existing wallet', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final profileStore = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      PreferencesService(preferences),
    );
    final now = DateTime.utc(2026, 8, 8);
    await profileStore.stageProvision(
      WalletProfile(
        id: walletId,
        name: 'Existing',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: storageToken,
      ),
    );
    await profileStore.commitProvision(walletId);
    final rawSecrets = MemorySecureStore();
    const existingSecret = WalletSecret(
      databasePassword: 'existing-password',
      mnemonic: 'existing mnemonic',
      storageToken: storageToken,
    );
    await WalletSecretStore(rawSecrets).write(walletId, existingSecret);
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.createFromMnemonic(
      mnemonic: 'mnemonic words',
      name: 'New Wallet',
    );

    expect(result, isA<AppFailureResult<WalletProfile>>());
    expect(
      (result as AppFailureResult<WalletProfile>).failure.code,
      'wallet_id_collision',
    );
    expect(directories.created, isEmpty);
    final retained =
        (await WalletSecretStore(
                  rawSecrets,
                ).read(walletId, expectedStorageToken: storageToken)
                as AppSuccess<WalletSecret>)
            .value;
    expect(retained.databasePassword, existingSecret.databasePassword);
  });

  test(
    'bootstrap stops before profile access when migration is required',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final documents = MemoryWalletRegistryDocumentStore()
        ..document = '{corrupt';
      final runtime = WalletRuntime(
        FakeWalletEngineFactory(const []),
        FakeWalletDirectoryManager(),
        WalletSecretStore(MemorySecureStore()),
        services,
      );
      addTearDown(runtime.dispose);
      final repository = WalletRepository(
        WalletProfileStore(documents, PreferencesService(preferences)),
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const FailingLegacyWalletSeedPreflight(),
      );

      final result = await repository.bootstrap();

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.code,
        'wallet_recovery_required',
      );
      expect(documents.readCount, 0);
    },
  );

  test('bootstrap rolls back an interrupted staged wallet', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final profileStore = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      PreferencesService(preferences),
    );
    final now = DateTime.utc(2026, 8, 8);
    await profileStore.stageProvision(
      WalletProfile(
        id: walletId,
        name: 'Interrupted',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: storageToken,
      ),
    );
    final rawSecrets = MemorySecureStore();
    await WalletSecretStore(rawSecrets).write(
      walletId,
      const WalletSecret(
        databasePassword: 'password',
        mnemonic: 'mnemonic words',
        storageToken: storageToken,
      ),
    );
    final directories = FakeWalletDirectoryManager()
      ..storageTokens[walletId] = storageToken;
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.bootstrap();

    final snapshot = (result as AppSuccess<WalletRegistry>).value;
    expect(snapshot.profiles, isEmpty);
    expect(rawSecrets.values, isEmpty);
    expect(directories.removed, [walletId]);
  });

  test(
    'bootstrap fails closed when current wallet resources are orphaned',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final rawSecrets = MemorySecureStore();
      await WalletSecretStore(rawSecrets).write(
        walletId,
        const WalletSecret(
          databasePassword: 'password',
          mnemonic: 'mnemonic words',
          storageToken: storageToken,
        ),
      );
      final runtime = WalletRuntime(
        FakeWalletEngineFactory(const []),
        FakeWalletDirectoryManager(),
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(runtime.dispose);
      final repository = WalletRepository(
        WalletProfileStore(
          MemoryWalletRegistryDocumentStore(),
          PreferencesService(preferences),
        ),
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const SuccessfulLegacyWalletSeedPreflight(),
      );

      final result = await repository.bootstrap();

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.code,
        'wallet_storage_recovery_required',
      );
      expect(rawSecrets.values, hasLength(1));
    },
  );

  test('selected metadata reopens a missing native runtime', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final profileStore = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      PreferencesService(preferences),
    );
    final now = DateTime.utc(2026, 8, 8);
    final profile = WalletProfile(
      id: walletId,
      name: 'Main',
      createdAt: now,
      updatedAt: now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.provisioning,
      storageToken: storageToken,
    );
    await profileStore.stageProvision(profile);
    await profileStore.commitProvision(walletId);
    final secrets = MemorySecureStore();
    await WalletSecretStore(secrets).write(
      walletId,
      const WalletSecret(
        databasePassword: 'password',
        mnemonic: 'mnemonic words',
        storageToken: storageToken,
      ),
    );
    final directories = FakeWalletDirectoryManager()
      ..storageTokens[walletId] = storageToken;
    final engine = FakeWalletEngine();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      directories,
      WalletSecretStore(secrets),
      services,
    );
    addTearDown(runtime.dispose);
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final result = await repository.switchWallet(walletId);

    expect(result, isA<AppSuccess<WalletRegistry>>());
    expect(runtime.snapshot.phase, WalletRuntimePhase.active);
    expect(engine.initializedMnemonic, isNull);
  });

  test(
    'resume reconciles a failed shutdown from durable active state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final profileStore = WalletProfileStore(
        MemoryWalletRegistryDocumentStore(),
        PreferencesService(preferences),
      );
      final active = FakeWalletEngine();
      final recovered = FakeWalletEngine();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([active, recovered]),
        FakeWalletDirectoryManager(),
        WalletSecretStore(MemorySecureStore()),
        services,
      );
      addTearDown(runtime.dispose);
      final repository = WalletRepository(
        profileStore,
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const SuccessfulLegacyWalletSeedPreflight(),
      );
      expect(
        await repository.createFromMnemonic(
          mnemonic: 'mnemonic words',
          name: 'Main Wallet',
        ),
        isA<AppSuccess<WalletProfile>>(),
      );
      active.shutdownError = StateError('injected shutdown failure');

      expect(await repository.suspend(), isA<AppFailureResult<void>>());
      final result = await repository.resume();

      expect(result, isA<AppSuccess<void>>());
      expect(active.calls, containsAllInOrder(['shutdown', 'destroy']));
      expect(recovered.initializedMnemonic, isNull);
      expect(runtime.snapshot.phase, WalletRuntimePhase.active);
      expect(runtime.snapshot.walletId, walletId);
    },
  );

  test(
    'quarantines a switched runtime when selection commit is unknown',
    () async {
      final now = DateTime.utc(2026, 8, 8);
      final firstProfile = WalletProfile(
        id: walletId,
        name: 'First',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.ready,
        storageToken: storageToken,
      );
      final secondProfile = WalletProfile(
        id: secondWalletId,
        name: 'Second',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.ready,
        storageToken: secondStorageToken,
      );
      final profiles = _FailingSwitchStore(
        WalletRegistry(
          profiles: [firstProfile, secondProfile],
          activeWalletId: walletId,
        ),
      );
      final firstEngine = FakeWalletEngine();
      final secondEngine = FakeWalletEngine();
      final secrets = MemorySecureStore();
      final directories = FakeWalletDirectoryManager();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([firstEngine, secondEngine]),
        directories,
        WalletSecretStore(secrets),
        services,
      );
      addTearDown(runtime.dispose);
      await runtime.provision(
        profile: WalletProfile(
          id: walletId,
          name: 'First',
          createdAt: now,
          updatedAt: now,
          environment: BlockchainEnvironment.regtest,
          state: WalletProfileState.provisioning,
          storageToken: storageToken,
        ),
        mnemonic: 'first mnemonic',
        databasePassword: 'first-password',
      );
      await WalletSecretStore(secrets).write(
        secondWalletId,
        const WalletSecret(
          databasePassword: 'second-password',
          mnemonic: 'second mnemonic',
          storageToken: secondStorageToken,
        ),
      );
      directories.storageTokens[secondWalletId] = secondStorageToken;
      final repository = WalletRepository(
        profiles,
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: walletId),
        services,
        const SuccessfulLegacyWalletSeedPreflight(),
      );

      final result = await repository.switchWallet(secondWalletId);

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.outcomeUnknown,
        isTrue,
      );
      expect(runtime.snapshot.phase, WalletRuntimePhase.disposed);
      expect(firstEngine.calls, contains('destroy'));
      expect(secondEngine.calls, contains('destroy'));
      expect(
        directories.storageTokens.keys,
        containsAll([walletId, secondWalletId]),
      );
      expect(secrets.values, hasLength(2));
    },
  );

  test('wallet reads stay ordered behind a requested wallet switch', () async {
    final now = DateTime.utc(2026, 8, 8);
    final firstProfile = WalletProfile(
      id: walletId,
      name: 'First',
      createdAt: now,
      updatedAt: now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.ready,
      storageToken: storageToken,
    );
    final secondProfile = WalletProfile(
      id: secondWalletId,
      name: 'Second',
      createdAt: now,
      updatedAt: now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.ready,
      storageToken: secondStorageToken,
    );
    final profiles = _GatedProfileStore(
      WalletRegistry(
        profiles: [firstProfile, secondProfile],
        activeWalletId: walletId,
      ),
    );
    final firstEngine = FakeWalletEngine();
    final secondEngine = FakeWalletEngine();
    final secrets = MemorySecureStore();
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([firstEngine, secondEngine]),
      directories,
      WalletSecretStore(secrets),
      services,
    );
    addTearDown(runtime.dispose);
    await runtime.provision(
      profile: WalletProfile(
        id: walletId,
        name: 'First',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: storageToken,
      ),
      mnemonic: 'first mnemonic',
      databasePassword: 'first-password',
    );
    await WalletSecretStore(secrets).write(
      secondWalletId,
      const WalletSecret(
        databasePassword: 'second-password',
        mnemonic: 'second mnemonic',
        storageToken: secondStorageToken,
      ),
    );
    directories.storageTokens[secondWalletId] = secondStorageToken;
    final repository = WalletRepository(
      profiles,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );

    final switching = repository.switchWallet(secondWalletId);
    await Future<void>.delayed(Duration.zero);
    final balance = repository.balance(WalletAsset.bitcoin);
    await Future<void>.delayed(Duration.zero);

    expect(firstEngine.calls, isNot(contains('balance')));
    expect(secondEngine.calls, isNot(contains('balance')));

    profiles.releaseRead();
    expect(await switching, isA<AppSuccess<WalletRegistry>>());
    expect(await balance, isA<AppSuccess<WalletBalance>>());
    expect(firstEngine.calls, isNot(contains('balance')));
    expect(secondEngine.calls, contains('balance'));
  });
}

final class _FailingRegistrationStore implements WalletProfilePersistence {
  _FailingRegistrationStore({this.outcomeUnknown = false});

  final bool outcomeUnknown;
  var snapshot = WalletRegistry(profiles: const [], activeWalletId: null);

  @override
  Future<AppResult<WalletRegistry>> read() async => AppResult.success(snapshot);

  @override
  Future<AppResult<WalletRegistry>> stageProvision(
    WalletProfile profile,
  ) async {
    snapshot = WalletRegistry(profiles: [profile], activeWalletId: null);
    return AppResult.success(snapshot);
  }

  @override
  Future<AppResult<WalletRegistry>> commitProvision(String walletId) async =>
      AppResult.failure(
        AppFailure(
          code: 'test_registration_failed',
          kind: AppFailureKind.storage,
          userMessage: 'Could not save wallet.',
          retryable: false,
          outcomeUnknown: outcomeUnknown,
        ),
      );

  @override
  Future<AppResult<WalletRegistry>> remove(String walletId) async {
    snapshot = WalletRegistry(profiles: const [], activeWalletId: null);
    return AppResult.success(snapshot);
  }

  @override
  Future<AppResult<WalletRegistry>> setActive(String walletId) async =>
      AppResult.success(snapshot);
}

final class _GatedProfileStore implements WalletProfilePersistence {
  _GatedProfileStore(this.snapshot);

  WalletRegistry snapshot;
  final _readGate = Completer<void>();

  void releaseRead() {
    if (!_readGate.isCompleted) _readGate.complete();
  }

  @override
  Future<AppResult<WalletRegistry>> read() async {
    await _readGate.future;
    return AppResult.success(snapshot);
  }

  @override
  Future<AppResult<WalletRegistry>> setActive(String walletId) async {
    snapshot = WalletRegistry(
      profiles: snapshot.profiles,
      activeWalletId: walletId,
    );
    return AppResult.success(snapshot);
  }

  @override
  Future<AppResult<WalletRegistry>> commitProvision(String walletId) =>
      throw UnimplementedError();

  @override
  Future<AppResult<WalletRegistry>> remove(String walletId) =>
      throw UnimplementedError();

  @override
  Future<AppResult<WalletRegistry>> stageProvision(WalletProfile profile) =>
      throw UnimplementedError();
}

final class _FailingSwitchStore implements WalletProfilePersistence {
  _FailingSwitchStore(this.snapshot);

  final WalletRegistry snapshot;

  @override
  Future<AppResult<WalletRegistry>> read() async => AppResult.success(snapshot);

  @override
  Future<AppResult<WalletRegistry>> setActive(String walletId) async =>
      AppResult.failure(
        const AppFailure(
          code: 'test_switch_commit_unknown',
          kind: AppFailureKind.storage,
          userMessage: 'Could not confirm wallet selection.',
          retryable: false,
          outcomeUnknown: true,
        ),
      );

  @override
  Future<AppResult<WalletRegistry>> commitProvision(String walletId) =>
      throw UnimplementedError();

  @override
  Future<AppResult<WalletRegistry>> remove(String walletId) =>
      throw UnimplementedError();

  @override
  Future<AppResult<WalletRegistry>> stageProvision(WalletProfile profile) =>
      throw UnimplementedError();
}
