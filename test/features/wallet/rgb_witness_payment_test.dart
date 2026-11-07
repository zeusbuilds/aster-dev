import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

final class _Wallet extends Mock implements UtexoWallet {}

void main() {
  const services = WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
    usdtAsset: RgbAssetConfiguration(
      contractId: 'rgb:configured-usdt',
      precision: 6,
      requiresEvmValidation: false,
    ),
  );
  final asset = WalletAsset.rgbUsdt(
    assetId: 'rgb:configured-usdt',
    precision: 6,
  );
  final route = PaymentRoute(asset: asset, rail: PaymentRail.onchain);
  late DateTime now;
  late _Wallet wallet;
  late RgbWalletEngine engine;
  var spendable = 2000000;
  String? kind = 'Witness';
  CoreInvoiceData decoded() => CoreInvoiceData(
    invoice: 'rgb:invoice',
    recipientId: 'public-recipient',
    network: 'regtest',
    recipientType: kind,
    assignment: const Assignment(type: 'Any'),
    transportEndpoints: [],
  );
  WalletSendCommand command(RgbRecipientType? type) => WalletSendCommand(
    route: route,
    destination: 'rgb:invoice',
    amount: WalletAmount.onchain(assetId: asset.id, units: 1000000),
    feeRate: WalletFeeRateEstimate(
      targetBlocks: 6,
      satsPerVbyte: 1,
      observedAt: now,
    ),
    rgbRecipientType: type,
    witnessBitcoinAmountSats: type == RgbRecipientType.witness ? 1000 : null,
  );

  setUpAll(() {
    registerFallbackValue(const RgbInvoiceRequest());
    registerFallbackValue(const RgbSendRequest(invoice: 'rgb:fallback'));
  });
  setUp(() {
    now = DateTime.utc(2026, 10, 15);
    spendable = 2000000;
    kind = 'Witness';
    wallet = _Wallet();
    engine = RgbWalletEngine(
      wallet,
      services,
      UtexoUnlockConfig(),
      clock: () => now,
    );
    when(() => wallet.decodeRgbInvoice('rgb:invoice'))
        .thenAnswer((_) async => decoded());
    when(wallet.listAssets).thenAnswer(
      (_) async => CoreListAssets(nia: [], cfa: [], ifa: [], uda: []),
    );
    when(wallet.getBtcBalance).thenAnswer(
      (_) async => CoreBtcBalance(
        vanilla: CoreBalance(
          settled: spendable,
          future: spendable,
          spendable: spendable,
        ),
        colored: const CoreBalance(settled: 0, future: 0, spendable: 0),
      ),
    );
    when(() => wallet.onchainReceive(any())).thenAnswer(
      (_) async => const OnchainReceiveResponse(
        invoice: 'rgb:invoice',
        recipientId: 'public-recipient',
        batchTransferIdx: 1,
      ),
    );
    when(() => wallet.onchainSend(any())).thenAnswer(
      (_) async => OnchainSendResponse(txid: '1' * 64, batchTransferIdx: 2),
    );
  });

  test('receive always uses witness and requires neither prepared outputs nor receiver Bitcoin', () async {
    spendable = 0;
    final request = await engine.createReceiveRequest(route);
    expect(request.encodedRequest, 'rgb:invoice');
    final native =
        verify(() => wallet.onchainReceive(captureAny())).captured.single
            as RgbInvoiceRequest;
    expect(native.witness, isTrue);
    expect(native.assetId, isNull);
    expect(native.amount, isNull);
    verifyNever(wallet.listUnspents);
    verifyNever(wallet.getBtcBalance);
  });

  test('receive rejects a native blind invoice without preparing outputs or retrying', () async {
    kind = 'Blind';
    await expectLater(
      engine.createReceiveRequest(route),
      throwsA(
        isA<NativeProtocolException>().having(
          (error) => error.field,
          'field',
          'CoreInvoiceData',
        ),
      ),
    );
    final request =
        verify(() => wallet.onchainReceive(captureAny())).captured.single
            as RgbInvoiceRequest;
    expect(request.witness, isTrue);
    verifyNever(wallet.listUnspents);
    verifyNever(wallet.getBtcBalance);
    verifyNever(
      () => wallet.createUtxos(upTo: false, num: 4, size: 20000, feeRate: 1),
    );
  });

  test('witness preview and send bind the separately reviewed 1000-sat output exactly once', () async {
    final preview = await engine.decodeInvoice(route, 'rgb:invoice');
    expect(preview.rgbRecipientType, RgbRecipientType.witness);
    expect(preview.witnessBitcoinAmountSats, 1000);
    await engine.sendPayment(command(preview.rgbRecipientType));
    final request =
        verify(() => wallet.onchainSend(captureAny())).captured.single
            as RgbSendRequest;
    expect(request.witnessAmountSat, 1000);
    expect(request.amount, 1000000);
    expect(request.assetId, asset.id.value);
    expect(request.feeRate, 1);
  });

  test('blind recipient preview and send remain supported without an additional Bitcoin output', () async {
    kind = 'Blind';
    final preview = await engine.decodeInvoice(route, 'rgb:invoice');
    expect(preview.rgbRecipientType, RgbRecipientType.blind);
    expect(preview.witnessBitcoinAmountSats, isNull);
    await engine.sendPayment(command(preview.rgbRecipientType));
    expect(
      (verify(() => wallet.onchainSend(captureAny())).captured.single
              as RgbSendRequest)
          .witnessAmountSat,
      isNull,
    );
    verifyNever(wallet.getBtcBalance);
  });

  test(
    'fee review expiring during RGB recipient decode never enters native send',
    () async {
      final reviewed = command(RgbRecipientType.witness);
      final decode = Completer<CoreInvoiceData>();
      when(() => wallet.decodeRgbInvoice('rgb:invoice'))
          .thenAnswer((_) => decode.future);
      final pending = engine.sendPayment(reviewed);
      now = now.add(
        WalletFeeRateEstimate.maximumAge + const Duration(seconds: 1),
      );
      decode.complete(decoded());
      await expectLater(
        pending,
        throwsA(
          isA<AppFailureException>().having(
            (error) => error.failure,
            'failure',
            walletFeeReviewRequiredFailure,
          ),
        ),
      );
      verify(() => wallet.decodeRgbInvoice('rgb:invoice')).called(1);
      verifyNever(() => wallet.onchainSend(any()));
    },
  );

  test(
    'missing consent or changed recipient type rejects before native send',
    () async {
      await expectLater(
        engine.sendPayment(command(null)),
        throwsA(isA<WalletPaymentRejectedBeforeDispatchException>()),
      );
      final reviewed = command(RgbRecipientType.witness);
      kind = 'Blind';
      await expectLater(
        engine.sendPayment(reviewed),
        throwsA(isA<WalletPaymentRejectedBeforeDispatchException>()),
      );
      verifyNever(() => wallet.onchainSend(any()));
    },
  );

  test('colored-funded witness send is not rejected by an unrelated zero vanilla balance', () async {
    spendable = 0;
    when(wallet.getBtcBalance).thenAnswer(
      (_) async => const CoreBtcBalance(
        vanilla: CoreBalance(settled: 0, future: 0, spendable: 0),
        colored: CoreBalance(settled: 20000, future: 20000, spendable: 20000),
      ),
    );
    final preview = await engine.decodeInvoice(route, 'rgb:invoice');
    await engine.sendPayment(command(preview.rgbRecipientType));
    expect(
      (verify(() => wallet.onchainSend(captureAny())).captured.single
              as RgbSendRequest)
          .witnessAmountSat,
      1000,
    );
    verifyNever(wallet.getBtcBalance);
  });

  test('vanilla funds cannot predict RGB input eligibility or override native construction failure', () async {
    spendable = 2000000;
    when(() => wallet.onchainSend(any())).thenThrow(
      const RgbNodeError('Native construction rejected input selection.'),
    );
    final preview = await engine.decodeInvoice(route, 'rgb:invoice');
    await expectLater(
      engine.sendPayment(command(preview.rgbRecipientType)),
      throwsA(isA<WalletMutationOutcomeUnknownException>()),
    );
    verify(() => wallet.onchainSend(any())).called(1);
    verifyNever(wallet.getBtcBalance);
  });

  test('malformed setup inventory reports a safe operation context', () async {
    when(wallet.listUnspents)
        .thenThrow(const FormatException('untrusted native payload'));
    await expectLater(
      engine.rgbSetupInventory(),
      throwsA(
        isA<NativeProtocolException>().having(
          (e) => e.field,
          'field',
          'listUnspents',
        ),
      ),
    );
    verifyNever(() => wallet.onchainReceive(any()));
  });

  test('unknown and absent authoritative recipient types fail closed without native send', () async {
    for (final value in <String?>[null, 'FutureNativeKind', 'witness', '']) {
      kind = value;
      await expectLater(
        engine.decodeInvoice(route, 'rgb:invoice'),
        throwsA(isA<NativeProtocolException>()),
      );
      await expectLater(
        engine.sendPayment(command(RgbRecipientType.witness)),
        throwsA(isA<NativeProtocolException>()),
      );
    }
    verifyNever(() => wallet.onchainSend(any()));
    verifyNever(wallet.getBtcBalance);
  });
}
