import 'dart:convert';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final key = 'utexo_wallet_secret_v2.$firstId';
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
    raw.values['utexo_wallet_secret_v2.$firstId'] = '{not-json';

    final result = await store.read(firstId, expectedStorageToken: firstToken);

    expect(result, isA<AppFailureResult<WalletSecret>>());
    expect(
      (result as AppFailureResult<WalletSecret>).failure.code,
      'stored_data_invalid',
    );
    expect(raw.values, hasLength(1));
  });

  test('oversized secure records are rejected before JSON decoding', () async {
    final raw = MemorySecureStore();
    final store = WalletSecretStore(raw);
    raw.values['utexo_wallet_secret_v2.$firstId'] = 'x' * 4097;

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
      raw.values['utexo_wallet_secret_v2.$firstId'] = jsonEncode({
        'version': 2,
        'storageToken': firstToken,
      });

      final result = await store.delete(firstId, storageToken: firstToken);

      expect(result, isA<AppFailureResult<void>>());
      expect(
        (result as AppFailureResult<void>).failure.code,
        'stored_data_invalid',
      );
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
      final retained =
          (await store.read(firstId, expectedStorageToken: firstToken)
                  as AppSuccess<WalletSecret>)
              .value;

      expect(duplicate, isA<AppFailureResult<void>>());
      expect(
        (duplicate as AppFailureResult<void>).failure.code,
        'wallet_secret_already_exists',
      );
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
    expect(
      (result as AppFailureResult<void>).failure.code,
      'wallet_secret_ownership_unverified',
    );
    expect(raw.values, hasLength(1));
  });

  test(
    'unowned legacy credentials require recovery and cannot be deleted',
    () async {
      final raw = MemorySecureStore();
      raw.values['utexo_wallet_secret_v1.$firstId'] = jsonEncode({
        'version': 1,
        'databasePassword': 'legacy-password',
        'mnemonic': 'legacy mnemonic',
      });
      final store = WalletSecretStore(raw);

      final read = await store.read(firstId, expectedStorageToken: firstToken);
      final deletion = await store.delete(firstId, storageToken: firstToken);

      expect(read, isA<AppFailureResult<WalletSecret>>());
      expect(
        (read as AppFailureResult<WalletSecret>).failure.code,
        'wallet_recovery_required',
      );
      expect(deletion, isA<AppFailureResult<void>>());
      expect(raw.values, hasLength(1));
      final inventory = await store.walletIds();
      expect(inventory, isA<AppFailureResult<Set<String>>>());
      expect(
        (inventory as AppFailureResult<Set<String>>).failure.code,
        'wallet_recovery_required',
      );
    },
  );

  test(
    'profile mutations serialize without losing concurrent writes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final documents = MemoryWalletRegistryDocumentStore();
      final store = WalletProfileStore(
        documents,
        PreferencesService(preferences),
      );
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
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final createdAt = DateTime.utc(2026, 8, 8);
    final committedAt = DateTime.utc(2026, 8, 9);
    final store = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      PreferencesService(preferences),
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

  test('corrupt profile registry fails without overwriting evidence', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final documents = MemoryWalletRegistryDocumentStore()
      ..document = '{corrupt';
    final store = WalletProfileStore(
      documents,
      PreferencesService(preferences),
    );

    final result = await store.read();

    expect(result, isA<AppFailureResult<WalletRegistry>>());
    expect(documents.document, '{corrupt');
  });

  test(
    'wrongly typed profile fields are classified as stored corruption',
    () async {
      final encoded = jsonEncode({
        'version': 3,
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
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final documents = MemoryWalletRegistryDocumentStore()..document = encoded;
      final store = WalletProfileStore(
        documents,
        PreferencesService(preferences),
      );

      final result = await store.read();

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.code,
        'stored_data_invalid',
      );
      expect(documents.document, encoded);
    },
  );

  test(
    'non-UTC profile timestamps are rejected as stored corruption',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final documents = MemoryWalletRegistryDocumentStore()
        ..document = jsonEncode({
          'version': 3,
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
      final store = WalletProfileStore(
        documents,
        PreferencesService(preferences),
      );

      final result = await store.read();

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.code,
        'stored_data_invalid',
      );
    },
  );

  test('unowned v2 registry requires recovery and remains untouched', () async {
    final now = DateTime.utc(2026, 8, 8).toIso8601String();
    SharedPreferences.setMockInitialValues({
      StorageKeys.legacyWalletRegistryV2: jsonEncode({
        'version': 2,
        'activeWalletId': firstId,
        'profiles': [
          {
            'id': firstId,
            'name': 'Legacy',
            'createdAt': now,
            'updatedAt': now,
            'environment': 'regtest',
          },
        ],
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final documents = MemoryWalletRegistryDocumentStore();
    final store = WalletProfileStore(
      documents,
      PreferencesService(preferences),
    );

    final result = await store.read();

    expect(result, isA<AppFailureResult<WalletRegistry>>());
    expect(
      (result as AppFailureResult<WalletRegistry>).failure.code,
      'wallet_recovery_required',
    );
    expect(documents.document, isNull);
    expect(
      preferences.getString(StorageKeys.legacyWalletRegistryV2),
      isNotNull,
    );
  });

  test(
    'metadata-only v1 registry requires recovery and remains untouched',
    () async {
      const legacy = '{"version":1,"profiles":[]}';
      SharedPreferences.setMockInitialValues({
        StorageKeys.legacyWalletRegistryV1: legacy,
      });
      final preferences = await SharedPreferences.getInstance();
      final documents = MemoryWalletRegistryDocumentStore();
      final store = WalletProfileStore(
        documents,
        PreferencesService(preferences),
      );

      final result = await store.read();

      expect(result, isA<AppFailureResult<WalletRegistry>>());
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.code,
        'wallet_recovery_required',
      );
      expect(preferences.getString(StorageKeys.legacyWalletRegistryV1), legacy);
      expect(documents.document, isNull);
    },
  );

  test('a current journal never masks legacy wallet metadata', () async {
    const legacy = '{"version":1,"profiles":[]}';
    const current = '{"version":3,"activeWalletId":null,"profiles":[]}';
    SharedPreferences.setMockInitialValues({
      StorageKeys.legacyWalletRegistryV1: legacy,
    });
    final preferences = await SharedPreferences.getInstance();
    final documents = MemoryWalletRegistryDocumentStore()..document = current;
    final store = WalletProfileStore(
      documents,
      PreferencesService(preferences),
    );

    final result = await store.read();

    expect(result, isA<AppFailureResult<WalletRegistry>>());
    expect(
      (result as AppFailureResult<WalletRegistry>).failure.code,
      'wallet_recovery_required',
    );
    expect(preferences.getString(StorageKeys.legacyWalletRegistryV1), legacy);
    expect(documents.document, current);
  });

  test('wallet registry journal restores its newest flushed slot', () async {
    final root = await Directory.systemTemp.createTemp(
      'utexo-registry-journal-',
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
      'utexo-registry-journal-',
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
        'utexo-registry-journal-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = IoWalletRegistryDocumentStore(
        root.path,
        MemoryWalletStorageSecurity(),
      );
      await store.write('{"revision":1}');
      await store.write('{"revision":2}');
      await File(
        '${root.path}${Platform.pathSeparator}wallet_registry.b.json',
      ).writeAsString('{corrupt', flush: true);

      expect(await store.read(), '{"revision":1}');
    },
  );

  test(
    'wallet registry journal fails closed when every slot is corrupt',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'utexo-registry-journal-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = IoWalletRegistryDocumentStore(
        root.path,
        MemoryWalletStorageSecurity(),
      );
      await store.write('{"revision":1}');
      await store.write('{"revision":2}');
      await File(
        '${root.path}${Platform.pathSeparator}wallet_registry.a.json',
      ).writeAsString('{corrupt-a', flush: true);
      await File(
        '${root.path}${Platform.pathSeparator}wallet_registry.b.json',
      ).writeAsString('{corrupt-b', flush: true);

      await expectLater(
        store.read(),
        throwsA(isA<StoredDataCorruptionException>()),
      );
    },
  );

  test('failed journal replacement retains the previous valid slot', () async {
    final root = await Directory.systemTemp.createTemp(
      'utexo-registry-journal-',
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
      'utexo-registry-journal-',
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
    final root = await Directory.systemTemp.createTemp('utexo-wallet-test-');
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
      '$created${Platform.pathSeparator}.utexo-storage-owner',
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

  test(
    'legacy preflight rechecks an empty namespace on every startup',
    () async {
      final source = MemoryLegacyWalletSeedSource()
        ..values['access_token'] = 'must remain';
      final preflight = LegacyWalletSeedMigrationGuard(source);

      expect(await preflight.verify(), isA<AppSuccess<void>>());
      expect(source.values, {'access_token': 'must remain'});

      expect(await preflight.verify(), isA<AppSuccess<void>>());
      expect(source.readCount, 2);
    },
  );

  test(
    'legacy preflight detects a seed introduced after an empty check',
    () async {
      final source = MemoryLegacyWalletSeedSource();
      final preflight = LegacyWalletSeedMigrationGuard(source);

      expect(await preflight.verify(), isA<AppSuccess<void>>());
      source.values['wallet_seed_0123456789ABCDEF'] = 'secret words';
      final result = await preflight.verify();

      expect(result, isA<AppFailureResult<void>>());
      expect(
        (result as AppFailureResult<void>).failure.code,
        'wallet_recovery_required',
      );
    },
  );

  test('legacy preflight preserves seeds and requires recovery', () async {
    final source = MemoryLegacyWalletSeedSource()
      ..values['wallet_seed_0123456789ABCDEF'] = 'secret words';
    final preflight = LegacyWalletSeedMigrationGuard(source);

    final result = await preflight.verify();

    expect(result, isA<AppFailureResult<void>>());
    expect(
      (result as AppFailureResult<void>).failure.code,
      'wallet_recovery_required',
    );
    expect(source.values, {'wallet_seed_0123456789ABCDEF': 'secret words'});
  });

  test('legacy preflight reports a source read failure', () async {
    final source = MemoryLegacyWalletSeedSource()
      ..readError = StateError('injected read failure');
    final preflight = LegacyWalletSeedMigrationGuard(source);

    final result = await preflight.verify();

    expect(result, isA<AppFailureResult<void>>());
  });
}
