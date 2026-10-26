import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/transaction/presentation/view_model/activity_view_model.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  test(
    'a missing switch target preserves the active wallet and its payment fence',
    () async {
      final now = DateTime.now().toUtc();
      final engine = FakeWalletEngine()
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        )
        ..sendPaymentError = StateError('Lost payment response');
      final h = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(h.dispose);
      final before = await h.container.read(walletViewModelProvider.future);
      final result = await h.repository.sendPayment(
        target: WalletPaymentTarget.bitcoinOnchain,
        destination: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
        amountUnits: 1,
        reviewedFeeRate: engine.feeEstimate,
      );
      expect(result, isA<AppFailureResult<WalletSendResult>>());
      final vm = h.container.read(walletViewModelProvider.notifier);
      expect(await vm.switchWallet(_secondWalletId), isFalse);
      final after = await h.container.read(walletViewModelProvider.future);
      expect(after.activeWallet, before.activeWallet);
      expect(after.wallets, before.wallets);
      expect(after.operationFailure?.code, 'wallet_profile_not_found');
      final activity = await h.container.read(
        activityViewModelProvider(WalletAssetKind.bitcoin).future,
      );
      expect(activity.feed.paymentSubmission?.requiresReconciliation, isTrue);
      final blocked = await h.repository.sendPayment(
        target: WalletPaymentTarget.bitcoinOnchain,
        destination: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
        amountUnits: 1,
        reviewedFeeRate: engine.feeEstimate,
      );
      expect(
        (blocked as AppFailureResult<WalletSendResult>).failure.code,
        walletPaymentSubmissionPendingFailure.code,
      );
      expect(engine.calls, isNot(contains('destroy')));
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
    },
  );

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
      final engine = FakeWalletEngine()..openPersistedGate = activationGate;
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
      expect(
        engine.calls.where((call) => call == 'openPersisted'),
        hasLength(1),
      );
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
    'escalates an unreconciled switch to a persistent root access error',
    () async {
      final target = FakeWalletEngine();
      final rollback = FakeWalletEngine()
        ..openPersistedError = StateError(
          'injected rollback activation failure',
        );
      final harness = await _createHarness(
        seedWalletProfiles: true,
        engines: [target, rollback],
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
      harness.documents.writeError = StateError(
        'injected active-wallet persistence failure',
      );
      final notifier = harness.container.read(walletViewModelProvider.notifier);

      expect(await notifier.switchWallet(_secondWalletId), isFalse);

      final failed = harness.container.read(walletViewModelProvider);
      expect(failed, isA<AsyncError<WalletState>>());
      final mapped = FailureMapper.from(
        failed.error!,
        failed.stackTrace ?? StackTrace.current,
      );
      expect(mapped.code, 'wallet_switch_commit_failed');
      expect(mapped.requiresReconciliation, isTrue);
      expect(mapped.outcomeUnknown, isFalse);
      final targetCalls = List<String>.of(target.calls);
      final rollbackCalls = List<String>.of(rollback.calls);

      expect(await notifier.switchWallet(_firstWalletId), isFalse);
      notifier.clearOperationFailure();

      expect(harness.container.read(walletViewModelProvider), same(failed));
      expect(target.calls, targetCalls);
      expect(rollback.calls, rollbackCalls);
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

  test(
    'deletion publishes progress and suppresses overlapping wallet changes',
    () async {
      final auditGate = Completer<void>();
      final first = FakeWalletEngine()..deletionAuditGate = auditGate;
      final h = await _createHarness(
        seedWalletProfiles: true,
        engines: [first, FakeWalletEngine()],
      );
      addTearDown(h.dispose);
      expect(await h.repository.bootstrap(), isA<AppSuccess<WalletRegistry>>());
      await h.container.read(walletViewModelProvider.future);
      final vm = h.container.read(walletViewModelProvider.notifier);
      final deleting = vm.deleteWallet(_firstWalletId);
      await Future<void>.delayed(Duration.zero);
      final during = h.container.read(walletViewModelProvider).requireValue;
      expect(during.deletingWalletId, _firstWalletId);
      expect(during.isChangingWallet, isTrue);
      expect(await vm.deleteWallet(_firstWalletId), isFalse);
      expect(await vm.switchWallet(_secondWalletId), isFalse);
      final reads = h.documents.readCount;
      await vm.reload();
      expect(h.documents.readCount, reads);
      auditGate.complete();
      expect(await deleting, isTrue);
      final after = h.container.read(walletViewModelProvider).requireValue;
      expect(after.activeWallet?.id, _secondWalletId);
      expect(after.wallets, hasLength(1));
      expect(after.isChangingWallet, isFalse);
      expect(after.operationFailure, isNull);
    },
  );

  test(
    'deletion preflight warning preserves wallet and is consumed once',
    () async {
      final first = FakeWalletEngine()..protectedRgbState = true;
      final h = await _createHarness(
        seedWalletProfiles: true,
        engines: [first],
      );
      addTearDown(h.dispose);
      await h.repository.bootstrap();
      await h.container.read(walletViewModelProvider.future);
      final vm = h.container.read(walletViewModelProvider.notifier);
      expect(await vm.deleteWallet(_firstWalletId), isFalse);
      final after = h.container.read(walletViewModelProvider).requireValue;
      expect(after.activeWallet?.id, _firstWalletId);
      expect(after.wallets, hasLength(2));
      expect(after.isChangingWallet, isFalse);
      expect(after.operationFailure?.code, 'wallet_deletion_rgb_state_present');
      vm.clearOperationFailure();
      expect(
        h.container.read(walletViewModelProvider).requireValue.operationFailure,
        isNull,
      );
      expect(first.calls, isNot(contains('destroy')));
    },
  );

  test(
    'explicit recovery reopens survivor after committed deletion failure',
    () async {
      final failedOpen = FakeWalletEngine()
        ..openPersistedError = StateError('unavailable');
      final h = await _createHarness(
        seedWalletProfiles: true,
        engines: [FakeWalletEngine(), failedOpen, FakeWalletEngine()],
      );
      addTearDown(h.dispose);
      await h.repository.bootstrap();
      await h.container.read(walletViewModelProvider.future);
      final vm = h.container.read(walletViewModelProvider.notifier);
      expect(await vm.deleteWallet(_firstWalletId), isFalse);
      final failed = h.container.read(walletViewModelProvider);
      expect(failed.hasError, isTrue);
      final failure = FailureMapper.from(failed.error!, failed.stackTrace!);
      expect(WalletViewModel.canResumeDeletion(failure), isTrue);
      expect(failure.code, 'wallet_deleted_activation_failed');
      await vm.reload();
      final after = h.container.read(walletViewModelProvider).requireValue;
      expect(after.activeWallet?.id, _secondWalletId);
      expect(after.wallets, hasLength(1));
      expect(after.wallets.any((p) => p.id == _firstWalletId), isFalse);
    },
  );

  test('only durable deletion failures qualify for explicit resume', () {
    expect(
      WalletViewModel.canResumeDeletion(
        const AppFailure(
          code: 'wallet_deletion_incomplete',
          kind: AppFailureKind.storage,
          userMessage: 'Wallet removal could not finish.',
          retryable: false,
          requiresReconciliation: true,
        ),
      ),
      isTrue,
    );
    expect(
      WalletViewModel.canResumeDeletion(
        const AppFailure(
          code: 'wallet_payment_submission_pending',
          kind: AppFailureKind.conflict,
          userMessage: 'Payment outcome unknown.',
          retryable: false,
          requiresReconciliation: true,
        ),
      ),
      isFalse,
    );
  });
}

Future<_WalletViewModelHarness> _createHarness({
  Object? readError,
  bool delayRepository = false,
  bool seedWalletProfiles = false,
  List<FakeWalletEngine> engines = const [],
}) async {
  final documents = MemoryWalletRegistryDocumentStore()..readError = readError;
  final profiles = WalletProfileStore(documents);
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
