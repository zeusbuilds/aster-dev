import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

final class _Wallet extends Mock implements UtexoWallet {}

final class _NativeCode implements NativeErrorCodeCause {
  const _NativeCode(this.nativeCode);
  @override
  final String nativeCode;
}

void main() {
  setUpAll(() => registerFallbackValue(const RgbInvoiceRequest()));
  late _Wallet wallet;
  late RgbWalletEngine engine;
  setUp(() {
    wallet = _Wallet();
    engine = RgbWalletEngine(
      wallet,
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
      ),
      UtexoUnlockConfig(),
    );
  });

  test(
    'forwards one explicit maximum-four-output request at the reviewed rate',
    () async {
      when(
        () => wallet.createUtxos(upTo: false, num: 4, size: 20000, feeRate: 20),
      ).thenAnswer((_) async => 4);
      await engine.createRgbSetupOutputs(20);
      verify(
        () => wallet.createUtxos(upTo: false, num: 4, size: 20000, feeRate: 20),
      ).called(1);
      verifyNoMoreInteractions(wallet);
    },
  );

  test('invalid reviewed rates never enter the SDK', () async {
    await expectLater(engine.createRgbSetupOutputs(0), throwsArgumentError);
    await expectLater(
      engine.createRgbSetupOutputs(1000001),
      throwsArgumentError,
    );
    verifyZeroInteractions(wallet);
  });

  test('setup inventory accepts spendable pending Bitcoin change before reading node identity', () async {
    when(wallet.listUnspents).thenAnswer((_) async => const []);
    when(wallet.getBtcBalance).thenAnswer(
      (_) async => const CoreBtcBalance(
        vanilla: CoreBalance(settled: 0, future: 1895000, spendable: 1895000),
        colored: CoreBalance(settled: 0, future: 80000, spendable: 80000),
      ),
    );
    // Stop before the platform artifact query. Reaching this unchanged next
    // boundary proves pending change is not misclassified as a protocol error.
    final nextBoundary = StateError('node identity test boundary');
    when(wallet.getNodeInfo).thenThrow(nextBoundary);
    await expectLater(engine.rgbSetupInventory(), throwsA(same(nextBoundary)));
    verify(wallet.getNodeInfo).called(1);
    verifyNever(
      () => wallet.createUtxos(upTo: false, num: 4, size: 20000, feeRate: 20),
    );
  });

  for (final invalid in <CoreBalance>[
    const CoreBalance(settled: -1, future: 100, spendable: 100),
    const CoreBalance(settled: 0, future: -1, spendable: 0),
    const CoreBalance(settled: 0, future: 100, spendable: -1),
    const CoreBalance(settled: 101, future: 100, spendable: 100),
    const CoreBalance(settled: 0, future: 100, spendable: 101),
  ]) {
    test(
      'malformed BTC setup tuple ${invalid.settled}/${invalid.future}/${invalid.spendable} fails before platform or mutation calls',
      () async {
        when(wallet.listUnspents).thenAnswer((_) async => const []);
        when(wallet.getBtcBalance).thenAnswer(
          (_) async => CoreBtcBalance(
            vanilla: invalid,
            colored: const CoreBalance(settled: 0, future: 0, spendable: 0),
          ),
        );
        await expectLater(
          engine.rgbSetupInventory(),
          throwsA(isA<NativeProtocolException>()),
        );
        verifyNever(wallet.getNodeInfo);
        verifyNever(
          () =>
              wallet.createUtxos(upTo: false, num: 4, size: 20000, feeRate: 20),
        );
      },
    );
  }

  for (final nativeCode in [
    'NoAvailableUtxos',
    'InsufficientAllocationSlots',
  ]) {
    test(
      'typed $nativeCode offers explicit preparation without dispatch',
      () async {
        when(wallet.listUnspents).thenAnswer(
          (_) async => [
            CoreUnspent(
              utxo: CoreUtxo(
                outpoint: Outpoint(txid: '1' * 64, vout: 0),
                btcAmount: 20000,
                colorable: true,
                exists: true,
              ),
              rgbAllocations: [],
            ),
          ],
        );
        when(wallet.listAssets).thenAnswer(
          (_) async => CoreListAssets(nia: [], cfa: [], ifa: [], uda: []),
        );
        when(
          () => wallet.onchainReceive(any()),
        ).thenThrow(RgbNodeError('safe error', cause: _NativeCode(nativeCode)));
        final configured = RgbWalletEngine(
          wallet,
          const WalletServiceConfiguration(
            environment: BlockchainEnvironment.regtest,
            sdkNetwork: 'regtest',
            usdtAsset: RgbAssetConfiguration(
              contractId: 'rgb:configured-usdt',
              precision: 6,
            ),
          ),
          UtexoUnlockConfig(),
        );
        await expectLater(
          configured.createBlindRgbReceive(
            PaymentRoute(
              asset: WalletAsset.rgbUsdt(
                assetId: 'rgb:configured-usdt',
                precision: 6,
              ),
              rail: PaymentRail.onchain,
            ),
          ),
          throwsA(
            isA<AppFailureException>().having(
              (e) => e.failure.code,
              'code',
              'rgb_wallet_setup_required',
            ),
          ),
        );
        verifyNever(
          () =>
              wallet.createUtxos(upTo: false, num: 4, size: 20000, feeRate: 20),
        );
      },
    );
  }

  test(
    'native message text never triggers setup without its exact typed code',
    () async {
      when(wallet.listAssets).thenAnswer(
        (_) async => CoreListAssets(nia: [], cfa: [], ifa: [], uda: []),
      );
      final failure = RgbNodeError(
        'NoAvailableUtxos',
        cause: const _NativeCode('Conflict'),
      );
      when(() => wallet.onchainReceive(any())).thenThrow(failure);
      final configured = RgbWalletEngine(
        wallet,
        const WalletServiceConfiguration(
          environment: BlockchainEnvironment.regtest,
          sdkNetwork: 'regtest',
          usdtAsset: RgbAssetConfiguration(
            contractId: 'rgb:configured-usdt',
            precision: 6,
          ),
        ),
        UtexoUnlockConfig(),
      );
      await expectLater(
        configured.createReceiveRequest(
          PaymentRoute(
            asset: WalletAsset.rgbUsdt(
              assetId: 'rgb:configured-usdt',
              precision: 6,
            ),
            rail: PaymentRail.onchain,
          ),
        ),
        throwsA(same(failure)),
      );
    },
  );

  test(
    'baseline reconciliation includes only CreateUtxos and validates txids',
    () async {
      when(wallet.listTransactions).thenAnswer(
        (_) async => [
          CoreTransaction(
            txid: '1' * 64,
            transactionType: 'CreateUtxos',
            received: 0,
            sent: 0,
            fee: 0,
            confirmationTime: const CoreBlockTime(height: 100, timestamp: 1000),
          ),
          CoreTransaction(
            txid: '2' * 64,
            transactionType: 'CreateUtxos',
            received: 0,
            sent: 0,
            fee: 0,
          ),
          CoreTransaction(
            txid: '3' * 64,
            transactionType: 'SendBtc',
            received: 0,
            sent: 1000,
            fee: 100,
          ),
        ],
      );
      final result = await engine.rgbSetupTransactions();
      expect(result.map((tx) => tx.txid), ['1' * 64, '2' * 64]);
      expect(result.map((tx) => tx.confirmed), [true, false]);
      when(wallet.listTransactions).thenAnswer(
        (_) async => [
          const CoreTransaction(
            txid: 'malformed',
            transactionType: 'CreateUtxos',
            received: 0,
            sent: 0,
            fee: 0,
          ),
        ],
      );
      await expectLater(
        engine.rgbSetupTransactions(),
        throwsA(isA<StoredDataCorruptionException>()),
      );
    },
  );
}
