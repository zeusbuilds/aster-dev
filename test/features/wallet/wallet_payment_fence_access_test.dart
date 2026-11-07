import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wallet_fakes.dart';

const _firstId = '11111111111111111111111111111111';
const _secondId = '22222222222222222222222222222222';
const _firstToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _secondToken = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _destination = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
  usdtAsset: RgbAssetConfiguration(
    contractId: 'rgb:configured-usdt',
    precision: 6,
    requiresEvmValidation: false,
  ),
);
final _now = DateTime.utc(2026, 10, 24);

void main() {
  test(
    'a send queued behind a wallet switch cannot debit the target wallet',
    () async {
      final h = await _Harness.create();
      addTearDown(h.runtime.dispose);
      h.second.openPersistedGate = Completer<void>();
      final switching = h.repository.switchWallet(_secondId);
      // sendPayment captures the current native owner before joining the queue.
      final sending = h.send();
      await Future<void>.delayed(Duration.zero);
      h.second.openPersistedGate!.complete();
      expect(await switching, isA<AppSuccess<WalletRegistry>>());
      final result = await sending;
      expect(
        (result as AppFailureResult<WalletSendResult>).failure.code,
        'payment_wallet_changed',
      );
      expect(h.runtime.activeProfile?.id, _secondId);
      expect(h.second.calls, ['openPersisted']);
      expect(h.second.paymentOperations.dispatchCount, 0);
      expect(h.journal.documents, isEmpty);
    },
  );

  test('an explicitly reviewed old wallet is rejected before fee and native preparation', () async {
    final h = await _Harness.create();
    addTearDown(h.runtime.dispose);
    expect(
      await h.repository.switchWallet(_secondId),
      isA<AppSuccess<WalletRegistry>>(),
    );
    final result = await h.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinOnchain,
      destination: _destination,
      amountUnits: 20000,
      reviewedFeeRate: h.fee,
      expectedWalletId: _firstId,
    );
    expect(
      (result as AppFailureResult<WalletSendResult>).failure.code,
      'payment_wallet_changed',
    );
    expect(h.second.calls, ['openPersisted']);
    expect(h.second.paymentOperations.dispatchCount, 0);
    expect(h.journal.documents, isEmpty);
  });

  test(
    'payment fence permits owned keys, phrase and Bitcoin receipt only',
    () async {
      final h = await _Harness.create();
      addTearDown(h.runtime.dispose);
      await h.loseCommitReply();
      final before = h.first.calls.toList();

      expect(
        await h.repository.publicKeys(),
        isA<AppSuccess<WalletPublicKeys>>(),
      );
      expect(
        (await h.repository.recoveryMnemonic(
          _firstId,
        ) as AppSuccess<String>).value,
        'first test mnemonic',
      );
      expect(
        await h.repository.recoveryMnemonic(_secondId),
        isA<AppFailureResult<String>>(),
      );
      expect(
        await h.repository.createReceiveRequest(
          WalletPaymentTarget.bitcoinOnchain,
        ),
        isA<AppSuccess<WalletReceiveRequest>>(),
      );
      expect(
        await h.repository.createReceiveRequest(
          WalletPaymentTarget.usdtOnchain,
        ),
        isA<AppFailureResult<WalletReceiveRequest>>(),
      );
      expect(await h.send(), isA<AppFailureResult<WalletSendResult>>());
      expect(h.first.paymentOperations.dispatchCount, 1);
      expect(h.runtime.hasPaymentSubmissionFence, isTrue);
      expect(h.first.calls.skip(before.length), [
        'publicKeys',
        'createReceiveRequest:start',
        'createReceiveRequest:end',
      ]);
    },
  );

  test(
    'switching isolates the old fence and restores it when returning',
    () async {
      final h = await _Harness.create();
      addTearDown(h.runtime.dispose);
      await h.loseCommitReply();
      final saved = h.journal.documents[_firstId];
      expect(
        await h.repository.switchWallet(_secondId),
        isA<AppSuccess<WalletRegistry>>(),
      );
      expect(h.runtime.activeProfile?.id, _secondId);
      expect(h.runtime.hasPaymentSubmissionFence, isFalse);
      expect(h.first.calls.last, 'destroy');
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      expect(h.second.paymentOperations.dispatchCount, 1);
      expect(h.journal.documents[_firstId], saved);

      expect(
        await h.repository.switchWallet(_firstId),
        isA<AppSuccess<WalletRegistry>>(),
      );
      expect(h.runtime.hasPaymentSubmissionFence, isTrue);
      expect(h.runtime.activeProfile?.id, _firstId);
      expect(await h.send(), isA<AppFailureResult<WalletSendResult>>());
      expect(h.returnedFirst.calls, ['openPersisted']);
      expect(h.first.paymentOperations.dispatchCount, 1);
      expect(h.journal.documents[_firstId], saved);
    },
  );

  test(
    'failed target activation restores the old wallet and its fence',
    () async {
      final h = await _Harness.create();
      addTearDown(h.runtime.dispose);
      await h.loseCommitReply();
      h.second.openPersistedError = StateError('Unavailable target');
      expect(
        await h.repository.switchWallet(_secondId),
        isA<AppFailureResult<WalletRegistry>>(),
      );
      expect(h.runtime.activeProfile?.id, _firstId);
      expect(h.runtime.hasPaymentSubmissionFence, isTrue);
      expect(await h.send(), isA<AppFailureResult<WalletSendResult>>());
      expect(h.returnedFirst.calls, ['openPersisted']);
    },
  );

  test(
    'failed old native cleanup never opens the target or exposes its keys',
    () async {
      final h = await _Harness.create();
      addTearDown(() async {
        h.first.destroyError = null;
        await h.runtime.dispose();
      });
      await h.loseCommitReply();
      h.first.destroyError = StateError('Lost native cleanup result');
      final result = await h.repository.switchWallet(_secondId);
      expect(
        (result as AppFailureResult<WalletRegistry>)
            .failure
            .requiresReconciliation,
        isTrue,
      );
      expect(h.runtime.hasPaymentSubmissionFence, isFalse);
      expect(h.runtime.activeProfile?.id, _firstId);
      expect(h.second.calls, isEmpty);
      expect(
        await h.repository.publicKeys(),
        isA<AppFailureResult<WalletPublicKeys>>(),
      );
      expect(
        await h.repository.recoveryMnemonic(_firstId),
        isA<AppFailureResult<String>>(),
      );
    },
  );

  test('a queued read cannot cross the target journal restoration', () async {
    final h = await _Harness.create();
    addTearDown(h.runtime.dispose);
    await h.loseCommitReply();
    h.second.openPersistedGate = Completer<void>();
    final switching = h.repository.switchWallet(_secondId);
    await Future<void>.delayed(Duration.zero);
    final receive = h.repository.createReceiveRequest(
      WalletPaymentTarget.bitcoinOnchain,
    );
    await Future<void>.delayed(Duration.zero);
    expect(h.second.calls, ['openPersisted']);
    expect(
      h.first.calls.where((c) => c == 'createReceiveRequest:start'),
      isEmpty,
    );
    h.second.openPersistedGate!.complete();
    expect(await switching, isA<AppSuccess<WalletRegistry>>());
    expect(await receive, isA<AppSuccess<WalletReceiveRequest>>());
    expect(h.second.calls, [
      'openPersisted',
      'createReceiveRequest:start',
      'createReceiveRequest:end',
    ]);
  });

  test(
    'selecting the same fenced wallet preserves its owner without reopening',
    () async {
      final h = await _Harness.create();
      addTearDown(h.runtime.dispose);
      await h.loseCommitReply();
      final before = h.first.calls.toList();
      expect(
        await h.repository.switchWallet(_firstId),
        isA<AppSuccess<WalletRegistry>>(),
      );
      expect(h.runtime.hasPaymentSubmissionFence, isTrue);
      expect(h.first.calls, before);
    },
  );

  test(
    'an unreadable target journal closes its new native owner before returning',
    () async {
      final h = await _Harness.create();
      addTearDown(h.runtime.dispose);
      await h.loseCommitReply();
      h.journal.documents[_secondId] = 'invalid journal';
      final result = await h.repository.switchWallet(_secondId);
      expect(
        (result as AppFailureResult<WalletRegistry>).failure.code,
        'wallet_payment_fence_restore_failed',
      );
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.disposed);
      expect(h.second.calls, ['openPersisted', 'destroy']);
      expect(await h.send(), isA<AppFailureResult<WalletSendResult>>());
      expect(h.second.paymentOperations.dispatchCount, 0);
    },
  );

  test(
    'known accepted receipt repair preserves success and fences later sends',
    () async {
      final h = await _Harness.create();
      addTearDown(h.runtime.dispose);
      h.journal.receiptWriteError = StateError('Unavailable receipt store');
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      expect(h.runtime.hasPaymentSubmissionFence, isTrue);
      expect(
        h.runtime.snapshot.failure?.code,
        'payment_receipt_persistence_required',
      );
      expect(h.runtime.snapshot.failure?.outcomeUnknown, isFalse);
      expect(await h.send(), isA<AppFailureResult<WalletSendResult>>());
      expect(
        await h.repository.publicKeys(),
        isA<AppSuccess<WalletPublicKeys>>(),
      );
      expect(h.first.paymentOperations.dispatchCount, 1);
    },
  );

  test(
    'the next ordinary read reopens the same deadline owner without redispatch',
    () async {
      final h = await _Harness.create();
      addTearDown(h.runtime.dispose);
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      h.first.requiresPaymentReopen = true;
      final before = h.first.calls.length;
      expect(
        await h.repository.balance(WalletAssetKind.bitcoin),
        isA<AppSuccess<WalletBalance>>(),
      );
      expect(h.first.calls.skip(before), ['openPersisted', 'balance']);
      expect(h.first.openedPassword, 'test-password');
      expect(h.first.requiresPaymentReopen, isFalse);
      expect(h.first.paymentOperations.dispatchCount, 1);
      expect(h.runtime.activeProfile?.id, _firstId);
    },
  );

  test('explicit Check inspects before reopening and cancelling a prepared deadline operation', () async {
    final h = await _Harness.create();
    addTearDown(h.runtime.dispose);
    h.first.preparePaymentOperationError = StateError('Lost prepare reply');
    expect(await h.send(), isA<AppFailureResult<WalletSendResult>>());
    h.first.requiresPaymentReopen = true;
    final before = h.first.calls.length;
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expect(h.first.calls.skip(before), [
      'validatePaymentOperationRequest',
      'inspectPaymentOperation',
      'openPersisted',
      'cancelPaymentOperation',
    ]);
    expect(h.first.paymentOperations.dispatchCount, 0);
    expect(h.first.requiresPaymentReopen, isFalse);
  });

  test('failed deadline reopen preserves exact Accepted evidence and stops native reads', () async {
    final h = await _Harness.create();
    addTearDown(h.runtime.dispose);
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    h.first
      ..requiresPaymentReopen = true
      ..openPersistedError = StateError('Reopen unavailable');
    final before = h.first.calls.length;
    final result = await h.repository.balance(WalletAssetKind.bitcoin);
    expect(
      (result as AppFailureResult<WalletBalance>).failure.code,
      'wallet_payment_owner_recovery_required',
    );
    expect(h.first.calls.skip(before), ['openPersisted']);
    final payment =
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value;
    expect(payment?.outcome, WalletPaymentSubmissionOutcome.accepted);
    expect(h.runtime.hasPaymentSubmissionFence, isFalse);
    expect(await h.send(), isA<AppFailureResult<WalletSendResult>>());
    expect(h.first.paymentOperations.dispatchCount, 1);
  });
}

final class _Harness {
  final journal = MemoryWalletPaymentJournalStore();
  final profiles = WalletProfileStore(
    MemoryWalletRegistryDocumentStore(),
    clock: () => _now,
  );
  final directories = FakeWalletDirectoryManager();
  final secrets = WalletSecretStore(MemorySecureStore());
  final first = FakeWalletEngine();
  final second = FakeWalletEngine();
  late final returnedFirst = FakeWalletEngine(
    paymentOperations: first.paymentOperations,
  );
  late final WalletRuntime runtime;
  late final WalletRepository repository;
  late final fee = WalletFeeRateEstimate(
    targetBlocks: 6,
    satsPerVbyte: 2,
    observedAt: _now,
  );

  static Future<_Harness> create() async {
    final h = _Harness();
    h.runtime = WalletRuntime(
      FakeWalletEngineFactory([h.first, h.second, h.returnedFirst]),
      h.directories,
      h.secrets,
      _services,
    );
    for (final (id, token) in [
      (_firstId, _firstToken),
      (_secondId, _secondToken),
    ]) {
      final profile = WalletProfile(
        id: id,
        name: id == _firstId ? 'First' : 'Second',
        createdAt: _now,
        updatedAt: _now,
        environment: BlockchainEnvironment.regtest,
        state: WalletProfileState.provisioning,
        storageToken: token,
      );
      expect(
        await h.profiles.stageProvision(profile),
        isA<AppSuccess<WalletRegistry>>(),
      );
      expect(
        await h.profiles.commitProvision(id),
        isA<AppSuccess<WalletRegistry>>(),
      );
      h.directories.storageTokens[id] = token;
      expect(
        await h.secrets.write(
          id,
          WalletSecret(
            databasePassword: 'test-password',
            mnemonic: id == _firstId
                ? 'first test mnemonic'
                : 'second test mnemonic',
            storageToken: token,
          ),
        ),
        isA<AppSuccess<void>>(),
      );
    }
    expect(
      await h.profiles.setActive(_firstId),
      isA<AppSuccess<WalletRegistry>>(),
    );
    final registry =
        (await h.profiles.read() as AppSuccess<WalletRegistry>).value;
    expect(
      await h.runtime.restore(registry.activeProfile!),
      isA<AppSuccess<void>>(),
    );
    for (final engine in [h.first, h.second, h.returnedFirst]) {
      engine.feeEstimate = h.fee;
    }
    h.repository = WalletRepository(
      h.profiles,
      h.runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: _firstId),
      _services,
      clock: () => _now,
      paymentJournalStore: h.journal,
    );
    return h;
  }

  Future<AppResult<WalletSendResult>> send() => repository.sendPayment(
    target: WalletPaymentTarget.bitcoinOnchain,
    destination: _destination,
    amountUnits: 20000,
    reviewedFeeRate: fee,
  );

  Future<void> loseCommitReply() async {
    first.commitPaymentOperationReplyError = StateError('Lost commit reply');
    first.inspectPaymentOperationError = StateError('Status unavailable');
    final result = await send();
    expect(
      (result as AppFailureResult<WalletSendResult>).failure.outcomeUnknown,
      isTrue,
    );
    expect(runtime.hasPaymentSubmissionFence, isTrue);
  }
}
