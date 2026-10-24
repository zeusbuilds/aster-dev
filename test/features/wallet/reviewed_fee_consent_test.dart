import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const address = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
  late DateTime now;
  late FakeWalletEngine engine;
  late PaymentFlowTestHarness harness;
  WalletFeeRateEstimate quote({
    int rate = 3,
    int target = 6,
    DateTime? observed,
    WalletFeeRateSource source = WalletFeeRateSource.networkEstimate,
  }) => WalletFeeRateEstimate(
    targetBlocks: target,
    satsPerVbyte: rate,
    observedAt: observed ?? now,
    source: source,
  );

  setUp(() async {
    now = DateTime.utc(2026, 10, 15);
    engine = FakeWalletEngine()..feeEstimate = quote();
    harness = await PaymentFlowTestHarness.create(
      engine: engine,
      services: testRgbServices,
      clock: () => now,
    );
  });
  tearDown(() => harness.dispose());

  Future<AppResult<WalletSendResult>> send(WalletFeeRateEstimate? reviewed) =>
      harness.repository.sendPayment(
        target: WalletPaymentTarget.bitcoinOnchain,
        destination: address,
        amountUnits: 100,
        reviewedFeeRate: reviewed,
      );
  void expectNoSend() =>
      expect(engine.calls, isNot(contains('sendPayment:start')));

  test(
    'missing, stale, and future-dated reviews fail before fee lookup',
    () async {
      for (final reviewed in <WalletFeeRateEstimate?>[
        null,
        quote(
          observed: now.subtract(
            WalletFeeRateEstimate.maximumAge + const Duration(seconds: 1),
          ),
        ),
        quote(observed: now.add(const Duration(seconds: 1))),
      ]) {
        final result =
            await send(reviewed) as AppFailureResult<WalletSendResult>;
        expect(result.failure, walletFeeReviewRequiredFailure);
        expect(result.failure.requiresReconciliation, isFalse);
      }
      expect(engine.calls, isNot(contains('estimateFeeRate')));
      expectNoSend();
    },
  );

  test('higher and lower rates both require another user review', () async {
    final reviewed = quote();
    for (final rate in [4, 2]) {
      engine.feeEstimate = quote(rate: rate);
      final result = await send(reviewed) as AppFailureResult<WalletSendResult>;
      expect(result.failure, walletFeeReviewChangedFailure);
    }
    expectNoSend();
  });

  test(
    'equal rates with a changed source or confirmation target are rejected',
    () async {
      engine.feeEstimate = quote(
        rate: 1,
        source: WalletFeeRateSource.localRegtestPolicy,
      );
      expect(
        (await send(
          quote(rate: 1),
        ) as AppFailureResult<WalletSendResult>).failure,
        walletFeeReviewChangedFailure,
      );
      engine.feeEstimate = quote(target: 1);
      expect(
        (await send(quote()) as AppFailureResult<WalletSendResult>).failure,
        walletFeeReviewChangedFailure,
      );
      expectNoSend();
    },
  );

  test(
    'a review that expires during lookup cannot enter native send',
    () async {
      final reviewed = quote();
      engine.feeEstimateGate = Completer<void>();
      engine.feeEstimateStarted = Completer<void>();
      final pending = send(reviewed);
      await engine.feeEstimateStarted!.future;
      now = now.add(
        WalletFeeRateEstimate.maximumAge + const Duration(seconds: 1),
      );
      engine.feeEstimate = quote();
      engine.feeEstimateGate!.complete();
      expect(
        (await pending as AppFailureResult<WalletSendResult>).failure,
        walletFeeReviewRequiredFailure,
      );
      expectNoSend();
    },
  );

  test(
    'a stale refreshed quote cannot authorize an otherwise fresh review',
    () async {
      final reviewed = quote();
      engine.feeEstimate = quote(
        observed: now.subtract(
          WalletFeeRateEstimate.maximumAge + const Duration(seconds: 1),
        ),
      );
      expect(
        (await send(reviewed) as AppFailureResult<WalletSendResult>).failure,
        walletFeeReviewRequiredFailure,
      );
      expectNoSend();
    },
  );

  test('local test fee provenance cannot authorize a mainnet send', () async {
    final mainnetEngine = FakeWalletEngine()..feeEstimate = quote(rate: 1);
    final mainnet = await PaymentFlowTestHarness.create(
      engine: mainnetEngine,
      services: const WalletServiceConfiguration(
        environment: BlockchainEnvironment.mainnet,
        sdkNetwork: 'mainnet',
      ),
      clock: () => now,
    );
    addTearDown(mainnet.dispose);
    final result = await mainnet.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinOnchain,
      destination: '1BoatSLRHtKNngkdXEeobR76b53LETtpyT',
      amountUnits: 100,
      reviewedFeeRate: quote(
        rate: 1,
        source: WalletFeeRateSource.localRegtestPolicy,
      ),
    ) as AppFailureResult<WalletSendResult>;
    expect(result.failure, walletFeeReviewRequiredFailure);
    expect(mainnetEngine.calls, isNot(contains('estimateFeeRate')));
    expect(mainnetEngine.calls, isNot(contains('sendPayment:start')));
  });

  test(
    'lifecycle work cannot interleave fee lookup and payment dispatch',
    () async {
      final reviewed = quote();
      engine.feeEstimateGate = Completer<void>();
      engine.feeEstimateStarted = Completer<void>();
      final pending = send(reviewed);
      await engine.feeEstimateStarted!.future;
      final suspend = harness.repository.suspend();
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls, isNot(contains('shutdown')));
      engine.feeEstimateGate!.complete();
      expect(await pending, isA<AppSuccess<WalletSendResult>>());
      expect(await suspend, isA<AppSuccess<void>>());
      expect(
        engine.calls,
        containsAllInOrder([
          'estimateFeeRate',
          'sendPayment:start',
          'sendPayment:end',
          'shutdown',
        ]),
      );
    },
  );

  test('unchanged policy forwards the reviewed object and witness output exactly once', () async {
    final reviewed = quote(
      rate: 1,
      source: WalletFeeRateSource.localRegtestPolicy,
    );
    engine.feeEstimate = quote(
      rate: 1,
      source: WalletFeeRateSource.localRegtestPolicy,
    );
    final result = await harness.repository.sendPayment(
      target: WalletPaymentTarget.usdtOnchain,
      destination: 'rgb:reviewed-witness',
      amountUnits: 1000000,
      reviewedFeeRate: reviewed,
      rgbRecipientType: RgbRecipientType.witness,
      witnessBitcoinAmountSats: 1000,
    );
    expect(result, isA<AppSuccess<WalletSendResult>>());
    expect(engine.sentPaymentCommand!.feeRate, same(reviewed));
    expect(engine.sentPaymentCommand!.destination, 'rgb:reviewed-witness');
    expect(engine.sentPaymentCommand!.witnessBitcoinAmountSats, 1000);
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
  });

  test(
    'fee change refreshes once in the action and requires another Send command',
    () async {
      // Leave BTC for fees so this case reaches the fee-review guard rather
      // than the separate guard against sending the full available balance.
      engine.balance = _bitcoinBalance(1000);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination(address);
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.00000001');
      expect(
        harness.container.read(provider).requireValue.canSubmitAt(now),
        isTrue,
      );
      engine.feeEstimate = quote(rate: 4);
      final readsBeforeSend = engine.calls
          .where((call) => call == 'estimateFeeRate')
          .length;
      expect(await notifier.submit(), isFalse);
      final blocked = harness.container.read(provider).requireValue;
      expect(blocked.feeFailure, isNull);
      expect(blocked.feeEstimate?.satsPerVbyte, 4);
      expect(blocked.failure, walletFeeUpdatedReviewFailure);
      expect(blocked.canSubmitAt(now), isTrue);
      // One repository pre-dispatch validation and one action-owned read.
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(readsBeforeSend + 2),
      );
      expectNoSend();
      expect(await notifier.submit(), isTrue);
      expect(await notifier.submit(), isFalse);
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
    },
  );
}

WalletBalance _bitcoinBalance(int units) {
  const asset = WalletAsset.bitcoin;
  WalletAmount onchain(int value) =>
      WalletAmount.onchain(assetId: asset.id, units: value);
  final noLightning = WalletAmount.lightning(assetId: asset.id, units: 0);
  return WalletBalance(
    asset: asset,
    onchainSettled: onchain(units),
    onchainFuture: onchain(units),
    onchainSpendable: onchain(units),
    onchainLocked: onchain(0),
    lightningOwned: noLightning,
    lightningSpendable: noLightning,
    lightningReceivable: noLightning,
  );
}
