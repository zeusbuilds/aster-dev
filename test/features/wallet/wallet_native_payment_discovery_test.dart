import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/wallet_payment_submissions.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wallet_fakes.dart';

const _walletId = '11111111111111111111111111111111';
const _operationId = '22222222222222222222222222222222';
const _token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _request = 'native-authenticated-canonical-envelope-fixture';
const _txid =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

final class _DiscoveryEngine extends FakeWalletEngine
    implements WalletPaymentDiscoveryEngine {
  _DiscoveryEngine(this.command);
  final WalletSendCommand command;
  var phase = WalletPaymentRecoveryPhase.committing;
  var duplicateInventory = false;

  WalletPaymentRecoveryStatus get nativeStatus => WalletPaymentRecoveryStatus(
    phase: phase,
    endAuthorized:
        phase == WalletPaymentRecoveryPhase.committing ||
        phase == WalletPaymentRecoveryPhase.accepted,
    referenceId: _txid,
  );

  @override
  Future<List<WalletDiscoveredPaymentOperation>>
  discoverPendingPaymentOperations() async {
    final operation = WalletDiscoveredPaymentOperation(
      operationId: _operationId,
      request: _request,
      command: command,
      status: nativeStatus,
    );
    return [operation, if (duplicateInventory) operation];
  }

  @override
  Future<void> validateDiscoveredPaymentOperation(
    String request,
    String operationId,
    WalletSendCommand restored,
  ) async {
    calls.add('validateDiscoveredPaymentOperation');
    if (request != _request ||
        operationId != _operationId ||
        restored != command) {
      throw const StoredDataCorruptionException();
    }
  }

  @override
  Future<WalletPaymentRecoveryStatus> inspectPaymentOperation(
    String request,
  ) async {
    calls.add('inspectPaymentOperation');
    if (request != _request) throw const StoredDataCorruptionException();
    return nativeStatus;
  }

  @override
  Future<WalletPaymentRecoveryStatus> cancelPaymentOperation(
    String request,
  ) async {
    calls.add('cancelPaymentOperation');
    if (request != _request || nativeStatus.endAuthorized) {
      throw const StoredDataCorruptionException();
    }
    phase = WalletPaymentRecoveryPhase.rejected;
    return nativeStatus;
  }

  @override
  Future<WalletPaymentRecoveryStatus> preparePaymentOperation(
    String request,
  ) async {
    fail('Discovery must never Prepare');
  }

  @override
  Future<WalletPaymentRecoveryStatus> commitPaymentOperation(
    String request,
  ) async {
    fail('Discovery must never Commit');
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 7);
  final command = WalletSendCommand(
    route: PaymentRoute(asset: WalletAsset.bitcoin, rail: PaymentRail.onchain),
    destination: 'native-approved-address-fixture',
    amount: WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: 1000),
    feeRate: WalletFeeRateEstimate(
      targetBlocks: null,
      satsPerVbyte: 1,
      observedAt: now,
      source: WalletFeeRateSource.nativeRecovery,
    ),
  );
  final profile = WalletProfile(
    id: _walletId,
    name: 'Fixture',
    createdAt: now,
    updatedAt: now,
    environment: BlockchainEnvironment.regtest,
    state: WalletProfileState.ready,
    storageToken: _token,
  );

  Future<
    ({
      WalletRuntime runtime,
      WalletPaymentSubmissions submissions,
      MemoryWalletPaymentJournalStore store,
      _DiscoveryEngine engine,
    })
  >
  fixture({MemoryWalletPaymentJournalStore? existingStore}) async {
    final store = existingStore ?? MemoryWalletPaymentJournalStore();
    final secrets = WalletSecretStore(MemorySecureStore());
    await secrets.write(
      _walletId,
      const WalletSecret(
        databasePassword: 'fixture',
        mnemonic: 'fixture-mnemonic',
        storageToken: _token,
      ),
    );
    final engine = _DiscoveryEngine(command);
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      FakeWalletDirectoryManager()..storageTokens[_walletId] = _token,
      secrets,
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
      ),
    );
    addTearDown(runtime.dispose);
    expect(await runtime.restore(profile), isA<AppSuccess<void>>());
    return (
      runtime: runtime,
      store: store,
      engine: engine,
      submissions: WalletPaymentSubmissions(
        runtime,
        store,
        receipts: store,
        newId: () => '3' * 32,
        clock: () => now,
      ),
    );
  }

  test('lost app marker restores exact native intent and never authorizes Commit', () async {
    final f = await fixture();
    await f.submissions.restoreFence();
    expect(f.runtime.hasPaymentSubmissionFence, isTrue);
    var record =
        (await f.submissions.status() as AppSuccess<WalletPaymentSubmission?>)
            .value!;
    expect(record.nativeDiscovered, isTrue);
    expect(record.journalVersion, 4);
    expect(record.command, command);
    expect(record.recoveryRequest, _request);
    expect(record.outcome, WalletPaymentSubmissionOutcome.unknown);
    // Even a deliberate Resume is observation-only for reconstructed evidence.
    expect(await f.submissions.resume(), isA<AppFailureResult<void>>());
    expect(f.runtime.hasPaymentSubmissionFence, isTrue);
    f.engine.phase = WalletPaymentRecoveryPhase.accepted;
    expect(await f.submissions.reconcile(), isA<AppSuccess<void>>());
    expect(f.runtime.hasPaymentSubmissionFence, isFalse);
    record =
        (await f.submissions.status() as AppSuccess<WalletPaymentSubmission?>)
            .value!;
    expect(record.phase, WalletPaymentSubmissionPhase.accepted);
    expect(record.result!.amount.units, 1000);
    expect(record.result!.status, WalletPaymentStatus.pending);
    expect(f.store.receiptDocuments[_walletId], hasLength(1));
    expect(
      f.engine.calls.where((name) => name == 'cancelPaymentOperation'),
      isEmpty,
    );
  });

  test(
    'native precommit preparation may be safely cancelled without dispatch',
    () async {
      final f = await fixture();
      f.engine.phase = WalletPaymentRecoveryPhase.prepared;
      await f.submissions.restoreFence();
      expect(
        (await f.submissions.status() as AppSuccess<WalletPaymentSubmission?>)
            .value!
            .outcome,
        WalletPaymentSubmissionOutcome.notSubmitted,
      );
      expect(await f.submissions.reconcile(), isA<AppSuccess<void>>());
      expect(f.runtime.hasPaymentSubmissionFence, isFalse);
      expect(
        (await f.submissions.status() as AppSuccess<WalletPaymentSubmission?>)
            .value!
            .phase,
        WalletPaymentSubmissionPhase.rejected,
      );
      expect(
        f.engine.calls.where((name) => name == 'cancelPaymentOperation'),
        hasLength(1),
      );
    },
  );

  test('a restart preserves native origin and cannot grant Commit', () async {
    final first = await fixture();
    await first.submissions.restoreFence();
    final restarted = await fixture(existingStore: first.store);
    await restarted.submissions.restoreFence();
    expect(await restarted.submissions.resume(), isA<AppFailureResult<void>>());
    expect(restarted.runtime.hasPaymentSubmissionFence, isTrue);
    expect(restarted.store.writes, hasLength(1));
  });

  test(
    'lost journal-write acknowledgement never repeats native dispatch',
    () async {
      final f = await fixture();
      f.store.failWriteNumber = 1;
      await expectLater(
        f.submissions.restoreFence(),
        throwsA(isA<DurableStorageCommitException>()),
      );
      expect(f.runtime.hasPaymentSubmissionFence, isTrue);
      expect(f.store.documents, isEmpty);
      f.engine.phase = WalletPaymentRecoveryPhase.accepted;
      expect(await f.submissions.reconcile(), isA<AppSuccess<void>>());
      expect(f.runtime.hasPaymentSubmissionFence, isFalse);
      expect(f.store.receiptDocuments[_walletId], hasLength(1));
    },
  );

  test('multiple native pending intents cannot be silently selected', () async {
    final f = await fixture();
    f.engine.duplicateInventory = true;
    await expectLater(
      f.submissions.restoreFence(),
      throwsA(isA<StoredDataCorruptionException>()),
    );
    expect(f.store.writes, isEmpty);
  });
}
