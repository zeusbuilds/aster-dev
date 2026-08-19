import 'dart:convert';
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

  test('secure credential record round-trips atomically', () async {
    final raw = MemorySecureStore();
    final store = WalletSecretStore(raw);
    const secret = WalletSecret(
      databasePassword: 'database-password',
      mnemonic: 'valid mnemonic words',
      storageToken: firstToken,
    );

    expect(await store.write(firstId, secret), isA<AppSuccess<void>>());
    final read = await store.read(firstId, expectedStorageToken: firstToken);

    expect(
      (read as AppSuccess<WalletSecret>).value.databasePassword,
      'database-password',
    );
    expect(read.value.mnemonic, 'valid mnemonic words');
    expect(raw.values, hasLength(1));
  });

  test(
    'reconciles a secure write that committed before reporting failure',
    () async {
      final raw = MemorySecureStore()
        ..writeError = StateError('injected write response failure')
        ..commitWriteBeforeError = true;
      final store = WalletSecretStore(raw);
      const secret = WalletSecret(
        databasePassword: 'database-password',
        mnemonic: 'valid mnemonic words',
        storageToken: firstToken,
      );

      final result = await store.write(firstId, secret);

      expect(result, isA<AppSuccess<void>>());
      expect(raw.values, hasLength(1));
    },
  );

  test('marks an unverifiable secure write outcome as unknown', () async {
    final key = 'aster.wallet.secret.$firstId';
    final raw = MemorySecureStore()
      ..writeError = StateError('injected write response failure')
      ..commitWriteBeforeError = true
      ..readErrors[key] = StateError('injected verification failure');
    final store = WalletSecretStore(raw);
    const secret = WalletSecret(
      databasePassword: 'database-password',
      mnemonic: 'valid mnemonic words',
      storageToken: firstToken,
    );

    final result = await store.write(firstId, secret);

    expect(result, isA<AppFailureResult<void>>());
    expect((result as AppFailureResult<void>).failure.outcomeUnknown, isTrue);
    expect(raw.values, hasLength(1));
  });

  test(
    'reconciles a secure deletion committed before its response fails',
    () async {
      final raw = MemorySecureStore();
      final store = WalletSecretStore(raw);
      const secret = WalletSecret(
        databasePassword: 'database-password',
        mnemonic: 'valid mnemonic words',
        storageToken: firstToken,
      );
      await store.write(firstId, secret);
      raw
        ..deleteError = StateError('injected delete response failure')
        ..commitDeleteBeforeError = true;

      final result = await store.delete(firstId, storageToken: firstToken);

      expect(result, isA<AppSuccess<void>>());
      expect(raw.values, isEmpty);
    },
  );

  test('corrupt secure record fails closed and is not deleted', () async {
    final raw = MemorySecureStore();
    final store = WalletSecretStore(raw);
    raw.values['aster.wallet.secret.$firstId'] = '{not-json';

    final result = await store.read(firstId, expectedStorageToken: firstToken);

    expect(result, isA<AppFailureResult<WalletSecret>>());
    expect(
      (result as AppFailureResult<WalletSecret>).failure.code,
      'stored_data_invalid',
    );
    expect(raw.values, hasLength(1));
  });

  test('credential store rejects every non-current schema', () async {
    final raw = MemorySecureStore();
    final store = WalletSecretStore(raw);
    final key = 'aster.wallet.secret.$firstId';
    raw.values[key] = jsonEncode({
      'version': 2,
      'databasePassword': 'database-password',
      'mnemonic': 'valid mnemonic words',
      'storageToken': firstToken,
    });

    final result = await store.read(firstId, expectedStorageToken: firstToken);

    expect(result, isA<AppFailureResult<WalletSecret>>());
    expect(
      (result as AppFailureResult<WalletSecret>).failure.code,
      'stored_data_invalid',
    );
    expect(raw.values[key], isNotNull);
  });

  test('oversized secure records are rejected before JSON decoding', () async {
    final raw = MemorySecureStore();
    final store = WalletSecretStore(raw);
    raw.values['aster.wallet.secret.$firstId'] = 'x' * 4097;

    final result = await store.read(firstId, expectedStorageToken: firstToken);

    expect(result, isA<AppFailureResult<WalletSecret>>());
    expect(
      (result as AppFailureResult<WalletSecret>).failure.code,
      'stored_data_invalid',
    );
    expect(raw.values, hasLength(1));
  });

  test(
    'malformed credential records cannot be deleted as owned data',
    () async {
      final raw = MemorySecureStore();
      final store = WalletSecretStore(raw);
      raw.values['aster.wallet.secret.$firstId'] = jsonEncode({
        'version': 1,
        'storageToken': firstToken,
      });

      final result = await store.delete(firstId, storageToken: firstToken);

      expect(result, isA<AppFailureResult<void>>());
      final failure = (result as AppFailureResult<void>).failure;
      expect(failure.code, 'stored_data_invalid');
      expect(failure.requiresReconciliation, isTrue);
      expect(failure.outcomeUnknown, isFalse);
      expect(raw.values, hasLength(1));
    },
  );

  test(
    'secure credential creation never overwrites an existing wallet',
    () async {
      final raw = MemorySecureStore();
      final store = WalletSecretStore(raw);
      const original = WalletSecret(
        databasePassword: 'original-password',
        mnemonic: 'original mnemonic',
        storageToken: firstToken,
      );
      const replacement = WalletSecret(
        databasePassword: 'replacement-password',
        mnemonic: 'replacement mnemonic',
        storageToken: firstToken,
      );
      await store.write(firstId, original);

      final duplicate = await store.write(firstId, replacement);
      final retained = (await store.read(
        firstId,
        expectedStorageToken: firstToken,
      ) as AppSuccess<WalletSecret>).value;

      expect(duplicate, isA<AppFailureResult<void>>());
      final failure = (duplicate as AppFailureResult<void>).failure;
      expect(failure.code, 'wallet_secret_already_exists');
      expect(failure.requiresReconciliation, isTrue);
      expect(failure.outcomeUnknown, isFalse);
      expect(retained.databasePassword, original.databasePassword);
      expect(retained.mnemonic, original.mnemonic);
    },
  );

  test('credential rollback refuses a mismatched ownership token', () async {
    final raw = MemorySecureStore();
    final store = WalletSecretStore(raw);
    const secret = WalletSecret(
      databasePassword: 'database-password',
      mnemonic: 'mnemonic words',
      storageToken: firstToken,
    );
    await store.write(firstId, secret);

    final result = await store.delete(firstId, storageToken: secondToken);

    expect(result, isA<AppFailureResult<void>>());
    final failure = (result as AppFailureResult<void>).failure;
    expect(failure.code, 'wallet_secret_ownership_unverified');
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isFalse);
    expect(raw.values, hasLength(1));
  });

  test(
    'credential inventory returns only valid Aster wallet records',
    () async {
      final raw = MemorySecureStore()..values['unrelated.key'] = 'retained';
      final store = WalletSecretStore(raw);
      await store.write(
        firstId,
        const WalletSecret(
          databasePassword: 'database-password',
          mnemonic: 'valid mnemonic words',
          storageToken: firstToken,
        ),
      );

      final result = await store.walletIds();

      expect(result, isA<AppSuccess<Set<String>>>());
      expect((result as AppSuccess<Set<String>>).value, {firstId});
      expect(raw.values['unrelated.key'], 'retained');
    },
  );

  test(
    'profile mutations serialize without losing concurrent writes',
    () async {
      final documents = MemoryWalletRegistryDocumentStore();
      final store = WalletProfileStore(documents);
      final now = DateTime.utc(2026, 8, 8);
      final first = WalletProfile(
        id: firstId,
        name: 'First',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: firstToken,
      );
      final second = WalletProfile(
        id: secondId,
        name: 'Second',
        createdAt: now,
        updatedAt: now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: secondToken,
      );

      await Future.wait([
        store.stageProvision(first),
        store.stageProvision(second),
      ]);
      await store.commitProvision(firstId);
      await store.commitProvision(secondId);
      final snapshot = (await store.read() as AppSuccess<WalletRegistry>).value;

      expect(snapshot.profiles.map((profile) => profile.id), [
        firstId,
        secondId,
      ]);
      expect(snapshot.activeWalletId, secondId);
    },
  );

  test('committing provisioning advances the profile update time', () async {
    final createdAt = DateTime.utc(2026, 8, 8);
    final committedAt = DateTime.utc(2026, 8, 9);
    final store = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      clock: () => committedAt,
    );
    await store.stageProvision(
      WalletProfile(
        id: firstId,
        name: 'First',
        createdAt: createdAt,
        updatedAt: createdAt,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: firstToken,
      ),
    );

    final result = await store.commitProvision(firstId);
    final profile = (result as AppSuccess<WalletRegistry>).value.activeProfile!;

    expect(profile.state, WalletProfileState.ready);
    expect(profile.updatedAt, committedAt);
  });

  test('profile state races return explicit redacted conflicts', () async {
    final store = WalletProfileStore(MemoryWalletRegistryDocumentStore());
    final now = DateTime.utc(2026, 8, 8);
    final profile = WalletProfile(
      id: firstId,
      name: 'First',
      createdAt: now,
      updatedAt: now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.provisioning,
      storageToken: firstToken,
    );

    expect(
      await store.stageProvision(profile),
      isA<AppSuccess<WalletRegistry>>(),
    );
    final duplicate = await store.stageProvision(profile);
    final missingCommit = await store.commitProvision(secondId);
    final missingActivation = await store.setActive(secondId);

    expect(
      (duplicate as AppFailureResult<WalletRegistry>).failure.code,
      'wallet_profile_already_exists',
    );
    expect(duplicate.failure.retryable, isTrue);
    expect(
      (missingCommit as AppFailureResult<WalletRegistry>).failure.code,
      'wallet_profile_stage_missing',
    );
    expect(missingCommit.failure.retryable, isTrue);
    expect(
      (missingActivation as AppFailureResult<WalletRegistry>).failure.code,
      'wallet_profile_activation_conflict',
    );
    expect(missingActivation.failure.retryable, isTrue);
    expect(missingActivation.failure.cause, isNull);
    expect(missingActivation.failure.userMessage, isNot(contains(secondId)));
  });

  test('profile rollback removal is idempotent', () async {
    final store = WalletProfileStore(MemoryWalletRegistryDocumentStore());

    final result = await store.remove(firstId);

    expect(result, isA<AppSuccess<WalletRegistry>>());
    final registry = (result as AppSuccess<WalletRegistry>).value;
    expect(registry.profiles, isEmpty);
    expect(registry.activeWalletId, isNull);
  });

  test('corrupt profile registry fails without overwriting evidence', () async {
    final documents = MemoryWalletRegistryDocumentStore()
      ..document = '{corrupt';
    final store = WalletProfileStore(documents);

    final result = await store.read();

    expect(result, isA<AppFailureResult<WalletRegistry>>());
    expect(documents.document, '{corrupt');
  });

  test('profile store rejects every non-current schema', () async {
    final encoded = jsonEncode({
      'version': 2,
      'activeWalletId': null,
      'profiles': <Object?>[],
    });
    final documents = MemoryWalletRegistryDocumentStore()..document = encoded;
    final store = WalletProfileStore(documents);

    final result = await store.read();

    expect(result, isA<AppFailureResult<WalletRegistry>>());
    expect(
      (result as AppFailureResult<WalletRegistry>).failure.code,
      'stored_data_invalid',
    );
    expect(documents.document, encoded);
  });

  test(
    'wrongly typed profile fields are classified as stored corruption',
    () async {
      final encoded = jsonEncode({
        'version': 1,
        'activeWalletId': firstId,
        'profiles': [
          {
            'id': 42,
            'name': 'Wallet',
            'createdAt': '2026-08-08T00:00:00.000Z',
            'updatedAt': '2026-08-08T00:00:00.000Z',
            'environment': 'regtest',
            'state': 'ready',
          },
        ],
      });
      final documents = MemoryWalletRegistryDocumentStore()..document = encoded;
      final store = WalletProfileStore(documents);

      final result = await store.read();

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      final failure = (result as AppFailureResult<WalletRegistry>).failure;
      expect(failure.code, 'stored_data_invalid');
      expect(failure.requiresReconciliation, isTrue);
      expect(failure.outcomeUnknown, isFalse);
      expect(documents.document, encoded);
    },
  );

  test(
    'non-UTC profile timestamps are rejected as stored corruption',
    () async {
      final documents = MemoryWalletRegistryDocumentStore()
        ..document = jsonEncode({
          'version': 1,
          'activeWalletId': firstId,
          'profiles': [
            {
              'id': firstId,
              'name': 'Wallet',
              'createdAt': '2026-08-08T00:00:00.000',
              'updatedAt': '2026-08-08T00:00:00.000',
              'environment': 'regtest',
              'state': 'ready',
              'storageToken': firstToken,
            },
          ],
        });
      final store = WalletProfileStore(documents);

      final result = await store.read();

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.code,
        'stored_data_invalid',
      );
    },
  );

  test('wallet registry journal restores its newest flushed slot', () async {
    final root = await Directory.systemTemp.createTemp(
      'aster-registry-journal-',
    );
    addTearDown(() => root.delete(recursive: true));
    final security = MemoryWalletStorageSecurity();
    final store = IoWalletRegistryDocumentStore(root.path, security);

    await store.write('{"revision":1}');
    await store.write('{"revision":2}');

    expect(
      await IoWalletRegistryDocumentStore(root.path, security).read(),
      '{"revision":2}',
    );
  });

  test('wallet registry journal retries one uncertain atomic commit', () async {
    final root = await Directory.systemTemp.createTemp(
      'aster-registry-journal-',
    );
    addTearDown(() => root.delete(recursive: true));
    final security = MemoryWalletStorageSecurity()
      ..replaceFailuresRemaining = 1;
    final store = IoWalletRegistryDocumentStore(root.path, security);

    await store.write('{"revision":1}');

    expect(security.replacedFiles, hasLength(2));
    expect(await store.read(), '{"revision":1}');
  });

  test(
    'wallet registry journal falls back from a corrupt newest slot',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aster-registry-journal-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = IoWalletRegistryDocumentStore(
        root.path,
        MemoryWalletStorageSecurity(),
      );
      await store.write('{"revision":1}');
      await store.write('{"revision":2}');
      await File('${root.path}${Platform.pathSeparator}wallet_registry.b.json')
          .writeAsString('{corrupt', flush: true);

      expect(await store.read(), '{"revision":1}');
    },
  );

  test(
    'wallet registry journal fails closed when every slot is corrupt',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aster-registry-journal-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = IoWalletRegistryDocumentStore(
        root.path,
        MemoryWalletStorageSecurity(),
      );
      await store.write('{"revision":1}');
      await store.write('{"revision":2}');
      await File('${root.path}${Platform.pathSeparator}wallet_registry.a.json')
          .writeAsString('{corrupt-a', flush: true);
      await File('${root.path}${Platform.pathSeparator}wallet_registry.b.json')
          .writeAsString('{corrupt-b', flush: true);

      await expectLater(
        store.read(),
        throwsA(isA<StoredDataCorruptionException>()),
      );
    },
  );

  test('failed journal replacement retains the previous valid slot', () async {
    final root = await Directory.systemTemp.createTemp(
      'aster-registry-journal-',
    );
    addTearDown(() => root.delete(recursive: true));
    final store = IoWalletRegistryDocumentStore(
      root.path,
      MemoryWalletStorageSecurity(),
    );
    await store.write('{"revision":1}');
    await Directory(
      '${root.path}${Platform.pathSeparator}wallet_registry.b.json',
    ).create();

    await expectLater(
      store.write('{"revision":2}'),
      throwsA(isA<DurableStorageCommitException>()),
    );

    expect(await store.read(), '{"revision":1}');
  });

  test('orphan journal temporary files never become committed data', () async {
    final root = await Directory.systemTemp.createTemp(
      'aster-registry-journal-',
    );
    addTearDown(() => root.delete(recursive: true));
    await File(
      '${root.path}${Platform.pathSeparator}wallet_registry.a.json.tmp',
    ).writeAsString('partially-written', flush: true);

    expect(
      await IoWalletRegistryDocumentStore(
        root.path,
        MemoryWalletStorageSecurity(),
      ).read(),
      isNull,
    );
  });

  test('wallet directories distinguish create, open, and collision', () async {
    final root = await Directory.systemTemp.createTemp('aster-wallet-test-');
    addTearDown(() => root.delete(recursive: true));
    final security = MemoryWalletStorageSecurity();
    final manager = IoWalletDirectoryManager(root.path, security);

    final created = await manager.create(firstId, storageToken: firstToken);

    expect(await Directory(created).exists(), isTrue);
    expect(security.preparedRoots, [root.path]);
    expect(security.createdDirectories, [created]);
    expect(await manager.open(firstId, storageToken: firstToken), created);
    expect(security.verifiedDirectories, [root.path, created]);
    expect(security.verifiedFiles, [
      '$created${Platform.pathSeparator}.aster-storage-owner',
    ]);
    await expectLater(
      manager.open(firstId, storageToken: secondToken),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      manager.remove(firstId, storageToken: secondToken),
      throwsA(isA<FileSystemException>()),
    );
    expect(await Directory(created).exists(), isTrue);
    await expectLater(
      manager.create(firstId, storageToken: firstToken),
      throwsA(isA<FileSystemException>()),
    );
    await manager.remove(firstId, storageToken: firstToken);
    await expectLater(
      manager.open(firstId, storageToken: firstToken),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('wallet directory preserves an ambiguous marker rollback', () async {
    final root = await Directory.systemTemp.createTemp('aster-wallet-test-');
    addTearDown(() => root.delete(recursive: true));
    final security = MemoryWalletStorageSecurity()
      ..replaceFailuresRemaining = 1;
    final cleanupError = FileSystemException(
      'Injected directory rollback failure.',
    );
    final manager = IoWalletDirectoryManager(
      root.path,
      security,
      deleteDirectory: (_) async => throw cleanupError,
    );

    await expectLater(
      manager.create(firstId, storageToken: firstToken),
      throwsA(
        isA<DurableStorageCommitException>()
            .having((error) => error.causes, 'causes', hasLength(2))
            .having(
              (error) => error.causes.first,
              'marker write failure',
              isA<FileSystemException>(),
            )
            .having(
              (error) => error.causes.last,
              'directory rollback failure',
              same(cleanupError),
            ),
      ),
    );

    expect(
      await Directory('${root.path}${Platform.pathSeparator}$firstId').exists(),
      isTrue,
    );
  });
}
