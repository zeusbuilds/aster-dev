import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wallet_fakes.dart';

const _id = '11111111111111111111111111111111';
const _storageToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _destination = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
  usdtAsset: RgbAssetConfiguration(
    contractId: 'rgb:configured-usdt',
    precision: 6,
  ),
);
final _now = DateTime.utc(2026, 10, 16);
final _txid = 'b' * 64;

void main() {
  test('an earlier accepted receipt cannot resolve a different failed marker commit', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    final previous =
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value!;
    h.store.failWriteNumber = 3;
    _expectPending(await h.send());
    final pending =
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value!;
    expect(pending.id, isNot(previous.id));
    expect(pending.phase, WalletPaymentSubmissionPhase.submitting);
    h.engine.activities = [_bitcoinActivity(txid: _txid)];
    _expectPending(await h.repository.reconcilePaymentSubmission());
    expect(
      h.engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
  });

  test(
    'failed native cleanup escalates payment audit to a full quarantine',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.store
        ..failWriteNumber = 2
        ..commitBeforeError = true;
      _expectPending(await h.send());
      h.engine
        ..destroyError = StateError('Lost destroy response')
        ..activities = [_bitcoinActivity(txid: _txid)];
      expect(await h.repository.dispose(), isA<AppFailureResult<void>>());
      expect(h.runtime.snapshot.failure?.code, 'wallet_native_cleanup_failed');
      final calls = h.engine.calls.toList();
      expect(
        await h.repository.activityFeed(WalletAssetKind.bitcoin),
        isA<AppFailureResult<WalletActivityFeed>>(),
      );
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppFailureResult<void>>(),
      );
      expect(await h.send(), isA<AppFailureResult<WalletSendResult>>());
      expect(h.engine.calls, calls);
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
      h.engine.destroyError = null;
    },
  );

  test(
    'strong native audit failure cannot be repaired by matching a receipt',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.store
        ..failWriteNumber = 2
        ..commitBeforeError = true;
      _expectPending(await h.send());
      h.engine.activityError = const AppFailureException(
        AppFailure(
          code: 'native_owner_state_invalid',
          kind: AppFailureKind.storage,
          userMessage: 'Wallet recovery required.',
          retryable: false,
          requiresReconciliation: true,
        ),
      );
      expect(
        await h.repository.activityFeed(WalletAssetKind.bitcoin),
        isA<AppFailureResult<WalletActivityFeed>>(),
      );
      expect(h.runtime.snapshot.failure?.code, 'native_owner_state_invalid');
      h.engine
        ..activityError = null
        ..activities = [_bitcoinActivity(txid: _txid)];
      final calls = h.engine.calls.toList();
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppFailureResult<void>>(),
      );
      expect(h.engine.calls, calls);
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    },
  );

  test('durable accepted receipt remains identifiable after lost local ack and restart', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store
      ..failWriteNumber = 2
      ..commitBeforeError = true;
    _expectPending(await h.send());
    await h.restart();
    final feed = await h.repository.activityFeed(WalletAssetKind.bitcoin);
    final receipt =
        (feed as AppSuccess<WalletActivityFeed>).value.paymentSubmission!;
    expect(receipt.phase, WalletPaymentSubmissionPhase.accepted);
    expect(receipt.result?.referenceId, _txid);
    expect(receipt.command.destination, _destination);
    expect(receipt.requiresReconciliation, isFalse);
    expect(h.engine.calls, isNot(contains('sendPayment:start')));
  });

  test('malformed native transaction receipts never become accepted', () async {
    for (final receipt in [
      ('not-a-txid', null),
      ('a' * 63, null),
      ('a' * 64, 0),
    ]) {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      const route = PaymentRoute(
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.onchain,
      );
      h.engine.sentPayment = WalletSendResult(
        route: route,
        amount: WalletAmount.onchain(assetId: route.asset.id, units: 20000),
        referenceId: receipt.$1,
        batchTransferIndex: receipt.$2,
        status: WalletPaymentStatus.pending,
      );
      _expectPending(await h.send());
      expect(h.store.writes, hasLength(1));
      await h.restart();
      _expectPending(await h.send());
      expect(h.engine.calls, isNot(contains('sendPayment:start')));
    }
  });

  test('durable reviewed intent precedes dispatch and exact acceptance precedes success', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store.onWrite = (_, document) {
      final value = jsonDecode(document) as Map<String, Object?>;
      if (value['phase'] == 'submitting') {
        expect(h.engine.calls, isNot(contains('sendPayment:start')));
      } else {
        expect(h.engine.calls, contains('sendPayment:end'));
      }
    };
    final result = await h.send();
    expect(result, isA<AppSuccess<WalletSendResult>>());
    expect(h.store.writes, hasLength(2));
    final intent = jsonDecode(h.store.writes.first) as Map<String, Object?>;
    final command = intent['command']! as Map<String, Object?>;
    expect(intent['walletId'], _id);
    expect(intent['storageToken'], _storageToken);
    expect(intent['network'], 'regtest');
    expect(command['destination'], _destination);
    expect(command['amount'], 20000);
    expect(command['feeRate'], 2);
    expect(command['feeTarget'], 6);
    final status = await h.repository.paymentSubmissionStatus();
    final record = (status as AppSuccess<WalletPaymentSubmission?>).value!;
    expect(record.command, h.engine.sentPaymentCommand);
    expect(record.phase, WalletPaymentSubmissionPhase.accepted);
    expect(record.result?.referenceId, _txid);
    expect(record.toString(), isNot(contains(_destination)));
    expect(record.toString(), isNot(contains(_txid)));
    await h.restart();
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    expect(
      (await h.repository.paymentSubmissionStatus()
              as AppSuccess<WalletPaymentSubmission?>)
          .value
          ?.result
          ?.referenceId,
      _txid,
    );
  });

  test('lost native response fences all mutations and leaves Activity readable across restart', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine.sendPaymentError = const WalletMutationOutcomeUnknownException(
      FailureDiagnostic(sourceType: 'LostReply'),
    );
    _expectPending(await h.send());
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    expect(
      await h.repository.activityFeed(WalletAssetKind.bitcoin),
      isA<AppSuccess<WalletActivityFeed>>(),
    );
    expect(
      await h.repository.balance(WalletAssetKind.bitcoin),
      isA<AppSuccess<WalletBalance>>(),
    );
    expect(await h.repository.portfolio(), isA<AppSuccess<WalletPortfolio>>());
    expect(
      await h.repository.networkStatus(),
      isA<AppSuccess<WalletNetworkStatus>>(),
    );
    await h.restart();
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    final before = h.engine.calls.toList();
    _expectPending(await h.send());
    _expectPending(
      await h.repository.createReceiveRequest(
        WalletPaymentTarget.bitcoinOnchain,
      ),
    );
    _expectPending(
      await h.repository.createReceiveRequest(WalletPaymentTarget.usdtOnchain),
    );
    _expectPending(await h.repository.prepareRgbWalletSetup());
    _expectPending(await h.repository.switchWallet('2' * 32));
    _expectPending(
      await h.repository.createFromMnemonic(mnemonic: 'invalid', name: 'New'),
    );
    _expectPending(await h.repository.publicKeys());
    _expectPending(await h.repository.recoveryMnemonic(_id));
    expect(h.engine.calls, before);
    expect(
      await h.repository.activityFeed(WalletAssetKind.bitcoin),
      isA<AppSuccess<WalletActivityFeed>>(),
    );
    _expectPending(await h.repository.reconcilePaymentSubmission());
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    expect(h.store.writes, hasLength(1));
  });

  test('empty or similar native history never identifies an unknown Bitcoin submission', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine.sendPaymentError = StateError('A native response disappeared');
    _expectPending(await h.send());
    await h.restart();
    for (final history in <List<WalletActivity>>[
      [],
      [_bitcoinActivity(txid: 'c' * 64)],
      [_bitcoinActivity(txid: _txid)],
    ]) {
      h.engine.activities = history;
      expect(
        await h.repository.activityFeed(WalletAssetKind.bitcoin),
        isA<AppSuccess<WalletActivityFeed>>(),
      );
      _expectPending(await h.repository.reconcilePaymentSubmission());
      _expectPending(await h.send());
    }
    expect(h.engine.calls, isNot(contains('sendPayment:start')));
    expect(h.store.writes, hasLength(1));
  });

  test('marker commit uncertainty never enters native and a committed marker survives restart', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store
      ..failWriteNumber = 1
      ..commitBeforeError = true;
    _expectPending(await h.send());
    expect(h.engine.calls, isNot(contains('sendPayment:start')));
    await h.restart();
    _expectPending(await h.send());
    expect(h.engine.calls, isNot(contains('sendPayment:start')));
  });

  test('lost acceptance commit retains the submitting marker and never retries native', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store.failWriteNumber = 2;
    _expectPending(await h.send());
    expect(
      h.engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
    await h.restart();
    h.engine.activities = [_bitcoinActivity(txid: _txid)];
    _expectPending(await h.repository.reconcilePaymentSubmission());
    _expectPending(await h.send());
    expect(h.engine.calls, isNot(contains('sendPayment:start')));
  });

  test('durably accepted lost acknowledgement resolves only the exact native transaction', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store
      ..failWriteNumber = 2
      ..commitBeforeError = true;
    _expectPending(await h.send());
    for (final history in <List<WalletActivity>>[
      [],
      [_bitcoinActivity(txid: 'c' * 64)],
      [_bitcoinActivity(txid: _txid, amount: 19999)],
      [_bitcoinActivity(txid: _txid), _bitcoinActivity(txid: _txid, index: 2)],
    ]) {
      h.engine.activities = history;
      _expectPending(await h.repository.reconcilePaymentSubmission());
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    }
    h.engine.activities = [_bitcoinActivity(txid: _txid)];
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    expect(
      h.engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
    expect(h.store.writes, hasLength(2));
  });

  test('RGB journal retains recipient policy and resolves only matching asset, txid, and native batch', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store
      ..failWriteNumber = 2
      ..commitBeforeError = true;
    final route = PaymentRoute(
      asset: WalletAsset.rgbUsdt(assetId: 'rgb:configured-usdt', precision: 6),
      rail: PaymentRail.onchain,
    );
    h.engine.sentPayment = WalletSendResult(
      route: route,
      amount: WalletAmount.onchain(assetId: route.asset.id, units: 20000),
      referenceId: _txid,
      status: WalletPaymentStatus.pending,
      batchTransferIndex: 42,
    );
    _expectPending(
      await h.repository.sendPayment(
        target: WalletPaymentTarget.usdtOnchain,
        destination: 'rgb:encoded-invoice',
        amountUnits: 20000,
        reviewedFeeRate: h.fee,
        rgbRecipientType: RgbRecipientType.witness,
        witnessBitcoinAmountSats: rgbWitnessRecipientSats,
      ),
    );
    final intent =
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value!;
    expect(intent.command.rgbRecipientType, RgbRecipientType.witness);
    expect(intent.command.witnessBitcoinAmountSats, 1000);
    h.engine.activities = [_rgbActivity(route, batch: 43)];
    _expectPending(await h.repository.reconcilePaymentSubmission());
    h.engine.activities = [_rgbActivity(route, batch: 42)];
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
  });

  test('review or confirmed local validation rejection permits a fresh explicit submission', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final missingReview = await h.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinOnchain,
      destination: _destination,
      amountUnits: 20000,
    );
    expect(
      (missingReview as AppFailureResult<WalletSendResult>).failure,
      walletFeeReviewRequiredFailure,
    );
    expect(h.store.writes, isEmpty);
    h.engine.sendPaymentError =
        const WalletPaymentRejectedBeforeDispatchException(
          AppFailure(
            code: 'wallet_validation',
            kind: AppFailureKind.validation,
            userMessage: 'Check the entered information and try again.',
            retryable: false,
          ),
        );
    final rejected = await h.send();
    expect(
      (rejected as AppFailureResult<WalletSendResult>).failure.outcomeUnknown,
      isFalse,
    );
    expect(
      (await h.repository.paymentSubmissionStatus()
              as AppSuccess<WalletPaymentSubmission?>)
          .value
          ?.phase,
      WalletPaymentSubmissionPhase.rejected,
    );
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    h.engine.sendPaymentError = null;
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
  });

  test(
    'native mismatched acknowledgement cannot clear the durable intent',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      const route = PaymentRoute(
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.onchain,
      );
      h.engine.sentPayment = WalletSendResult(
        route: route,
        amount: WalletAmount.onchain(
          assetId: WalletAsset.bitcoin.id,
          units: 19999,
        ),
        referenceId: _txid,
        status: WalletPaymentStatus.pending,
      );
      _expectPending(await h.send());
      expect(h.store.writes, hasLength(1));
      _expectPending(await h.repository.reconcilePaymentSubmission());
    },
  );

  test(
    'a queued second send cannot cross the first unresolved dispatch',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine
        ..sendPaymentGate = Completer<void>()
        ..sendPaymentError = StateError('Lost response');
      final first = h.send();
      await Future<void>.delayed(Duration.zero);
      final second = h.send();
      h.engine.sendPaymentGate!.complete();
      _expectPending(await first);
      _expectPending(await second);
      expect(
        h.engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
      expect(h.store.writes, hasLength(1));
    },
  );

  test('background shutdown and resume preserve the read-only fence', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine.sendPaymentError = StateError('Lost response');
    _expectPending(await h.send());
    expect(await h.repository.suspend(), isA<AppSuccess<void>>());
    expect(h.engine.calls, contains('shutdown'));
    expect(
      await h.repository.activityFeed(WalletAssetKind.bitcoin),
      isA<AppFailureResult<WalletActivityFeed>>(),
    );
    expect(
      h.runtime.snapshot.failure?.code,
      walletPaymentSubmissionPendingFailure.code,
    );
    expect(await h.repository.resume(), isA<AppSuccess<void>>());
    expect(h.engine.calls, contains('openPersisted'));
    expect(
      await h.repository.activityFeed(WalletAssetKind.bitcoin),
      isA<AppSuccess<WalletActivityFeed>>(),
    );
    _expectPending(await h.send());
  });

  test('uncertain shutdown never leaves a readable native lease', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine
      ..sendPaymentError = StateError('Lost response')
      ..shutdownError = StateError('Lost shutdown response');
    _expectPending(await h.send());
    expect(await h.repository.suspend(), isA<AppFailureResult<void>>());
    expect(
      await h.repository.activityFeed(WalletAssetKind.bitcoin),
      isA<AppFailureResult<WalletActivityFeed>>(),
    );
    _expectPending(await h.send());
    h.engine.shutdownError = null;
  });

  test('storage binding, schema, and malformed intent fail bootstrap before native open', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    final original = h.store.documents[_id]!;
    for (final change in <void Function(Map<String, Object?>)>[
      (value) => value['walletId'] = '2' * 32,
      (value) => value['storageToken'] = 'c' * 32,
      (value) => value['network'] = 'mainnet',
      (value) => value['version'] = 2,
      (value) => value['phase'] = 'forgotten',
      (value) => value['extra'] = true,
      (value) => value['result'] = null,
      (value) => (value['result']! as Map<String, Object?>)['referenceId'] =
          'not-a-txid',
      (value) =>
          (value['result']! as Map<String, Object?>)['batchTransferIndex'] = 0,
      (value) => (value['command']! as Map<String, Object?>)['amount'] = 0,
      (value) => (value['command']! as Map<String, Object?>)['feeRate'] = 0,
    ]) {
      final modified = jsonDecode(original) as Map<String, Object?>;
      change(modified);
      h.store.documents[_id] = jsonEncode(modified);
      final boot = await h.restart(expectSuccess: false);
      expect(
        (boot as AppFailureResult<WalletRegistry>).failure.code,
        'stored_data_invalid',
      );
      expect(h.engine.calls, isNot(contains('openPersisted')));
    }
  });

  test(
    'wallet sends fail closed when no durable journal has been configured',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final repository = h.buildRepository(withJournal: false);
      final result = await repository.sendPayment(
        target: WalletPaymentTarget.bitcoinOnchain,
        destination: _destination,
        amountUnits: 20000,
        reviewedFeeRate: h.fee,
      );
      expect(
        (result as AppFailureResult<WalletSendResult>).failure.code,
        'payment_journal_unavailable',
      );
      expect(h.engine.calls, isNot(contains('sendPayment:start')));
    },
  );

  test('IO financial journal never falls back from a corrupt newest slot to an older accepted document', () async {
    final root = await Directory.systemTemp.createTemp(
      'aster-payment-journal-',
    );
    addTearDown(() => root.delete(recursive: true));
    final security = MemoryWalletStorageSecurity();
    final store = IoWalletPaymentJournalStore(root.path, security);
    await store.write(_id, '{"phase":"accepted"}');
    await store.write(_id, '{"phase":"submitting"}');
    await File('${root.path}/$_id/wallet_registry.b.json')
        .writeAsString('{truncated', flush: true);
    final freshStore = IoWalletPaymentJournalStore(root.path, security);
    await expectLater(
      freshStore.read(_id),
      throwsA(isA<StoredDataCorruptionException>()),
    );
    await expectLater(
      store.read('../escape'),
      throwsA(isA<StoredDataCorruptionException>()),
    );
  });
}

void _expectPending<T>(AppResult<T> result) {
  expect(result, isA<AppFailureResult<T>>());
  final failure = (result as AppFailureResult<T>).failure;
  expect(failure.code, walletPaymentSubmissionPendingFailure.code);
  expect(failure.retryable, isFalse);
  expect(failure.outcomeUnknown, isTrue);
}

WalletActivity _bitcoinActivity({
  required String txid,
  int amount = 20000,
  int index = 1,
}) => WalletActivity(
  id: 'activity-${index.toRadixString(16).padLeft(64, '0')}',
  source: WalletActivitySource.bitcoinTransaction,
  operation: WalletActivityOperation.bitcoinSend,
  asset: WalletAsset.bitcoin,
  rail: PaymentRail.onchain,
  direction: WalletActivityDirection.sent,
  status: WalletActivityStatus.pending,
  amount: WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: amount),
  txid: txid,
);

WalletActivity _rgbActivity(PaymentRoute route, {required int batch}) =>
    WalletActivity(
      id: 'activity-${'1' * 64}',
      source: WalletActivitySource.rgbTransfer,
      operation: WalletActivityOperation.rgbSend,
      asset: route.asset,
      rail: PaymentRail.onchain,
      direction: WalletActivityDirection.sent,
      status: WalletActivityStatus.waitingConfirmations,
      amount: WalletAmount.onchain(assetId: route.asset.id, units: 20000),
      txid: _txid,
      transferIndex: 1,
      batchTransferIndex: batch,
    );

final class _Harness {
  final store = MemoryWalletPaymentJournalStore();
  final profiles = WalletProfileStore(
    MemoryWalletRegistryDocumentStore(),
    clock: () => _now,
  );
  final directories = FakeWalletDirectoryManager();
  final secrets = WalletSecretStore(MemorySecureStore());
  late WalletRuntime runtime;
  late WalletRepository repository;
  late FakeWalletEngine engine;
  late WalletFeeRateEstimate fee;

  static Future<_Harness> create() async {
    final h = _Harness();
    h._newRuntime();
    final profile = WalletProfile(
      id: _id,
      name: 'Test',
      createdAt: _now,
      updatedAt: _now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.provisioning,
      storageToken: _storageToken,
    );
    expect(
      await h.profiles.stageProvision(profile),
      isA<AppSuccess<WalletRegistry>>(),
    );
    expect(
      await h.runtime.provision(
        profile: profile,
        mnemonic: 'test mnemonic',
        databasePassword: 'password',
      ),
      isA<AppSuccess<void>>(),
    );
    expect(
      await h.profiles.commitProvision(_id),
      isA<AppSuccess<WalletRegistry>>(),
    );
    h.repository = h.buildRepository();
    return h;
  }

  void _newRuntime() {
    fee = WalletFeeRateEstimate(
      targetBlocks: 6,
      satsPerVbyte: 2,
      observedAt: _now,
    );
    engine = FakeWalletEngine()..feeEstimate = fee;
    runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      directories,
      secrets,
      _services,
    );
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );
    engine.sentPayment = WalletSendResult(
      route: route,
      amount: WalletAmount.onchain(
        assetId: WalletAsset.bitcoin.id,
        units: 20000,
      ),
      referenceId: _txid,
      status: WalletPaymentStatus.pending,
    );
  }

  WalletRepository buildRepository({bool withJournal = true}) =>
      WalletRepository(
        profiles,
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: _id),
        _services,
        clock: () => _now,
        paymentJournalStore: withJournal ? store : null,
      );

  Future<AppResult<WalletRegistry>> restart({bool expectSuccess = true}) async {
    await runtime.dispose();
    _newRuntime();
    repository = buildRepository();
    final result = await repository.bootstrap();
    if (expectSuccess) expect(result, isA<AppSuccess<WalletRegistry>>());
    return result;
  }

  Future<AppResult<WalletSendResult>> send() => repository.sendPayment(
    target: WalletPaymentTarget.bitcoinOnchain,
    destination: _destination,
    amountUnits: 20000,
    reviewedFeeRate: fee,
  );

  Future<void> dispose() async => runtime.dispose();
}
