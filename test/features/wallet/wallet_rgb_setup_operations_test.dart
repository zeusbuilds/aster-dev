import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/repository/wallet_rgb_setup_operations.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/wallet_fakes.dart';

const _id = '11111111111111111111111111111111';
const _token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
  usdtAsset: RgbAssetConfiguration(
    contractId: 'rgb:configured-usdt',
    precision: 6,
  ),
);
final _tx = 'a' * 64;
final _oldTx = 'b' * 64;

final class _Engine extends Mock
    implements WalletEngine, RgbSetupWalletEngine {}

final class _Factory implements WalletEngineFactory {
  _Factory(this.engine);
  final WalletEngine engine;
  @override
  WalletEngine create(WalletEngineConfiguration configuration) => engine;
}

final class _Store implements RgbWalletSetupStore {
  final documents = <String, String>{};
  int writes = 0;
  int? failWrite;
  bool commitBeforeError = false;
  void Function(String document)? onWrite;
  @override
  Future<String?> read(String walletId) async => documents[walletId];
  @override
  Future<void> write(String walletId, String document) async {
    writes++;
    if (writes == failWrite) {
      if (commitBeforeError) documents[walletId] = document;
      throw StateError('Injected durable write failure');
    }
    documents[walletId] = document;
    onWrite?.call(document);
  }
}

final class _Harness {
  final engine = _Engine();
  final store = _Store();
  RgbWalletSetupStore? overrideStore;
  RgbWalletSetupStore get activeStore => overrideStore ?? store;
  final profiles = WalletProfileStore(MemoryWalletRegistryDocumentStore());
  late final WalletRuntime runtime;
  late WalletRgbSetupOperations operations;
  DateTime now = DateTime.utc(2026, 10, 15);
  List<RgbWalletSetupTransaction> history = [];
  int free = 0;
  int spendable = 2000000;
  String fingerprint = 'c' * 64;
  String node = '02${'d' * 64}';
  int dispatches = 0;
  bool nativeThrows = false;
  Future<void> Function()? dispatch;
  Completer<void>? historyGate;
  int reviewNumber = 1;

  Future<void> open() async {
    when(
      () => engine.provision(
        databasePassword: any(named: 'databasePassword'),
        mnemonic: any(named: 'mnemonic'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => engine.openPersisted(
        databasePassword: any(named: 'databasePassword'),
      ),
    ).thenAnswer((_) async {});
    when(engine.shutdown).thenAnswer((_) async {});
    when(engine.destroy).thenAnswer((_) async {});
    when(engine.rgbSetupInventory).thenAnswer(
      (_) async => RgbWalletSetupInventory(
        freeAllocationCount: free,
        vanillaSpendableSats: spendable,
        runtimeFingerprint: fingerprint,
        nodePublicKey: node,
      ),
    );
    when(engine.rgbSetupTransactions).thenAnswer((_) async {
      await historyGate?.future;
      return List.of(history);
    });
    when(() => engine.estimateFeeRate(6)).thenAnswer(
      (_) async => WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 20,
        observedAt: now,
      ),
    );
    when(() => engine.createRgbSetupOutputs(any())).thenAnswer((_) async {
      dispatches++;
      // Native cannot be entered without the durable committing marker.
      expect(
        (jsonDecode((await activeStore.read(_id))!)
            as Map<String, Object?>)['phase'],
        'committing',
      );
      if (dispatch != null) await dispatch!();
      if (nativeThrows) throw StateError('Lost acknowledgement');
    });
    runtime = WalletRuntime(
      _Factory(engine),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      _services,
    );
    final profile = WalletProfile(
      id: _id,
      name: 'QA wallet',
      createdAt: now,
      updatedAt: now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.provisioning,
      storageToken: _token,
    );
    expect(
      await profiles.stageProvision(profile),
      isA<AppSuccess<WalletRegistry>>(),
    );
    expect(
      await profiles.commitProvision(_id),
      isA<AppSuccess<WalletRegistry>>(),
    );
    expect(
      await runtime.provision(
        profile: profile,
        mnemonic: 'fixture words',
        databasePassword: 'fixture password',
      ),
      isA<AppSuccess<void>>(),
    );
    restartOperations();
  }

  void restartOperations() {
    operations = WalletRgbSetupOperations(
      runtime,
      profiles,
      _services,
      activeStore,
      newId: () => '${reviewNumber++}'.padLeft(32, '0'),
      clock: () => now,
    );
  }

  Future<RgbWalletSetupReview> prepare() async =>
      (await operations.prepare() as AppSuccess<RgbWalletSetupReview>).value;
  Future<RgbWalletSetupStatus> status() async =>
      (await operations.status() as AppSuccess<RgbWalletSetupStatus>).value;
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      WalletSendCommand(
        route: const PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.onchain,
        ),
        destination: 'fixture',
        amount: WalletAmount.onchain(
          assetId: WalletAsset.bitcoin.id,
          units: 100,
        ),
        feeRate: WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 20,
          observedAt: DateTime.utc(2026, 10, 15),
        ),
      ),
    );
  });
  late _Harness h;
  setUp(() async {
    h = _Harness();
    await h.open();
  });
  tearDown(() => h.runtime.dispose());

  test(
    'delete guard reconciles completed preparation without repeating it',
    () async {
      final review = await h.prepare();
      h.dispatch = () async {
        h.history = [RgbWalletSetupTransaction(txid: _tx, confirmed: false)];
      };
      await h.operations.confirm(review);
      final profile = (await h.profiles.read() as AppSuccess<WalletRegistry>)
          .value
          .activeProfile!;
      expect(
        await h.operations.assertWalletDeletionSafe(profile),
        isA<AppFailureResult<void>>(),
      );
      h.history = [RgbWalletSetupTransaction(txid: _tx, confirmed: true)];
      expect(
        await h.operations.assertWalletDeletionSafe(profile),
        isA<AppSuccess<void>>(),
      );
      expect(h.dispatches, 1);
    },
  );

  test(
    'cancel persists without any native mutation; a fresh review is required',
    () async {
      final review = await h.prepare();
      expect(await h.operations.cancel(review), isA<AppSuccess<void>>());
      expect(h.dispatches, 0);
      expect(
        await h.operations.confirm(review),
        isA<AppFailureResult<RgbWalletSetupStatus>>(),
      );
      expect(h.dispatches, 0);
      expect((await h.prepare()).id, isNot(review.id));
    },
  );

  test('confirmed setup is dispatched once and consumed outputs allow a new review', () async {
    h.history = [RgbWalletSetupTransaction(txid: _oldTx, confirmed: true)];
    final review = await h.prepare();
    h.dispatch = () async {
      h.history.add(RgbWalletSetupTransaction(txid: _tx, confirmed: true));
      h.free = 4;
    };
    final result =
        await h.operations.confirm(review) as AppSuccess<RgbWalletSetupStatus>;
    expect(result.value.phase, RgbWalletSetupPhase.ready);
    expect(result.value.transactionId, _tx);
    expect(h.dispatches, 1);
    expect(
      await h.operations.confirm(review),
      isA<AppFailureResult<RgbWalletSetupStatus>>(),
    );
    h.free = 0;
    expect((await h.status()).phase, RgbWalletSetupPhase.required);
    expect(
      await h.operations.prepare(),
      isA<AppSuccess<RgbWalletSetupReview>>(),
    );
    expect(h.dispatches, 1);
  });

  test('lost native acknowledgement stays blocked across restart and reconciles exactly one transaction', () async {
    final review = await h.prepare();
    h.nativeThrows = true;
    final result =
        await h.operations.confirm(review) as AppSuccess<RgbWalletSetupStatus>;
    expect(result.value.phase, RgbWalletSetupPhase.indeterminate);
    expect(await h.operations.assertResolved(), isA<AppFailureResult<void>>());
    h.restartOperations();
    expect(
      await h.operations.prepare(),
      isA<AppFailureResult<RgbWalletSetupReview>>(),
    );
    expect((await h.status()).phase, RgbWalletSetupPhase.indeterminate);
    h.history = [RgbWalletSetupTransaction(txid: _tx, confirmed: false)];
    expect((await h.status()).phase, RgbWalletSetupPhase.pending);
    h.history = [RgbWalletSetupTransaction(txid: _tx, confirmed: true)];
    h.free = 4;
    expect((await h.status()).phase, RgbWalletSetupPhase.ready);
    expect(await h.operations.assertResolved(), isA<AppSuccess<void>>());
    expect(h.dispatches, 1);
  });

  test(
    'ambiguous transaction set and missing baseline never resolve or retry',
    () async {
      h.history = [RgbWalletSetupTransaction(txid: _oldTx, confirmed: true)];
      final review = await h.prepare();
      h.nativeThrows = true;
      await h.operations.confirm(review);
      h.history = [
        RgbWalletSetupTransaction(txid: _oldTx, confirmed: true),
        RgbWalletSetupTransaction(txid: _tx, confirmed: true),
        RgbWalletSetupTransaction(txid: 'e' * 64, confirmed: true),
      ];
      expect((await h.status()).phase, RgbWalletSetupPhase.indeterminate);
      h.history = [RgbWalletSetupTransaction(txid: _tx, confirmed: true)];
      expect((await h.status()).phase, RgbWalletSetupPhase.indeterminate);
      expect(
        await h.operations.assertResolved(),
        isA<AppFailureResult<void>>(),
      );
      expect(h.dispatches, 1);
    },
  );

  test(
    'uncertain marker write never enters native and remains blocked',
    () async {
      final review = await h.prepare();
      h.store.failWrite = h.store.writes + 1;
      h.store.commitBeforeError = true;
      expect(
        await h.operations.confirm(review),
        isA<AppFailureResult<RgbWalletSetupStatus>>(),
      );
      expect(h.dispatches, 0);
      h.restartOperations();
      expect(
        await h.operations.assertResolved(),
        isA<AppFailureResult<void>>(),
      );
      expect((await h.status()).phase, RgbWalletSetupPhase.indeterminate);
    },
  );

  test(
    'lost acknowledgement journal write reconciles without redispatch',
    () async {
      final review = await h.prepare();
      h.store.failWrite = h.store.writes + 2;
      h.dispatch = () async {
        h.history = [RgbWalletSetupTransaction(txid: _tx, confirmed: true)];
        h.free = 4;
      };
      final result = await h.operations.confirm(
        review,
      ) as AppSuccess<RgbWalletSetupStatus>;
      expect(result.value.phase, RgbWalletSetupPhase.indeterminate);
      h.restartOperations();
      expect((await h.status()).phase, RgbWalletSetupPhase.ready);
      expect(h.dispatches, 1);
    },
  );

  test('restart, expiry, and runtime identity changes reject an old review before native', () async {
    var review = await h.prepare();
    h.restartOperations();
    expect(
      await h.operations.confirm(review),
      isA<AppFailureResult<RgbWalletSetupStatus>>(),
    );
    review = await h.prepare();
    h.now = h.now.add(RgbWalletSetupReview.lifetime);
    expect(
      await h.operations.confirm(review),
      isA<AppFailureResult<RgbWalletSetupStatus>>(),
    );
    review = await h.prepare();
    h.fingerprint = 'e' * 64;
    expect(
      await h.operations.confirm(review),
      isA<AppFailureResult<RgbWalletSetupStatus>>(),
    );
    expect(h.dispatches, 0);
  });

  test(
    'expiry during native preflight rejects before marker and dispatch',
    () async {
      final review = await h.prepare();
      h.historyGate = Completer<void>();
      final confirmation = h.operations.confirm(review);
      await Future<void>.delayed(Duration.zero);
      h.now = h.now.add(RgbWalletSetupReview.lifetime);
      h.historyGate!.complete();
      expect(await confirmation, isA<AppFailureResult<RgbWalletSetupStatus>>());
      expect(
        (jsonDecode(h.store.documents[_id]!) as Map<String, Object?>)['phase'],
        'review',
      );
      expect(h.dispatches, 0);
    },
  );

  test(
    'expiry during marker persistence cancels known-undispatched setup',
    () async {
      final review = await h.prepare();
      h.store.onWrite = (document) {
        if ((jsonDecode(document) as Map<String, Object?>)['phase'] ==
            'committing') {
          h.now = h.now.add(RgbWalletSetupReview.lifetime);
        }
      };
      expect(
        await h.operations.confirm(review),
        isA<AppFailureResult<RgbWalletSetupStatus>>(),
      );
      expect(
        (jsonDecode(h.store.documents[_id]!) as Map<String, Object?>)['phase'],
        'cancelled',
      );
      expect(h.dispatches, 0);
    },
  );

  test('suspend and reopen invalidates the reviewed runtime session', () async {
    final review = await h.prepare();
    expect(await h.runtime.suspend(), isA<AppSuccess<void>>());
    expect(await h.runtime.resume(), isA<AppSuccess<void>>());
    expect(
      await h.operations.confirm(review),
      isA<AppFailureResult<RgbWalletSetupStatus>>(),
    );
    expect(h.dispatches, 0);
  });

  test(
    'funding floor and preexisting pending setup fail before dispatch',
    () async {
      h.spendable = 80000;
      expect(
        await h.operations.prepare(),
        isA<AppFailureResult<RgbWalletSetupReview>>(),
      );
      h.spendable = 2000000;
      h.history = [RgbWalletSetupTransaction(txid: _oldTx, confirmed: false)];
      expect(
        await h.operations.prepare(),
        isA<AppFailureResult<RgbWalletSetupReview>>(),
      );
      expect(h.dispatches, 0);
    },
  );

  test(
    'a corrupt newer financial slot cannot fall back to an older review',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rgb-setup-journal-',
      );
      addTearDown(() => directory.delete(recursive: true));
      h.overrideStore = IoRgbWalletSetupStore(
        directory.path,
        MemoryWalletStorageSecurity(),
      );
      h.restartOperations();
      final review = await h.prepare();
      h.nativeThrows = true;
      expect(
        (await h.operations.confirm(
          review,
        ) as AppSuccess<RgbWalletSetupStatus>).value.phase,
        RgbWalletSetupPhase.indeterminate,
      );
      expect(h.dispatches, 1);
      await File('${directory.path}/$_id/wallet_registry.b.json')
          .writeAsString('{corrupt marker', flush: true);
      h.restartOperations();
      expect(
        await h.operations.status(),
        isA<AppFailureResult<RgbWalletSetupStatus>>(),
      );
      expect(
        await h.operations.prepare(),
        isA<AppFailureResult<RgbWalletSetupReview>>(),
      );
      expect(
        await h.operations.confirm(review),
        isA<AppFailureResult<RgbWalletSetupStatus>>(),
      );
      expect(
        await h.operations.assertResolved(),
        isA<AppFailureResult<void>>(),
      );
      expect(h.dispatches, 1);
    },
  );

  test('confirmed setup losing confirmation is quarantined again before another action', () async {
    final review = await h.prepare();
    h.dispatch = () async {
      h.history = [RgbWalletSetupTransaction(txid: _tx, confirmed: true)];
      h.free = 4;
    };
    await h.operations.confirm(review);
    h.history = [];
    expect(await h.operations.assertResolved(), isA<AppFailureResult<void>>());
    expect(
      await h.operations.prepare(),
      isA<AppFailureResult<RgbWalletSetupReview>>(),
    );
    expect(h.dispatches, 1);
  });

  test('real repository gates BTC send, RGB send and RGB receive while setup is unresolved', () async {
    final review = await h.prepare();
    h.nativeThrows = true;
    await h.operations.confirm(review);
    final repository = WalletRepository(
      h.profiles,
      h.runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: _id),
      _services,
      rgbSetupStore: h.activeStore,
    );
    for (final confirmed in <bool?>[null, false]) {
      h.history = confirmed == null
          ? []
          : [RgbWalletSetupTransaction(txid: _tx, confirmed: confirmed)];
      final btc = await repository.sendPayment(
        target: WalletPaymentTarget.bitcoinOnchain,
        destination: 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
        amountUnits: 20000,
      );
      final rgb = await repository.sendPayment(
        target: WalletPaymentTarget.usdtOnchain,
        destination: 'rgb:first-invoice',
        amountUnits: 1000000,
      );
      final receive = await repository.createReceiveRequest(
        WalletPaymentTarget.usdtOnchain,
      );
      expect(btc, isA<AppFailureResult<WalletSendResult>>());
      expect(rgb, isA<AppFailureResult<WalletSendResult>>());
      expect(receive, isA<AppFailureResult<WalletReceiveRequest>>());
      expect(
        (btc as AppFailureResult<WalletSendResult>).failure.code,
        'rgb_wallet_setup_pending',
      );
      expect(
        (rgb as AppFailureResult<WalletSendResult>).failure.code,
        'rgb_wallet_setup_pending',
      );
      expect(
        (receive as AppFailureResult<WalletReceiveRequest>).failure.code,
        'rgb_wallet_setup_pending',
      );
    }
    verifyNever(() => h.engine.sendPayment(any()));
    verifyNever(
      () => h.engine.createReceiveRequest(
        PaymentRoute(
          asset: WalletAsset.rgbUsdt(
            assetId: 'rgb:configured-usdt',
            precision: 6,
          ),
          rail: PaymentRail.onchain,
        ),
        amount: null,
      ),
    );
    expect(h.dispatches, 1);
  });

  test('corrupt journal and wallet/network mismatch fail closed', () async {
    final review = await h.prepare();
    final document =
        jsonDecode(h.store.documents[_id]!) as Map<String, dynamic>;
    (document['review'] as Map<String, dynamic>)['network'] = 'mainnet';
    h.store.documents[_id] = jsonEncode(document);
    expect(
      await h.operations.confirm(review),
      isA<AppFailureResult<RgbWalletSetupStatus>>(),
    );
    expect(await h.operations.assertResolved(), isA<AppFailureResult<void>>());
    h.store.documents[_id] = '{malformed';
    expect(
      await h.operations.prepare(),
      isA<AppFailureResult<RgbWalletSetupReview>>(),
    );
    expect(h.dispatches, 0);
  });
}
