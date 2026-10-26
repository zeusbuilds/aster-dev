import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:dart_bech32/dart_bech32.dart' as bech32_codec;
import 'package:flutter_test/flutter_test.dart';

import '../../support/wallet_fakes.dart';

void main() {
  test('queued work cannot cross a lock and subsequent unlock', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final gate = Completer<void>();
    h.engine.networkStatusGate = gate;
    final first = h.repository.networkStatus();
    await _flush();
    final queued = h.repository.networkStatus();
    h.security.lock();
    await h.security.unlock();
    gate.complete();
    expect(await first, isA<AppSuccess<WalletNetworkStatus>>());
    expect(_failure(await queued).code, 'wallet_locked');
    expect(
      h.engine.calls.where((call) => call == 'networkStatus'),
      hasLength(1),
    );
  });

  test('queued send from an earlier session never creates an intent', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final gate = Completer<void>();
    h.engine.networkStatusGate = gate;
    final first = h.repository.networkStatus();
    await _flush();
    final sending = h.send();
    h.security.lock();
    await h.security.unlock();
    gate.complete();
    await first;
    expect(_failure(await sending).code, 'wallet_locked');
    expect(h.journal.writes, isEmpty);
    expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
    expect(h.engine.paymentOperations.dispatchCount, 0);
  });

  test('lock during fee validation prevents any payment preparation', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final gate = Completer<void>();
    h.engine.feeEstimateGate = gate;
    h.engine.feeEstimateStarted = Completer<void>();
    final sending = h.send();
    await h.engine.feeEstimateStarted!.future;
    h.security.lock();
    gate.complete();
    expect(_failure(await sending).code, 'wallet_locked');
    expect(h.journal.writes, isEmpty);
    expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
    expect(h.runtime.hasPaymentSubmissionFence, isFalse);
  });

  test('revoked intent is rejected before entering native prepare', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.journal.onWrite = (_, _) {
      if (h.journal.writes.length == 1) h.security.lock();
    };
    final failure = _failure(await h.send());
    expect(failure.code, 'wallet_locked');
    expect(failure.outcomeUnknown, isFalse);
    expect(_phase(h), 'rejected');
    expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
    expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
    expect(h.runtime.hasPaymentSubmissionFence, isFalse);
  });

  test('revoked prepared payment is cancelled before native commit', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.journal.onWrite = (_, _) {
      if (h.journal.writes.length == 2) h.security.lock();
    };
    final failure = _failure(await h.send());
    expect(failure.code, 'wallet_locked');
    expect(failure.outcomeUnknown, isFalse);
    expect(_phase(h), 'rejected');
    expect(h.engine.calls, contains('preparePaymentOperation'));
    expect(h.engine.calls, contains('cancelPaymentOperation'));
    expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
    expect(h.engine.paymentOperations.dispatchCount, 0);
    expect(h.runtime.hasPaymentSubmissionFence, isFalse);
  });

  test(
    'failed cancellation preserves the durable fence without committing',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.cancelPaymentOperationError = StateError('injected');
      h.journal.onWrite = (_, _) {
        if (h.journal.writes.length == 2) h.security.lock();
      };
      final failure = _failure(await h.send());
      expect(failure.requiresReconciliation, isTrue);
      expect(_phase(h), 'submitting');
      expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
      expect(h.engine.paymentOperations.dispatchCount, 0);
      expect(h.runtime.hasPaymentSubmissionFence, isTrue);
    },
  );

  test(
    'already entered commit settles after locking without cancellation',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final gate = Completer<void>();
      h.engine.sendPaymentGate = gate;
      final sending = h.send();
      await _until(() => h.engine.calls.contains('sendPayment:start'));
      h.security.lock();
      gate.complete();
      expect(await sending, isA<AppSuccess<WalletSendResult>>());
      expect(_phase(h), 'accepted');
      expect(h.engine.paymentOperations.dispatchCount, 1);
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
    },
  );

  test(
    'runtime rejects a revoked seed lease before reading credentials',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final gate = Completer<void>();
      h.engine.networkStatusGate = gate;
      final blocking = h.runtime.readPaymentState(
        (engine) => engine.getNetworkStatus(),
      );
      await _flush();
      final reads = h.secrets.reads;
      var authorized = true;
      final opening = h.runtime.recoveryMnemonic(
        _id,
        authorize: () {
          if (!authorized) throw const AppFailureException(_revoked);
        },
      );
      authorized = false;
      gate.complete();
      await blocking;
      expect(_failure(await opening).code, _revoked.code);
      expect(h.secrets.reads, reads);
    },
  );

  test('runtime rejects a revoked xpub lease inside its queue', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final gate = Completer<void>();
    h.engine.networkStatusGate = gate;
    final blocking = h.runtime.readPaymentState(
      (engine) => engine.getNetworkStatus(),
    );
    await _flush();
    var authorized = true;
    final opening = h.runtime.readPaymentState(
      (engine) => engine.getPublicKeys(),
      authorize: () {
        if (!authorized) throw const AppFailureException(_revoked);
      },
    );
    authorized = false;
    gate.complete();
    await blocking;
    expect(_failure(await opening).code, _revoked.code);
    expect(h.engine.calls, isNot(contains('publicKeys')));
  });

  test('xpub authorization is rechecked after native owner recovery', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final gate = Completer<void>();
    h.engine.requiresPaymentReopen = true;
    h.engine.openPersistedGate = gate;
    var authorized = true;
    final opening = h.runtime.readPaymentState(
      (engine) => engine.getPublicKeys(),
      authorize: () {
        if (!authorized) throw const AppFailureException(_revoked);
      },
    );
    await _until(() => h.engine.calls.contains('openPersisted'));
    authorized = false;
    gate.complete();
    expect(_failure(await opening).code, _revoked.code);
    expect(h.engine.calls, isNot(contains('publicKeys')));
  });
}

const _id = '11111111111111111111111111111111';
const _token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
);
const _revoked = AppFailure(
  code: 'test_revoked',
  kind: AppFailureKind.authentication,
  userMessage: 'Unlock again.',
  retryable: true,
);
final _now = DateTime.utc(2026, 10, 25);
final _review = WalletFeeRateEstimate(
  targetBlocks: 6,
  satsPerVbyte: 2,
  observedAt: _now,
);

AppFailure _failure<T>(AppResult<T> result) =>
    (result as AppFailureResult<T>).failure;
String _phase(_Harness h) =>
    (jsonDecode(h.journal.documents[_id]!) as Map<String, dynamic>)['phase']
        as String;
Future<void> _flush() => Future<void>.delayed(Duration.zero);
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    if (done()) return;
    await _flush();
  }
  fail('Expected operation did not start.');
}

final class _Harness {
  final engine = FakeWalletEngine()..feeEstimate = _review;
  final journal = MemoryWalletPaymentJournalStore();
  final secrets = _CountingSecrets();
  final security = SecurityController(_Device());
  late final WalletRuntime runtime;
  late final WalletRepository repository;

  static Future<_Harness> create() async {
    final h = _Harness();
    await h.security.initialize(hasWallet: true);
    h.security.updateWallet(_id);
    await h.security.unlock();
    h.runtime = WalletRuntime(
      FakeWalletEngineFactory([h.engine]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(h.secrets),
      _services,
    );
    final profile = WalletProfile(
      id: _id,
      name: 'Fixture',
      createdAt: _now,
      updatedAt: _now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.provisioning,
      storageToken: _token,
    );
    expect(
      await h.runtime.provision(
        profile: profile,
        mnemonic: 'fixture words',
        databasePassword: 'fixture-password',
      ),
      isA<AppSuccess<void>>(),
    );
    final profiles = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      clock: () => _now,
    );
    h.repository = WalletRepository(
      profiles,
      h.runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: _id),
      _services,
      clock: () => _now,
      paymentJournalStore: h.journal,
      securityController: h.security,
    );
    return h;
  }

  Future<AppResult<WalletSendResult>> send() => repository.sendPayment(
    target: WalletPaymentTarget.bitcoinOnchain,
    destination: bech32_codec.bech32.encode(
      bech32_codec.Decoded(
        prefix: 'bcrt',
        words: Uint8List.fromList([
          0,
          ...bech32_codec.bech32.toWords(Uint8List(20)),
        ]),
      ),
    ),
    amountUnits: 1000,
    reviewedFeeRate: _review,
    expectedWalletId: _id,
  );

  Future<void> dispose() async {
    await repository.dispose();
    security.dispose();
  }
}

final class _Device implements DeviceAuthentication {
  @override
  Future<DeviceSecurityStatus> status() async => DeviceSecurityStatus.secured;
  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) async =>
      DeviceAuthenticationResult.authenticated;
  @override
  Future<void> cancel() async {}
  @override
  Future<void> setSensitive(bool sensitive) async {}
  @override
  Stream<bool> get captureChanges => const Stream.empty();
  @override
  bool get isCaptured => false;
}

final class _CountingSecrets implements SecureKeyValueStore {
  final delegate = MemorySecureStore();
  var reads = 0;
  @override
  Future<bool> containsKey({required String key}) =>
      delegate.containsKey(key: key);
  @override
  Future<void> delete({required String key}) => delegate.delete(key: key);
  @override
  Future<Set<String>> keys() => delegate.keys();
  @override
  Future<String?> read({required String key}) {
    reads++;
    return delegate.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) =>
      delegate.write(key: key, value: value);
}
