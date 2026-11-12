import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart'
    show RlnOperationTimeoutException;

import '../../support/wallet_fakes.dart';

const _first = '11111111111111111111111111111111';
const _second = '22222222222222222222222222222222';
const _third = '33333333333333333333333333333333';
const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
);

void main() {
  test(
    'audit deadline retry drains and reopens owner before any deletion stage',
    () async {
      final h = await _Harness.create([_first]);
      h.engines.first.deletionAuditError = const RlnOperationTimeoutException(
        operation: 'rlnRefreshTransfers',
        timeout: Duration(minutes: 2),
      );
      expect(
        await h.repository.deleteWallet(_first),
        isA<AppFailureResult<WalletRegistry>>(),
      );
      expect(h.engines.first.requiresPaymentReopen, isTrue);
      expect(h.secure.values, hasLength(1));
      expect(
        (await h.profiles.read() as AppSuccess<WalletRegistry>)
            .value
            .deletingProfiles,
        isEmpty,
      );
      h.engines.first.deletionAuditError = null;
      h.engines.first.openPersistedGate = Completer<void>();
      final retry = h.repository.deleteWallet(_first);
      await Future<void>.delayed(Duration.zero);
      expect(
        h.engines.first.calls.where((call) => call == 'openPersisted'),
        hasLength(2),
      );
      expect(h.secure.values, hasLength(1));
      expect(
        (await h.profiles.read() as AppSuccess<WalletRegistry>)
            .value
            .deletingProfiles,
        isEmpty,
      );
      h.engines.first.openPersistedGate!.complete();
      expect(await retry, isA<AppSuccess<WalletRegistry>>());
      expect(h.secure.values, isEmpty);
    },
  );
  test(
    'retry re-flushes native removal after child deletion succeeded',
    () async {
      final root = await Directory.systemTemp.createTemp('aster-delete-fsync-');
      addTearDown(() => root.delete(recursive: true));
      final security = MemoryWalletStorageSecurity();
      final directories = IoWalletDirectoryManager(
        '${root.path}/wallets',
        security,
      );
      await directories.create(_first, storageToken: _first);
      await directories.removeDeletedWallet(_first, storageToken: _first);
      expect(security.flushedDirectories, hasLength(2));
      security.flushError = const FileSystemException('fsync failed');
      await expectLater(
        directories.removeDeletedWallet(_first, storageToken: _first),
        throwsA(isA<FileSystemException>()),
      );
      security.flushError = null;
      await directories.removeDeletedWallet(_first, storageToken: _first);
      expect(security.flushedDirectories, hasLength(4));
    },
  );
  test(
    'unresolved exact payment evidence cannot be erased by deletion',
    () async {
      final h = await _Harness.create([_first]);
      final at = DateTime.utc(2026, 10, 26).toIso8601String();
      h.journals.documents[_first] = jsonEncode({
        'version': 1,
        'id': _third,
        'walletId': _first,
        'storageToken': _first,
        'network': 'regtest',
        'submittedAt': at,
        'phase': 'submitting',
        'command': {
          'asset': 'btc',
          'precision': 8,
          'destination': 'test-destination',
          'amount': 1,
          'feeTarget': 6,
          'feeRate': 1,
          'feeObservedAt': at,
          'feeSource': 'networkEstimate',
          'rgbRecipientType': null,
          'witnessBitcoinAmountSats': null,
        },
        'result': null,
      });
      final result = await h.repository.deleteWallet(_first);
      expect(_failure(result).code, 'payment_submission_unresolved');
      expect(h.secure.values, hasLength(1));
      expect(h.directories.removed, isEmpty);
      expect(h.engines.first.calls, isNot(contains('deletionAudit')));
      expect(h.journals.documents[_first], isNotNull);
    },
  );
  test(
    'last deletion empties registry and native owner without disposing it',
    () async {
      final h = await _Harness.create([_first]);
      final result = await h.repository.deleteWallet(_first);
      expect(result, isA<AppSuccess<WalletRegistry>>());
      expect((result as AppSuccess<WalletRegistry>).value.profiles, isEmpty);
      expect(h.secure.values, isEmpty);
      expect(h.directories.storageTokens, isEmpty);
      expect(h.runtime.activeProfile, isNull);
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.inactive);
      expect(
        h.engines.first.calls,
        containsAllInOrder(['deletionAudit', 'destroy']),
      );
      expect(h.engines.first.calls, isNot(contains('sync')));
      // The process-owned runtime must remain usable for a fresh wallet.
      final created = await h.repository.createFromMnemonic(
        mnemonic: FakeWalletKeyGenerator().generatedMnemonic,
        name: 'Fresh',
      );
      expect(created, isA<AppSuccess<WalletRegistry>>());
      expect(h.runtime.activeProfile?.id, _third);
    },
  );

  test(
    'active deletion selects first remaining wallet and preserves its data',
    () async {
      final h = await _Harness.create([
        _first,
        _second,
        _third,
      ], active: _second);
      final beforeSecrets = Map.of(h.secure.values);
      final beforeDirectories = Map.of(h.directories.storageTokens);
      final result = await h.repository.deleteWallet(_second);
      final registry = (result as AppSuccess<WalletRegistry>).value;
      expect(registry.activeWalletId, _first);
      expect(registry.readyProfiles.map((p) => p.id), [_first, _third]);
      expect(h.runtime.activeProfile?.id, _first);
      expect(h.secure.values.keys, hasLength(2));
      for (final entry in h.secure.values.entries) {
        expect(entry.value, beforeSecrets[entry.key]);
      }
      expect(h.directories.storageTokens, {
        _first: beforeDirectories[_first],
        _third: beforeDirectories[_third],
      });
      expect(h.engines.first.calls.where((c) => c == 'destroy'), hasLength(1));
    },
  );

  test('inactive or missing targets cannot delete another wallet', () async {
    final h = await _Harness.create([_first, _second]);
    expect(
      _failure(await h.repository.deleteWallet(_second)).code,
      'wallet_deletion_select_wallet',
    );
    expect(
      _failure(await h.repository.deleteWallet(_third)).code,
      'wallet_profile_not_found',
    );
    expect(h.secure.values, hasLength(2));
    expect(h.directories.removed, isEmpty);
    expect(h.engines.first.calls, isNot(contains('deletionAudit')));
  });

  test(
    'RGB holdings or pending requests reject deletion before any write',
    () async {
      final h = await _Harness.create([_first]);
      h.engines.first.protectedRgbState = true;
      final writes = h.documents.writeCount;
      expect(
        _failure(await h.repository.deleteWallet(_first)).code,
        'wallet_deletion_rgb_state_present',
      );
      expect(h.documents.writeCount, writes);
      expect(h.secure.values, hasLength(1));
      expect(h.engines.first.calls, isNot(contains('destroy')));
    },
  );

  test(
    'unavailable native audit fails closed with wallet data intact',
    () async {
      final h = await _Harness.create([_first]);
      h.engines.first.deletionAuditError = const FileSystemException(
        'unavailable',
      );
      expect(
        await h.repository.deleteWallet(_first),
        isA<AppFailureResult<WalletRegistry>>(),
      );
      expect(
        (await h.profiles.read() as AppSuccess<WalletRegistry>)
            .value
            .readyProfiles,
        hasLength(1),
      );
      expect(h.secure.values, hasLength(1));
      expect(h.directories.removed, isEmpty);
    },
  );

  test(
    'corrupt payment evidence rejects deletion before native audit',
    () async {
      final h = await _Harness.create([_first]);
      h.journals.documents[_first] = 'corrupt';
      expect(
        await h.repository.deleteWallet(_first),
        isA<AppFailureResult<WalletRegistry>>(),
      );
      expect(h.engines.first.calls, isNot(contains('deletionAudit')));
      expect(h.secure.values, hasLength(1));
    },
  );

  test(
    'native close failure retains credentials and durable delete authority',
    () async {
      final h = await _Harness.create([_first, _second]);
      h.engines.first.destroyError = StateError('close failed');
      expect(
        _failure(await h.repository.deleteWallet(_first))
            .requiresReconciliation,
        isTrue,
      );
      final registry =
          (await h.profiles.read() as AppSuccess<WalletRegistry>).value;
      expect(registry.deletingProfiles.single.id, _first);
      expect(registry.activeWalletId, _second);
      expect(h.secure.values, hasLength(2));
      expect(h.directories.removed, isEmpty);
      h.engines.first.destroyError = null;
      expect(await h.repository.bootstrap(), isA<AppSuccess<WalletRegistry>>());
      expect(h.runtime.activeProfile?.id, _second);
      expect(h.secure.values, hasLength(1));
    },
  );

  test(
    'secret erase failure leaves a durable marker and resumes after restart',
    () async {
      final h = await _Harness.create([_first, _second]);
      h.secure.deleteError = const FileSystemException('locked');
      expect(
        await h.repository.deleteWallet(_first),
        isA<AppFailureResult<WalletRegistry>>(),
      );
      expect(h.directories.removed, isEmpty);
      expect(
        (await h.profiles.read() as AppSuccess<WalletRegistry>)
            .value
            .deletingProfiles,
        hasLength(1),
      );
      h.secure.deleteError = null;
      h.engines.first.openPersistedError = TimeoutException(
        'temporary open failure',
      );
      final restarted = h.restart();
      final restartFailure = _failure(await restarted.bootstrap());
      expect(restartFailure.code, 'wallet_deleted_activation_failed');
      expect(restartFailure.requiresReconciliation, isTrue);
      expect(h.secure.values, hasLength(1));
      expect(h.directories.storageTokens.keys, [_second]);
      expect(
        await restarted.recoverWalletDeletion(),
        isA<AppSuccess<WalletRegistry>>(),
      );
      expect(h.runtime.activeProfile?.id, _second);
    },
  );

  test(
    'partial directory cleanup never restores deleted credentials',
    () async {
      final h = await _Harness.create([_first]);
      h.directories.removeError = const FileSystemException('interrupted');
      expect(
        await h.repository.deleteWallet(_first),
        isA<AppFailureResult<WalletRegistry>>(),
      );
      expect(h.secure.values, isEmpty);
      expect(
        (await h.profiles.read() as AppSuccess<WalletRegistry>)
            .value
            .deletingProfiles,
        hasLength(1),
      );
      h.directories.removeError = null;
      expect(await h.repository.bootstrap(), isA<AppSuccess<WalletRegistry>>());
      expect(h.directories.storageTokens, isEmpty);
    },
  );

  test(
    'scoped cleanup failure retains deletion marker until all metadata removed',
    () async {
      final h = await _Harness.create([_first, _second]);
      h.journals.removeWalletError = const FileSystemException(
        'metadata locked',
      );
      expect(
        await h.repository.deleteWallet(_first),
        isA<AppFailureResult<WalletRegistry>>(),
      );
      expect(
        (await h.profiles.read() as AppSuccess<WalletRegistry>)
            .value
            .deletingProfiles,
        hasLength(1),
      );
      h.journals.removeWalletError = null;
      expect(await h.repository.bootstrap(), isA<AppSuccess<WalletRegistry>>());
      expect(h.directories.storageTokens.keys, [_second]);
    },
  );

  test(
    'queue serializes deletion audit and drops a duplicate delete safely',
    () async {
      final h = await _Harness.create([_first]);
      h.engines.first.deletionAuditGate = Completer<void>();
      final firstDelete = h.repository.deleteWallet(_first);
      await Future<void>.delayed(Duration.zero);
      final duplicate = h.repository.deleteWallet(_first);
      await Future<void>.delayed(Duration.zero);
      expect(h.secure.values, hasLength(1));
      expect(
        h.engines.first.calls.where((c) => c == 'deletionAudit'),
        hasLength(1),
      );
      h.engines.first.deletionAuditGate!.complete();
      expect(await firstDelete, isA<AppSuccess<WalletRegistry>>());
      expect(_failure(await duplicate).code, 'wallet_profile_not_found');
      expect(h.engines.first.calls.where((c) => c == 'destroy'), hasLength(1));
    },
  );

  test('staging storage failure performs no irreversible cleanup', () async {
    final h = await _Harness.create([_first]);
    h.documents.writeError = const FileSystemException('disk full');
    expect(
      await h.repository.deleteWallet(_first),
      isA<AppFailureResult<WalletRegistry>>(),
    );
    expect(h.secure.values, hasLength(1));
    expect(h.directories.removed, isEmpty);
    // An ambiguous durable write closes the owner but preserves a reusable
    // deletion fence until the registry plus resources have been audited.
    expect(h.runtime.hasDeletionRecovery, isTrue);
    h.documents.writeError = null;
    expect(
      await h.repository.recoverWalletDeletion(),
      isA<AppSuccess<WalletRegistry>>(),
    );
    expect(h.runtime.activeProfile?.id, _first);
    expect(h.secure.values, hasLength(1));
  });

  test(
    'native tombstone resumes after recursive delete removed ownership marker',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aster-delete-native-',
      );
      addTearDown(() => root.delete(recursive: true));
      final security = MemoryWalletStorageSecurity();
      const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      var interrupt = true;
      final directories = IoWalletDirectoryManager(
        '${root.path}/wallets',
        security,
        deleteDirectory: (directory) async {
          if (interrupt) {
            interrupt = false;
            await File('${directory.path}/.aster-storage-owner').delete();
            throw const FileSystemException('power loss');
          }
          await directory.delete(recursive: true);
        },
      );
      final path = await directories.create(_first, storageToken: token);
      await File('$path/database').writeAsString('test-only');
      await expectLater(
        directories.removeDeletedWallet(_first, storageToken: token),
        throwsA(isA<FileSystemException>()),
      );
      expect(await Directory(path).exists(), isFalse);
      await directories.removeDeletedWallet(_first, storageToken: token);
      expect(await directories.walletIds(), isEmpty);
    },
  );

  test(
    'native deletion rejects a colliding owner and symbolic links',
    () async {
      final root = await Directory.systemTemp.createTemp('aster-delete-owner-');
      addTearDown(() => root.delete(recursive: true));
      final directories = IoWalletDirectoryManager(
        '${root.path}/wallets',
        MemoryWalletStorageSecurity(),
      );
      const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await directories.create(_first, storageToken: token);
      await expectLater(
        directories.removeDeletedWallet(_first, storageToken: 'b' * 32),
        throwsA(isA<FileSystemException>()),
      );
      expect(await Directory('${root.path}/wallets/$_first').exists(), isTrue);
      final outside = await Directory('${root.path}/outside').create();
      await Link('${root.path}/wallets/$_second').create(outside.path);
      await expectLater(
        directories.removeDeletedWallet(_second, storageToken: token),
        throwsA(isA<FileSystemException>()),
      );
      expect(await outside.exists(), isTrue);
    },
  );

  test(
    'production metadata stores erase only target wallet subdirectories',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aster-delete-metadata-',
      );
      addTearDown(() => root.delete(recursive: true));
      final security = MemoryWalletStorageSecurity();
      final journal = IoWalletPaymentJournalStore(
        '${root.path}/journals',
        security,
      );
      final setup = IoRgbWalletSetupStore('${root.path}/setup', security);
      final receipts = IoWalletPaymentReceiptStore(
        '${root.path}/receipts',
        security,
      );
      for (final id in [_first, _second]) {
        await journal.write(id, 'journal-$id');
        await setup.write(id, 'setup-$id');
        await receipts.writeReceipt(id, 'c' * 64, 'receipt-$id');
      }
      for (final store in <WalletScopedDataRemoval>[journal, setup, receipts]) {
        await store.removeWallet(_first);
        await store.removeWallet(_first); // interrupted cleanup is idempotent
      }
      expect(await journal.read(_first), isNull);
      expect(await setup.read(_first), isNull);
      expect(await receipts.readAll(_first), isEmpty);
      expect(await journal.read(_second), 'journal-$_second');
      expect(await setup.read(_second), 'setup-$_second');
      expect(await receipts.readAll(_second), {'c' * 64: 'receipt-$_second'});
    },
  );
}

AppFailure _failure(AppResult<WalletRegistry> result) =>
    (result as AppFailureResult<WalletRegistry>).failure;

final class _Harness {
  _Harness();
  final documents = MemoryWalletRegistryDocumentStore();
  late final profiles = WalletProfileStore(documents);
  final secure = MemorySecureStore();
  final directories = FakeWalletDirectoryManager();
  final journals = MemoryWalletPaymentJournalStore();
  final engines = List.generate(8, (_) => FakeWalletEngine());
  late WalletRuntime runtime;
  late WalletRepository repository;

  static Future<_Harness> create(
    List<String> ids, {
    String active = _first,
  }) async {
    final h = _Harness();
    for (final id in ids) {
      final profile = WalletProfile(
        id: id,
        name: 'Wallet ${id[0]}',
        createdAt: DateTime.utc(2026, 10, 26),
        updatedAt: DateTime.utc(2026, 10, 26),
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: id,
      );
      await h.profiles.stageProvision(profile);
      await h.profiles.commitProvision(id);
      await WalletSecretStore(h.secure).write(
        id,
        WalletSecret(
          databasePassword: 'test-password',
          mnemonic: 'test-only-mnemonic',
          storageToken: id,
        ),
      );
      h.directories.storageTokens[id] = id;
    }
    await h.profiles.setActive(active);
    h.repository = h.restart();
    expect(await h.repository.bootstrap(), isA<AppSuccess<WalletRegistry>>());
    return h;
  }

  WalletRepository restart() {
    runtime = WalletRuntime(
      FakeWalletEngineFactory(engines),
      directories,
      WalletSecretStore(secure),
      _services,
    );
    addTearDown(runtime.dispose);
    return WalletRepository(
      profiles,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: _third),
      _services,
      paymentJournalStore: journals,
      paymentReceiptStore: journals,
    );
  }
}
