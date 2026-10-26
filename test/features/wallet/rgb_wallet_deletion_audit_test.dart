import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

final class _Wallet extends Mock implements UtexoWallet {}

final class _AuditStopwatch extends Mock implements Stopwatch {}

const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
);
final _now = DateTime.utc(2026, 10, 26);

void main() {
  late _Wallet wallet;
  late RgbWalletEngine engine;
  setUp(() {
    wallet = _Wallet();
    engine = RgbWalletEngine(
      wallet,
      _services,
      UtexoUnlockConfig(),
      clock: () => _now,
    );
    when(() => wallet.refreshTransfers())
        .thenAnswer((_) async => RefreshTransfersResult(transfers: const {}));
    when(() => wallet.listAssets())
        .thenAnswer((_) async => _assets(['rgb:fixture']));
    when(() => wallet.getAssetBalance(any()))
        .thenAnswer((_) async => _balance());
    when(() => wallet.listTransfers(assetId: any(named: 'assetId')))
        .thenAnswer((_) async => []);
    when(() => wallet.listTransfers()).thenThrow(
      const BadRequestError('either asset_id or txid must be provided'),
    );
    when(() => wallet.listTransfers(assetId: 'rgb:fixture'))
        .thenAnswer((_) async => []);
  });

  tearDown(() {
    verifyNever(() => wallet.listTransfers());
  });

  test(
    'unassigned unchanged receive is protected despite zero imported assets',
    () async {
      when(() => wallet.listAssets()).thenAnswer((_) async => _assets());
      when(() => wallet.refreshTransfers()).thenAnswer(
        (_) async =>
            RefreshTransfersResult(transfers: const {7: RefreshedTransfer()}),
      );
      when(() => wallet.failTransfers(noAssetOnly: true))
          .thenAnswer((_) async => false);
      expect(await engine.hasProtectedRgbState(), isTrue);
      verify(() => wallet.failTransfers(noAssetOnly: true)).called(1);
      verify(() => wallet.refreshTransfers()).called(2);
    },
  );

  test('native expired unassigned sweep and fresh empty waiting map permit removal', () async {
    var expired = false;
    when(() => wallet.listAssets()).thenAnswer((_) async => _assets());
    when(() => wallet.refreshTransfers()).thenAnswer(
      (_) async => RefreshTransfersResult(
        transfers: expired ? const {} : const {7: RefreshedTransfer()},
      ),
    );
    when(() => wallet.failTransfers(noAssetOnly: true)).thenAnswer((_) async {
      expired = true;
      return true;
    });
    expect(await engine.hasProtectedRgbState(), isFalse);
  });

  test(
    'unassigned sweep acknowledgement alone never proves a terminal outcome',
    () async {
      when(() => wallet.listAssets()).thenAnswer((_) async => _assets());
      when(() => wallet.refreshTransfers()).thenAnswer(
        (_) async =>
            RefreshTransfersResult(transfers: const {7: RefreshedTransfer()}),
      );
      when(() => wallet.failTransfers(noAssetOnly: true))
          .thenAnswer((_) async => true);
      expect(await engine.hasProtectedRgbState(), isTrue);
    },
  );

  test('unassigned expiry reconciliation can import funds and must recheck holdings', () async {
    var received = false;
    when(() => wallet.listAssets())
        .thenAnswer((_) async => _assets(received ? ['rgb:first'] : []));
    when(() => wallet.refreshTransfers()).thenAnswer(
      (_) async => RefreshTransfersResult(
        transfers: received ? const {} : const {7: RefreshedTransfer()},
      ),
    );
    when(() => wallet.failTransfers(noAssetOnly: true)).thenAnswer((_) async {
      received = true;
      return true;
    });
    when(() => wallet.getAssetBalance('rgb:first'))
        .thenAnswer((_) async => _balance('settled'));
    expect(await engine.hasProtectedRgbState(), isTrue);
    verify(() => wallet.getAssetBalance('rgb:first')).called(1);
  });

  test(
    'failed refresh after unassigned sweep never authorizes deletion',
    () async {
      var swept = false;
      when(() => wallet.listAssets()).thenAnswer((_) async => _assets());
      when(() => wallet.refreshTransfers()).thenAnswer(
        (_) async => RefreshTransfersResult(
          transfers: swept
              ? const {
                  7: RefreshedTransfer(
                    failure: RefreshFailure(name: 'Network', message: 'hidden'),
                  ),
                }
              : const {7: RefreshedTransfer()},
        ),
      );
      when(() => wallet.failTransfers(noAssetOnly: true)).thenAnswer((_) async {
        swept = true;
        return true;
      });
      await expectLater(
        engine.hasProtectedRgbState(),
        throwsA(isA<AppFailureException>()),
      );
    },
  );

  test('native audit invalid request uses audit copy rather than input-validation copy', () async {
    when(() => wallet.refreshTransfers())
        .thenThrow(const BadRequestError('native contract failure'));
    await expectLater(
      engine.hasProtectedRgbState(),
      throwsA(
        isA<AppFailureException>()
            .having(
              (error) => error.failure.code,
              'owned code',
              'wallet_deletion_audit_unavailable',
            )
            .having(
              (error) => error.failure.userMessage,
              'copy',
              'Wallet assets could not be checked. Try again later.',
            ),
      ),
    );
  });

  test(
    'initiated scoped transfer remains protected when refresh excludes it',
    () async {
      when(() => wallet.listTransfers(assetId: 'rgb:fixture')).thenAnswer(
        (_) async => [
          _transfer(status: CoreTransferStatuses.initiated, kind: 'Send'),
        ],
      );
      expect(await engine.hasProtectedRgbState(), isTrue);
    },
  );

  for (final status in [
    CoreTransferStatuses.waitingCounterparty,
    CoreTransferStatuses.waitingSafeHeight,
    CoreTransferStatuses.waitingBroadcast,
    CoreTransferStatuses.waitingConfirmations,
  ]) {
    test(
      'unassigned explicit $status stays protected after a refused sweep',
      () async {
        when(() => wallet.listAssets()).thenAnswer((_) async => _assets());
        when(() => wallet.refreshTransfers()).thenAnswer(
          (_) async => RefreshTransfersResult(
            transfers: {7: RefreshedTransfer(updatedStatus: status)},
          ),
        );
        when(() => wallet.failTransfers(noAssetOnly: true))
            .thenAnswer((_) async => false);
        expect(await engine.hasProtectedRgbState(), isTrue);
      },
    );
  }

  test(
    'native audit deadline marks owner for serialized reopen on explicit retry',
    () async {
      when(() => wallet.refreshTransfers()).thenThrow(
        const RlnOperationTimeoutException(
          operation: 'rlnRefreshTransfers',
          timeout: Duration(minutes: 2),
        ),
      );
      await expectLater(
        engine.hasProtectedRgbState(),
        throwsA(isA<AppFailureException>()),
      );
      expect(engine.requiresPaymentReopen, isTrue);
      verifyNever(() => wallet.listAssets());
    },
  );

  test(
    'aggregate budget ends completed work without poisoning native owner',
    () async {
      var elapsed = Duration.zero;
      final timer = _AuditStopwatch();
      when(() => timer.elapsed).thenAnswer((_) => elapsed);
      engine = RgbWalletEngine(
        wallet,
        _services,
        UtexoUnlockConfig(),
        deletionAuditStopwatch: () => timer,
      );
      when(() => wallet.refreshTransfers()).thenAnswer((_) async {
        elapsed = const Duration(seconds: 61);
        return RefreshTransfersResult(transfers: const {});
      });
      await expectLater(
        engine.hasProtectedRgbState(),
        throwsA(isA<AppFailureException>()),
      );
      expect(engine.requiresPaymentReopen, isFalse);
      verifyNever(() => wallet.listAssets());
      verifyNever(() => wallet.listTransfers(assetId: 'rgb:fixture'));
      verify(() => timer.stop()).called(1);
    },
  );

  test('aggregate budget never releases an unfinished native future', () async {
    var elapsed = Duration.zero;
    final timer = _AuditStopwatch();
    when(() => timer.elapsed).thenAnswer((_) => elapsed);
    engine = RgbWalletEngine(
      wallet,
      _services,
      UtexoUnlockConfig(),
      deletionAuditStopwatch: () => timer,
    );
    final native = Completer<RefreshTransfersResult>();
    when(() => wallet.refreshTransfers()).thenAnswer((_) => native.future);
    var settled = false;
    final audit = engine.hasProtectedRgbState();
    unawaited(
      audit.then(
        (_) {
          settled = true;
        },
        onError: (Object _) {
          settled = true;
        },
      ),
    );
    elapsed = const Duration(minutes: 5);
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    verifyNever(() => wallet.listTransfers(assetId: 'rgb:fixture'));
    native.complete(RefreshTransfersResult(transfers: const {}));
    await expectLater(audit, throwsA(isA<AppFailureException>()));
    expect(settled, isTrue);
  });

  test('five thousand asset audit stops dispatching when cumulative budget is used', () async {
    var elapsed = Duration.zero;
    var balances = 0;
    final timer = _AuditStopwatch();
    when(() => timer.elapsed).thenAnswer((_) => elapsed);
    engine = RgbWalletEngine(
      wallet,
      _services,
      UtexoUnlockConfig(),
      deletionAuditStopwatch: () => timer,
    );
    when(() => wallet.listAssets()).thenAnswer(
      (_) async => _assets(List.generate(5000, (index) => 'rgb:$index')),
    );
    when(() => wallet.getAssetBalance(any())).thenAnswer((_) async {
      balances++;
      elapsed += const Duration(seconds: 20);
      return _balance();
    });
    await expectLater(
      engine.hasProtectedRgbState(),
      throwsA(isA<AppFailureException>()),
    );
    expect(balances, 3);
    expect(engine.requiresPaymentReopen, isFalse);
  });

  test(
    'native expiry reconciliation discovers a funded receive and protects it',
    () async {
      var progressed = false;
      when(() => wallet.listTransfers(assetId: 'rgb:fixture')).thenAnswer(
        (_) async => [
          progressed
              ? _transfer(
                  status: CoreTransferStatuses.waitingConfirmations,
                  txid: 'a' * 64,
                  assignments: [
                    Assignment(type: 'Fungible', amount: BigInt.one),
                  ],
                )
              : _transfer(),
        ],
      );
      when(() => wallet.failTransfers(batchTransferIdx: 7))
          .thenAnswer((_) async {
            progressed = true;
            return true;
          });
      expect(await engine.hasProtectedRgbState(), isTrue);
    },
  );

  test('empty native inventory permits removal without sending', () async {
    when(() => wallet.listAssets()).thenAnswer((_) async => _assets());
    expect(await engine.hasProtectedRgbState(), isFalse);
    verifyInOrder([
      () => wallet.refreshTransfers(),
      () => wallet.listAssets(),
      () => wallet.listAssets(),
    ]);
    verifyNoMoreInteractions(wallet);
  });

  for (final field in [
    'settled',
    'future',
    'spendable',
    'outbound',
    'inbound',
  ]) {
    test(
      'any native $field holdings on an unconfigured contract block deletion',
      () async {
        when(() => wallet.listAssets())
            .thenAnswer((_) async => _assets(['rgb:other']));
        when(() => wallet.getAssetBalance('rgb:other'))
            .thenAnswer((_) async => _balance(field));
        expect(await engine.hasProtectedRgbState(), isTrue);
      },
    );
  }

  test(
    'a per-batch refresh failure blocks deletion despite stale zero state',
    () async {
      when(() => wallet.refreshTransfers()).thenAnswer(
        (_) async => RefreshTransfersResult(
          transfers: const {
            4: RefreshedTransfer(
              failure: RefreshFailure(
                name: 'Network',
                message: 'private payload',
              ),
            ),
          },
        ),
      );
      await expectLater(
        engine.hasProtectedRgbState(),
        throwsA(isA<AppFailureException>()),
      );
      verifyNever(() => wallet.listAssets());
      verifyNever(() => wallet.listTransfers(assetId: 'rgb:fixture'));
    },
  );

  test(
    'unavailable native inventory propagates instead of fabricating zero',
    () async {
      when(() => wallet.listAssets()).thenThrow(StateError('unavailable'));
      await expectLater(engine.hasProtectedRgbState(), throwsStateError);
    },
  );

  test(
    'a missing balance for an imported asset cannot be treated as zero',
    () async {
      when(() => wallet.listAssets())
          .thenAnswer((_) async => _assets(['rgb:other']));
      when(() => wallet.getAssetBalance('rgb:other'))
          .thenThrow(StateError('missing'));
      await expectLater(engine.hasProtectedRgbState(), throwsStateError);
    },
  );

  test('duplicate asset inventory blocks deletion', () async {
    when(() => wallet.listAssets())
        .thenAnswer((_) async => _assets(['rgb:other', 'rgb:other']));
    await expectLater(engine.hasProtectedRgbState(), throwsFormatException);
  });

  test('negative balance data blocks deletion', () async {
    when(() => wallet.listAssets())
        .thenAnswer((_) async => _assets(['rgb:other']));
    when(() => wallet.getAssetBalance('rgb:other')).thenAnswer(
      (_) async => CoreAssetBalance(
        settled: -BigInt.one,
        future: BigInt.zero,
        spendable: BigInt.zero,
        offchainOutbound: BigInt.zero,
        offchainInbound: BigInt.zero,
      ),
    );
    await expectLater(engine.hasProtectedRgbState(), throwsFormatException);
  });

  test('active zero-value receive request remains protected', () async {
    when(() => wallet.listTransfers(assetId: 'rgb:fixture'))
        .thenAnswer((_) async => [_transfer(expired: false)]);
    expect(await engine.hasProtectedRgbState(), isTrue);
    verifyNever(
      () => wallet.failTransfers(
        batchTransferIdx: any(named: 'batchTransferIdx'),
      ),
    );
  });

  test(
    'expired empty receive uses native rejection, then re-reads terminal state',
    () async {
      var cancelled = false;
      when(() => wallet.listTransfers(assetId: 'rgb:fixture')).thenAnswer(
        (_) async => [
          _transfer(
            status: cancelled
                ? CoreTransferStatuses.failed
                : CoreTransferStatuses.waitingCounterparty,
          ),
        ],
      );
      when(() => wallet.failTransfers(batchTransferIdx: 7))
          .thenAnswer((_) async {
            cancelled = true;
            return true;
          });
      expect(await engine.hasProtectedRgbState(), isFalse);
      verify(() => wallet.failTransfers(batchTransferIdx: 7)).called(1);
      verify(() => wallet.listTransfers(assetId: 'rgb:fixture')).called(2);
    },
  );

  test('elapsed invoice expiry alone never permits removal', () async {
    when(() => wallet.listTransfers(assetId: 'rgb:fixture'))
        .thenAnswer((_) async => [_transfer()]);
    when(() => wallet.failTransfers(batchTransferIdx: 7))
        .thenAnswer((_) async => true);
    expect(await engine.hasProtectedRgbState(), isTrue);
  });

  test('unavailable expiry reconciliation blocks deletion', () async {
    when(() => wallet.listTransfers(assetId: 'rgb:fixture'))
        .thenAnswer((_) async => [_transfer()]);
    when(() => wallet.failTransfers(batchTransferIdx: 7))
        .thenThrow(StateError('cannot prove'));
    await expectLater(engine.hasProtectedRgbState(), throwsStateError);
  });

  for (final transfer in [
    _transfer(kind: 'Send'),
    _transfer(txid: 'a' * 64),
    _transfer(status: CoreTransferStatuses.waitingConfirmations),
    _transfer(
      assignments: [Assignment(type: 'Fungible', amount: BigInt.one)],
    ),
    _transfer(batch: null),
  ]) {
    test(
      'funded, outgoing, advanced or unidentified expired transfer stays protected ${transfer.kind}/${transfer.status}/${transfer.txid}/${transfer.assignments.length}/${transfer.batchTransferIdx}',
      () async {
        when(() => wallet.listTransfers(assetId: 'rgb:fixture'))
            .thenAnswer((_) async => [transfer]);
        expect(await engine.hasProtectedRgbState(), isTrue);
        verifyNever(
          () => wallet.failTransfers(
            batchTransferIdx: any(named: 'batchTransferIdx'),
          ),
        );
      },
    );
  }

  test('terminal transfers alone do not retain empty native data', () async {
    when(() => wallet.listTransfers(assetId: 'rgb:fixture')).thenAnswer(
      (_) async => [
        _transfer(status: CoreTransferStatuses.settled),
        _transfer(status: CoreTransferStatuses.failed),
      ],
    );
    expect(await engine.hasProtectedRgbState(), isFalse);
  });
}

CoreTransfer _transfer({
  String kind = 'ReceiveWitness',
  String status = CoreTransferStatuses.waitingCounterparty,
  bool expired = true,
  String? txid,
  List<Assignment> assignments = const [],
  int? batch = 7,
}) => CoreTransfer(
  idx: 4,
  batchTransferIdx: batch,
  status: status,
  assignments: assignments,
  kind: kind,
  txid: txid,
  expiration: _now.millisecondsSinceEpoch ~/ 1000 + (expired ? -60 : 60),
  transportEndpoints: const [],
);

CoreAssetBalance _balance([String? field]) => CoreAssetBalance(
  settled: field == 'settled' ? BigInt.one : BigInt.zero,
  future: field == 'future' ? BigInt.one : BigInt.zero,
  spendable: field == 'spendable' ? BigInt.one : BigInt.zero,
  offchainOutbound: field == 'outbound' ? BigInt.one : BigInt.zero,
  offchainInbound: field == 'inbound' ? BigInt.one : BigInt.zero,
);

CoreListAssets _assets([List<String> ids = const []]) => CoreListAssets(
  nia: [
    for (final id in ids)
      CoreAssetNia(
        assetId: id,
        ticker: 'OTHER',
        name: 'Other asset',
        precision: 6,
        timestamp: 1,
        addedAt: 1,
        balance: _balance(),
        issuedSupply: BigInt.zero,
      ),
  ],
  cfa: const [],
  ifa: const [],
  uda: const [],
);
