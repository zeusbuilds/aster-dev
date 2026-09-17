import 'dart:async';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wallet_fakes.dart';

void main() {
  const firstId = '11111111111111111111111111111111';
  const secondId = '22222222222222222222222222222222';
  const firstToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const secondToken = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const services = WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
  );

  WalletProfile profile(
    String id, {
    WalletProfileState state = WalletProfileState.provisioning,
    BlockchainEnvironment environment = BlockchainEnvironment.regtest,
  }) => WalletProfile(
    id: id,
    name: 'Wallet',
    createdAt: DateTime.utc(2026, 8, 8),
    updatedAt: DateTime.utc(2026, 8, 8),
    environment: environment,
    state: state,
    storageToken: id == firstId ? firstToken : secondToken,
  );

  test('provision publishes engine only after native setup succeeds', () async {
    final rawSecrets = MemorySecureStore();
    final engine = FakeWalletEngine();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);

    final result = await runtime.provision(
      profile: profile(firstId),
      mnemonic: 'mnemonic words',
      databasePassword: 'password',
    );

    expect(result, isA<AppSuccess<void>>());
    expect(runtime.snapshot.phase, WalletRuntimePhase.active);
    expect(engine.provisionedMnemonic, 'mnemonic words');
    expect(rawSecrets.values, hasLength(1));
  });

  test(
    'restore opens a persisted store without provisioning it again',
    () async {
      final rawSecrets = MemorySecureStore();
      final directories = FakeWalletDirectoryManager()
        ..storageTokens[firstId] = firstToken;
      final secretStore = WalletSecretStore(rawSecrets);
      await secretStore.write(
        firstId,
        const WalletSecret(
          databasePassword: 'password',
          mnemonic: 'mnemonic words',
          storageToken: firstToken,
        ),
      );
      final engine = FakeWalletEngine();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([engine]),
        directories,
        secretStore,
        services,
      );
      addTearDown(runtime.dispose);

      final result = await runtime.restore(
        profile(firstId, state: WalletProfileState.ready),
      );

      expect(result, isA<AppSuccess<void>>());
      expect(engine.calls, <String>['openPersisted']);
      expect(engine.openedPassword, 'password');
      expect(engine.provisionedPassword, isNull);
      expect(engine.provisionedMnemonic, isNull);
      expect(directories.opened, [firstId]);
      expect(runtime.snapshot.phase, WalletRuntimePhase.active);
    },
  );

  test('network mismatch is rejected before provisioning resources', () async {
    final secrets = MemorySecureStore();
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      directories,
      WalletSecretStore(secrets),
      services,
    );
    addTearDown(runtime.dispose);

    final result = await runtime.provision(
      profile: profile(firstId, environment: BlockchainEnvironment.mainnet),
      mnemonic: 'mnemonic words',
      databasePassword: 'password',
    );

    expect(result, isA<AppFailureResult<void>>());
    expect(
      (result as AppFailureResult<void>).failure.code,
      'wallet_network_mismatch',
    );
    expect(directories.created, isEmpty);
    expect(secrets.values, isEmpty);
  });

  test('serializes regular operations ahead of suspension', () async {
    final rawSecrets = MemorySecureStore();
    final engine = FakeWalletEngine()..addressGate = Completer<void>();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);
    await runtime.provision(
      profile: profile(firstId),
      mnemonic: 'mnemonic words',
      databasePassword: 'password',
    );

    final address = runtime.run((wallet) => wallet.getBitcoinAddress());
    final suspend = runtime.suspend();
    await Future<void>.delayed(Duration.zero);
    expect(engine.calls, isNot(contains('shutdown')));

    engine.addressGate!.complete();
    expect(await address, isA<AppSuccess<String>>());
    expect(await suspend, isA<AppSuccess<void>>());
    expect(
      engine.calls.indexOf('address:end'),
      lessThan(engine.calls.indexOf('shutdown')),
    );
  });

  test('failed switch restores the previous wallet engine', () async {
    final rawSecrets = MemorySecureStore();
    final first = FakeWalletEngine();
    final failing = FakeWalletEngine()
      ..openPersistedError = StateError('target failed');
    final restored = FakeWalletEngine();
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([first, failing, restored]),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);
    await runtime.provision(
      profile: profile(firstId),
      mnemonic: 'first mnemonic',
      databasePassword: 'first-password',
    );
    await WalletSecretStore(rawSecrets).write(
      secondId,
      const WalletSecret(
        databasePassword: 'second-password',
        mnemonic: 'second mnemonic',
        storageToken: secondToken,
      ),
    );
    directories.storageTokens[secondId] = secondToken;

    final result = await runtime.switchTo(
      profile(secondId, state: WalletProfileState.ready),
    );

    expect(result, isA<AppFailureResult<void>>());
    expect(runtime.snapshot.phase, WalletRuntimePhase.active);
    expect(runtime.snapshot.walletId, firstId);
    expect(first.calls, contains('destroy'));
    expect(failing.calls, containsAllInOrder(['openPersisted', 'destroy']));
    expect(restored.calls, contains('openPersisted'));
    expect(restored.openedPassword, 'first-password');
    expect(restored.provisionedMnemonic, isNull);
  });

  test(
    'failed persisted reopen retries the same store through a fresh engine',
    () async {
      final rawSecrets = MemorySecureStore();
      final initial = FakeWalletEngine();
      final recovered = FakeWalletEngine();
      final directories = FakeWalletDirectoryManager();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([initial, recovered]),
        directories,
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(runtime.dispose);
      await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'mnemonic words',
        databasePassword: 'password',
      );
      await runtime.suspend();
      initial.openPersistedError = StateError('injected reopen failure');

      final result = await runtime.resume();

      expect(result, isA<AppSuccess<void>>());
      expect(
        initial.calls,
        containsAllInOrder(['shutdown', 'openPersisted', 'destroy']),
      );
      expect(recovered.openedPassword, 'password');
      expect(recovered.provisionedPassword, isNull);
      expect(recovered.provisionedMnemonic, isNull);
      expect(directories.opened, [firstId]);
      expect(runtime.snapshot.phase, WalletRuntimePhase.active);
    },
  );

  test(
    'unknown persisted reopen and failed recovery require reconciliation',
    () async {
      final initial = FakeWalletEngine();
      final recovery = FakeWalletEngine()
        ..openPersistedError = StateError('injected recovery failure');
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([initial, recovery]),
        FakeWalletDirectoryManager(),
        WalletSecretStore(MemorySecureStore()),
        services,
      );
      addTearDown(runtime.dispose);
      await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'mnemonic words',
        databasePassword: 'password',
      );
      await runtime.suspend();
      initial.openPersistedError = const AppFailureException(
        AppFailure(
          code: 'test_native_outcome_unknown',
          kind: AppFailureKind.timeout,
          userMessage: 'Test operation outcome is unknown.',
          retryable: false,
          outcomeUnknown: true,
        ),
      );

      final result = await runtime.resume();

      expect(result, isA<AppFailureResult<void>>());
      final failure = (result as AppFailureResult<void>).failure;
      expect(failure.code, 'wallet_resume_recovery_failed');
      expect(failure.requiresReconciliation, isTrue);
      expect(failure.outcomeUnknown, isTrue);
      expect(failure.retryable, isFalse);
      expect(failure.userMessage, contains('Restart'));
      final causes = failure.cause! as List<AppFailure>;
      expect(causes, hasLength(2));
      expect(causes.first.code, 'test_native_outcome_unknown');
      expect(causes.first.outcomeUnknown, isTrue);
      expect(causes.last.code, 'internal_state_violation');
      expect(causes.last.outcomeUnknown, isFalse);
      expect(initial.calls, containsAllInOrder(['openPersisted', 'destroy']));
      expect(recovery.calls, containsAllInOrder(['openPersisted', 'destroy']));
      expect(runtime.snapshot.phase, WalletRuntimePhase.failed);

      final repeated = await runtime.resume();
      expect(repeated, isA<AppFailureResult<void>>());
      expect((repeated as AppFailureResult<void>).failure, failure);
      expect(
        initial.calls.where((call) => call == 'openPersisted'),
        hasLength(1),
      );
      expect(
        recovery.calls.where((call) => call == 'openPersisted'),
        hasLength(1),
      );
    },
  );

  test('known recovery reconciliation prevents resume replay', () async {
    final initial = FakeWalletEngine();
    final recovery = FakeWalletEngine()
      ..openPersistedError = const AppFailureException(
        AppFailure(
          code: 'test_recovery_reconciliation_required',
          kind: AppFailureKind.storage,
          userMessage: 'Test recovery requires reconciliation.',
          retryable: false,
          requiresReconciliation: true,
        ),
      );
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([initial, recovery]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    addTearDown(runtime.dispose);
    await runtime.provision(
      profile: profile(firstId),
      mnemonic: 'mnemonic words',
      databasePassword: 'password',
    );
    await runtime.suspend();
    initial.openPersistedError = StateError('injected reopen failure');

    final result = await runtime.resume();

    expect(result, isA<AppFailureResult<void>>());
    final failure = (result as AppFailureResult<void>).failure;
    expect(failure.code, 'wallet_resume_recovery_failed');
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isFalse);
    expect(failure.retryable, isFalse);
    expect(failure.userMessage, contains('Restart'));
    final causes = failure.cause! as List<AppFailure>;
    expect(causes, hasLength(2));
    expect(causes.first.requiresReconciliation, isFalse);
    expect(causes.last.code, 'test_recovery_reconciliation_required');
    expect(causes.last.requiresReconciliation, isTrue);
    expect(initial.calls, containsAllInOrder(['openPersisted', 'destroy']));
    expect(recovery.calls, containsAllInOrder(['openPersisted', 'destroy']));
    expect(runtime.snapshot.phase, WalletRuntimePhase.failed);

    final repeated = await runtime.resume();
    expect(repeated, isA<AppFailureResult<void>>());
    expect((repeated as AppFailureResult<void>).failure, failure);
    expect(
      initial.calls.where((call) => call == 'openPersisted'),
      hasLength(1),
    );
    expect(
      recovery.calls.where((call) => call == 'openPersisted'),
      hasLength(1),
    );
  });

  test('resume cleanup preserves an unknown native outcome', () async {
    final initial = FakeWalletEngine();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([initial]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    addTearDown(() async {
      initial.destroyError = null;
      await runtime.dispose();
    });
    await runtime.provision(
      profile: profile(firstId),
      mnemonic: 'mnemonic words',
      databasePassword: 'password',
    );
    await runtime.suspend();
    initial
      ..openPersistedError = StateError('injected reopen failure')
      ..destroyError = const AppFailureException(
        AppFailure(
          code: 'test_native_outcome_unknown',
          kind: AppFailureKind.timeout,
          userMessage: 'Test operation outcome is unknown.',
          retryable: false,
          outcomeUnknown: true,
        ),
      );

    final result = await runtime.resume();

    expect(result, isA<AppFailureResult<void>>());
    final failure = (result as AppFailureResult<void>).failure;
    expect(failure.code, 'wallet_resume_cleanup_failed');
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isTrue);
    expect(failure.retryable, isFalse);
  });

  test('recovery phrase access requires an active native runtime', () async {
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([FakeWalletEngine()]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    addTearDown(runtime.dispose);
    await runtime.provision(
      profile: profile(firstId),
      mnemonic: 'mnemonic words',
      databasePassword: 'password',
    );
    await runtime.suspend();

    final result = await runtime.recoveryMnemonic(firstId);

    expect(result, isA<AppFailureResult<String>>());
    expect(
      (result as AppFailureResult<String>).failure.code,
      'wallet_not_ready',
    );
  });

  test('failed provision removes credentials and directory', () async {
    final rawSecrets = MemorySecureStore();
    final directories = FakeWalletDirectoryManager();
    final engine = FakeWalletEngine()
      ..provisionError = StateError('native init failed');
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);

    final result = await runtime.provision(
      profile: profile(firstId),
      mnemonic: 'mnemonic words',
      databasePassword: 'password',
    );

    expect(result, isA<AppFailureResult<void>>());
    expect(rawSecrets.values, isEmpty);
    expect(directories.removed, [firstId]);
  });

  test(
    'uncertain credential write preserves staged native resources',
    () async {
      final key = 'aster.wallet.secret.$firstId';
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
      addTearDown(() async {
        rawSecrets
          ..writeError = null
          ..readErrors.clear();
        await runtime.rollbackProvision(firstId, storageToken: firstToken);
        await runtime.dispose();
      });

      final result = await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'mnemonic words',
        databasePassword: 'password',
      );

      expect(result, isA<AppFailureResult<void>>());
      final failure = (result as AppFailureResult<void>).failure;
      expect(failure.requiresReconciliation, isTrue);
      expect(failure.outcomeUnknown, isTrue);
      expect(rawSecrets.values, hasLength(1));
      expect(directories.storageTokens, contains(firstId));
      expect(directories.removed, isEmpty);
    },
  );

  test(
    'uncertain directory cleanup after credential failure requires recovery',
    () async {
      final rawSecrets = MemorySecureStore()
        ..writeError = StateError('injected credential write failure');
      final directories = FakeWalletDirectoryManager()
        ..removeError = DurableStorageCommitException([
          StateError('injected ambiguous directory removal'),
        ]);
      final runtime = WalletRuntime(
        FakeWalletEngineFactory(const []),
        directories,
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(() async {
        rawSecrets.writeError = null;
        directories.removeError = null;
        await runtime.rollbackProvision(firstId, storageToken: firstToken);
        await runtime.dispose();
      });

      final result = await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'mnemonic words',
        databasePassword: 'password',
      );

      expect(result, isA<AppFailureResult<void>>());
      final failure = (result as AppFailureResult<void>).failure;
      expect(failure.code, 'wallet_provision_rollback_failed');
      expect(failure.requiresReconciliation, isTrue);
      expect(failure.outcomeUnknown, isTrue);
      expect(failure.retryable, isFalse);
      final causes = failure.cause! as List<AppFailure>;
      expect(causes, hasLength(2));
      expect(causes.first.outcomeUnknown, isFalse);
      expect(causes.last.code, 'durable_storage_commit_unknown');
      expect(causes.last.outcomeUnknown, isTrue);
      expect(rawSecrets.values, isEmpty);
      expect(directories.storageTokens, contains(firstId));
      expect(directories.removed, isEmpty);
    },
  );

  test('credential cleanup failure preserves its owned directory', () async {
    final rawSecrets = MemorySecureStore();
    final directories = FakeWalletDirectoryManager();
    final engine = FakeWalletEngine()
      ..provisionError = StateError('native init failed');
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(() async {
      rawSecrets.deleteError = null;
      await runtime.rollbackProvision(firstId, storageToken: firstToken);
      await runtime.dispose();
    });
    rawSecrets.deleteError = StateError('injected delete failure');

    final result = await runtime.provision(
      profile: profile(firstId),
      mnemonic: 'mnemonic words',
      databasePassword: 'password',
    );

    expect(result, isA<AppFailureResult<void>>());
    final failure = (result as AppFailureResult<void>).failure;
    expect(failure.code, 'wallet_provision_rollback_failed');
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isFalse);
    expect(failure.retryable, isFalse);
    expect(rawSecrets.values, hasLength(1));
    expect(directories.storageTokens, contains(firstId));
    expect(directories.removed, isEmpty);
  });

  test(
    'cleanly rolled-back provision returns the runtime to inactive',
    () async {
      final engine = FakeWalletEngine()
        ..provisionError = StateError('native init failed');
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([engine]),
        FakeWalletDirectoryManager(),
        WalletSecretStore(MemorySecureStore()),
        services,
      );
      addTearDown(runtime.dispose);
      final provision = await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'mnemonic words',
        databasePassword: 'password',
      );

      expect(provision, isA<AppFailureResult<void>>());
      expect(runtime.snapshot.phase, WalletRuntimePhase.inactive);

      final resume = await runtime.resume();

      expect(resume, isA<AppSuccess<void>>());
      expect(runtime.snapshot.phase, WalletRuntimePhase.inactive);
    },
  );

  test('suspension never promotes an unknown failed engine state', () async {
    final engine = FakeWalletEngine()
      ..provisionError = StateError('native init failed')
      ..destroyError = StateError('native destroy failed');
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    addTearDown(() async {
      engine.destroyError = null;
      await runtime.dispose();
    });
    final provision = await runtime.provision(
      profile: profile(firstId),
      mnemonic: 'mnemonic words',
      databasePassword: 'password',
    );

    final suspend = await runtime.suspend();

    expect(provision, isA<AppFailureResult<void>>());
    expect(suspend, isA<AppFailureResult<void>>());
    final provisionFailure = (provision as AppFailureResult<void>).failure;
    final suspendFailure = (suspend as AppFailureResult<void>).failure;
    expect(provisionFailure.code, 'wallet_provision_rollback_failed');
    expect(provisionFailure.requiresReconciliation, isTrue);
    expect(suspendFailure, provisionFailure);
    expect(runtime.snapshot.failure, provisionFailure);
    expect(runtime.snapshot.phase, WalletRuntimePhase.failed);
    expect(engine.calls, isNot(contains('shutdown')));
  });

  test(
    'failed native cleanup retains owned files until handle destruction works',
    () async {
      final rawSecrets = MemorySecureStore();
      final directories = FakeWalletDirectoryManager();
      final engine = FakeWalletEngine()
        ..provisionError = StateError('native init failed')
        ..destroyError = StateError('native destroy failed');
      final replacement = FakeWalletEngine();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([engine, replacement]),
        directories,
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(() async {
        engine.destroyError = null;
        await runtime.dispose();
      });

      final result = await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'mnemonic words',
        databasePassword: 'password',
      );

      expect(result, isA<AppFailureResult<void>>());
      final failure = (result as AppFailureResult<void>).failure;
      expect(failure.code, 'wallet_provision_rollback_failed');
      expect(failure.requiresReconciliation, isTrue);
      expect(failure.outcomeUnknown, isFalse);
      expect(rawSecrets.values, hasLength(1));
      expect(directories.removed, isEmpty);

      engine.destroyError = null;
      expect(
        await runtime.rollbackProvision(firstId, storageToken: firstToken),
        isA<AppSuccess<void>>(),
      );
      expect(rawSecrets.values, isEmpty);
      expect(directories.removed, [firstId]);
      expect(runtime.snapshot.phase, WalletRuntimePhase.inactive);

      expect(
        await runtime.provision(
          profile: profile(secondId),
          mnemonic: 'replacement mnemonic',
          databasePassword: 'replacement-password',
        ),
        isA<AppSuccess<void>>(),
      );
      expect(runtime.snapshot.walletId, secondId);
      expect(replacement.calls, contains('provision'));
    },
  );

  test('uncertain explicit rollback requires storage reconciliation', () async {
    final rawSecrets = MemorySecureStore();
    final directories = FakeWalletDirectoryManager();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([FakeWalletEngine()]),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(() async {
      directories.removeError = null;
      await runtime.rollbackProvision(firstId, storageToken: firstToken);
      await runtime.dispose();
    });
    expect(
      await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'mnemonic words',
        databasePassword: 'password',
      ),
      isA<AppSuccess<void>>(),
    );
    directories.removeError = DurableStorageCommitException([
      StateError('injected ambiguous directory removal'),
    ]);

    final result = await runtime.rollbackProvision(
      firstId,
      storageToken: firstToken,
    );

    expect(result, isA<AppFailureResult<void>>());
    final failure = (result as AppFailureResult<void>).failure;
    expect(failure.code, 'wallet_rollback_failed');
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isTrue);
    expect(failure.retryable, isFalse);
    final causes = failure.cause! as List<AppFailure>;
    expect(causes, hasLength(1));
    expect(causes.single.code, 'durable_storage_commit_unknown');
    expect(causes.single.outcomeUnknown, isTrue);
    expect(rawSecrets.values, isEmpty);
    expect(directories.storageTokens, contains(firstId));
    expect(directories.removed, isEmpty);
  });

  test(
    'never destroys the active wallet when its rollback secret is unreadable',
    () async {
      final rawSecrets = MemorySecureStore();
      final active = FakeWalletEngine();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([active]),
        FakeWalletDirectoryManager(),
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(runtime.dispose);
      await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'first mnemonic',
        databasePassword: 'first-password',
      );
      await WalletSecretStore(rawSecrets).write(
        secondId,
        const WalletSecret(
          databasePassword: 'second-password',
          mnemonic: 'second mnemonic',
          storageToken: secondToken,
        ),
      );
      rawSecrets.readErrors['aster.wallet.secret.$firstId'] = StateError(
        'secure storage unavailable',
      );

      final result = await runtime.switchTo(
        profile(secondId, state: WalletProfileState.ready),
      );

      expect(result, isA<AppFailureResult<void>>());
      expect(active.calls, isNot(contains('destroy')));
      expect(runtime.snapshot.phase, WalletRuntimePhase.active);
      expect(runtime.snapshot.walletId, firstId);
      rawSecrets.readErrors.clear();
    },
  );

  test(
    'attributes active-wallet reconciliation before a switch to its owner',
    () async {
      final rawSecrets = MemorySecureStore();
      final secretStore = WalletSecretStore(rawSecrets);
      final active = FakeWalletEngine();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([active]),
        FakeWalletDirectoryManager(),
        secretStore,
        services,
      );
      addTearDown(runtime.dispose);
      await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'first mnemonic',
        databasePassword: 'first-password',
      );
      expect(
        await secretStore.delete(firstId, storageToken: firstToken),
        isA<AppSuccess<void>>(),
      );
      expect(
        await secretStore.write(
          secondId,
          const WalletSecret(
            databasePassword: 'second-password',
            mnemonic: 'second mnemonic',
            storageToken: secondToken,
          ),
        ),
        isA<AppSuccess<void>>(),
      );

      final result = await runtime.switchTo(
        profile(secondId, state: WalletProfileState.ready),
      );

      expect(result, isA<AppFailureResult<void>>());
      final failure = (result as AppFailureResult<void>).failure;
      expect(failure.code, 'wallet_secret_missing');
      expect(failure.requiresReconciliation, isTrue);
      expect(runtime.snapshot.phase, WalletRuntimePhase.failed);
      expect(runtime.snapshot.walletId, firstId);
      expect(runtime.snapshot.failure, same(failure));
      expect(active.calls, isNot(contains('destroy')));

      final blocked = await runtime.sync();
      expect((blocked as AppFailureResult<void>).failure, same(failure));
    },
  );

  test(
    'directory collision never removes a directory it did not create',
    () async {
      final rawSecrets = MemorySecureStore();
      final directories = FakeWalletDirectoryManager()
        ..createError = const FileSystemException('directory exists');
      final runtime = WalletRuntime(
        FakeWalletEngineFactory(const []),
        directories,
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(runtime.dispose);

      final result = await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'mnemonic words',
        databasePassword: 'password',
      );

      expect(result, isA<AppFailureResult<void>>());
      expect(rawSecrets.values, isEmpty);
      expect(directories.removed, isEmpty);
    },
  );

  test(
    'credential collision rolls back only the newly created directory',
    () async {
      final rawSecrets = MemorySecureStore();
      const original = WalletSecret(
        databasePassword: 'original-password',
        mnemonic: 'original mnemonic',
        storageToken: secondToken,
      );
      await WalletSecretStore(rawSecrets).write(firstId, original);
      final directories = FakeWalletDirectoryManager();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory(const []),
        directories,
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(runtime.dispose);

      final result = await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'replacement mnemonic',
        databasePassword: 'replacement-password',
      );

      expect(result, isA<AppFailureResult<void>>());
      expect(directories.created, [firstId]);
      expect(directories.removed, [firstId]);
      final retained = (await WalletSecretStore(rawSecrets).read(
        firstId,
        expectedStorageToken: secondToken,
      ) as AppSuccess<WalletSecret>).value;
      expect(retained.databasePassword, original.databasePassword);
    },
  );

  test('storage audit verifies every registry ownership record', () async {
    final rawSecrets = MemorySecureStore();
    final directories = FakeWalletDirectoryManager()
      ..storageTokens[firstId] = firstToken;
    await WalletSecretStore(rawSecrets).write(
      firstId,
      const WalletSecret(
        databasePassword: 'password',
        mnemonic: 'mnemonic words',
        storageToken: firstToken,
      ),
    );
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      directories,
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);

    final result = await runtime.verifyStorage([
      profile(firstId, state: WalletProfileState.ready),
    ]);

    expect(result, isA<AppSuccess<void>>());
    expect(directories.opened, [firstId]);
  });

  test('storage audit preserves and reports orphaned resources', () async {
    final rawSecrets = MemorySecureStore();
    await WalletSecretStore(rawSecrets).write(
      firstId,
      const WalletSecret(
        databasePassword: 'password',
        mnemonic: 'mnemonic words',
        storageToken: firstToken,
      ),
    );
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      FakeWalletDirectoryManager(),
      WalletSecretStore(rawSecrets),
      services,
    );
    addTearDown(runtime.dispose);

    final result = await runtime.verifyStorage(const []);

    expect(result, isA<AppFailureResult<void>>());
    expect(
      (result as AppFailureResult<void>).failure.code,
      'wallet_storage_recovery_required',
    );
    expect(rawSecrets.values, hasLength(1));
  });

  test(
    'storage audit rejects a mismatched credential ownership token',
    () async {
      final rawSecrets = MemorySecureStore();
      final directories = FakeWalletDirectoryManager()
        ..storageTokens[firstId] = firstToken;
      await WalletSecretStore(rawSecrets).write(
        firstId,
        const WalletSecret(
          databasePassword: 'password',
          mnemonic: 'mnemonic words',
          storageToken: secondToken,
        ),
      );
      final runtime = WalletRuntime(
        FakeWalletEngineFactory(const []),
        directories,
        WalletSecretStore(rawSecrets),
        services,
      );
      addTearDown(runtime.dispose);

      final result = await runtime.verifyStorage([
        profile(firstId, state: WalletProfileState.ready),
      ]);

      expect(result, isA<AppFailureResult<void>>());
      expect(
        (result as AppFailureResult<void>).failure.code,
        'wallet_secret_ownership_unverified',
      );
    },
  );

  test(
    'reconciliation failure quarantines queued mutations but permits disposal',
    () async {
      final engine = FakeWalletEngine();
      final replacement = FakeWalletEngine();
      final directories = FakeWalletDirectoryManager();
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([engine, replacement]),
        directories,
        WalletSecretStore(MemorySecureStore()),
        services,
      );
      await runtime.provision(
        profile: profile(firstId),
        mnemonic: 'mnemonic words',
        databasePassword: 'password',
      );
      var secondOperationCalls = 0;
      const retained = AppFailure(
        code: 'test_reconciliation_required',
        kind: AppFailureKind.storage,
        userMessage: 'Test state requires reconciliation.',
        retryable: false,
        requiresReconciliation: true,
      );

      final first = runtime.run<void>(
        (_) => throw const AppFailureException(retained),
      );
      final queued = runtime.run<void>((_) async {
        secondOperationCalls += 1;
      });

      final firstResult = await first;
      final queuedResult = await queued;
      expect((firstResult as AppFailureResult<void>).failure, same(retained));
      expect((queuedResult as AppFailureResult<void>).failure, same(retained));
      expect(secondOperationCalls, 0);
      expect(runtime.snapshot.phase, WalletRuntimePhase.failed);
      expect(runtime.snapshot.failure, same(retained));

      final unrelatedRollback = await runtime.rollbackProvision(
        secondId,
        storageToken: secondToken,
      );
      expect(
        (unrelatedRollback as AppFailureResult<void>).failure,
        same(retained),
      );
      expect(directories.removed, isNot(contains(secondId)));

      final audit = await runtime.verifyStorage(const []);
      expect(audit, isA<AppFailureResult<void>>());
      expect(
        (audit as AppFailureResult<void>).failure.code,
        isNot(retained.code),
      );
      expect(runtime.snapshot.failure, same(retained));

      final switched = await runtime.switchTo(
        profile(secondId, state: WalletProfileState.ready),
      );
      expect((switched as AppFailureResult<void>).failure, same(retained));
      expect(replacement.calls, isEmpty);

      engine.destroyError = StateError('injected cleanup failure');
      final failedDisposal = await runtime.dispose();
      expect(failedDisposal, isA<AppFailureResult<void>>());
      expect(
        (failedDisposal as AppFailureResult<void>).failure.code,
        'wallet_native_cleanup_failed',
      );
      expect(runtime.snapshot.failure, same(retained));

      engine.destroyError = null;
      expect(await runtime.dispose(), isA<AppSuccess<void>>());
      expect(engine.calls, contains('destroy'));
      expect(runtime.snapshot.phase, WalletRuntimePhase.disposed);
    },
  );

  test('operations fail through AppResult once disposal starts', () async {
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );

    expect(await runtime.dispose(), isA<AppSuccess<void>>());
    final result = await runtime.sync();

    expect(result, isA<AppFailureResult<void>>());
    expect(
      (result as AppFailureResult<void>).failure.code,
      'wallet_runtime_disposed',
    );
    expect(result.failure.retryable, isFalse);
  });

  test('failed native destruction can be retried to completion', () async {
    final engine = FakeWalletEngine();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    await runtime.provision(
      profile: profile(firstId),
      mnemonic: 'mnemonic words',
      databasePassword: 'password',
    );
    engine.destroyError = StateError('injected cleanup failure');

    final failed = await runtime.dispose();
    expect(failed, isA<AppFailureResult<void>>());
    final failure = (failed as AppFailureResult<void>).failure;
    expect(failure.code, 'wallet_native_cleanup_failed');
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isFalse);
    expect(failure.retryable, isFalse);
    expect(runtime.snapshot.failure, same(failure));

    final blocked = await runtime.sync();
    expect((blocked as AppFailureResult<void>).failure, same(failure));

    engine.destroyError = null;
    final recovered = await runtime.dispose();

    expect(recovered, isA<AppSuccess<void>>());
    expect(runtime.snapshot.phase, WalletRuntimePhase.disposed);
    expect(engine.calls.where((call) => call == 'destroy'), hasLength(2));
  });
}
