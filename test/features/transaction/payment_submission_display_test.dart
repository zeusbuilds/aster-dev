import 'package:aster/core/config/app_environment.dart';
import 'package:aster/features/transaction/presentation/models/payment_submission_display.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a shared RGB anchor does not hide a different saved batch', () {
    final asset = WalletAsset.rgbUsdt(assetId: 'rgb:fixture', precision: 6);
    final display = PaymentSubmissionDisplay(_submission(asset, batch: 3));
    final wrongBatch = _activity(asset, batch: 4);
    final correct = _activity(asset, batch: 3);
    expect(display.nativeActivityIn(_feed(asset, [wrongBatch])), isNull);
    expect(display.nativeActivityIn(_feed(asset, [correct])), same(correct));
  });

  test('an unrelated Bitcoin receive record cannot replace a saved send', () {
    final display = PaymentSubmissionDisplay(_submission(WalletAsset.bitcoin));
    final received = _activity(WalletAsset.bitcoin, receive: true);
    final sent = _activity(WalletAsset.bitcoin);
    expect(
      display.nativeActivityIn(_feed(WalletAsset.bitcoin, [received])),
      isNull,
    );
    expect(
      display.nativeActivityIn(_feed(WalletAsset.bitcoin, [sent])),
      same(sent),
    );
  });

  test(
    'ambiguous duplicate native identities never select an arbitrary record',
    () {
      final display = PaymentSubmissionDisplay(
        _submission(WalletAsset.bitcoin),
      );
      expect(
        display.nativeActivityIn(
          _feed(WalletAsset.bitcoin, [
            _activity(WalletAsset.bitcoin),
            _activity(WalletAsset.bitcoin, second: true),
          ]),
        ),
        isNull,
      );
    },
  );
}

WalletPaymentSubmission _submission(WalletAsset asset, {int? batch}) {
  final route = PaymentRoute(asset: asset, rail: PaymentRail.onchain);
  final amount = WalletAmount.onchain(assetId: asset.id, units: 100);
  return WalletPaymentSubmission(
    id: '1' * 32,
    walletId: '2' * 32,
    command: WalletSendCommand(
      route: route,
      amount: amount,
      destination: 'fixture-recipient',
      feeRate: WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: DateTime.utc(2026, 10, 24),
      ),
      rgbRecipientType: asset.kind == WalletAssetKind.usdt
          ? RgbRecipientType.blind
          : null,
    ),
    submittedAt: DateTime.utc(2026, 10, 24),
    phase: WalletPaymentSubmissionPhase.accepted,
    result: WalletSendResult(
      route: route,
      amount: amount,
      referenceId: 'a' * 64,
      batchTransferIndex: batch,
      status: WalletPaymentStatus.pending,
    ),
  );
}

WalletActivity _activity(
  WalletAsset asset, {
  int? batch,
  bool receive = false,
  bool second = false,
}) => WalletActivity(
  id: 'activity-${(second ? 'c' : 'b') * 64}',
  source: asset.kind == WalletAssetKind.bitcoin
      ? WalletActivitySource.bitcoinTransaction
      : WalletActivitySource.rgbTransfer,
  operation: asset.kind == WalletAssetKind.bitcoin
      ? receive
            ? WalletActivityOperation.bitcoinReceive
            : WalletActivityOperation.bitcoinSend
      : WalletActivityOperation.rgbSend,
  asset: asset,
  rail: PaymentRail.onchain,
  direction: receive
      ? WalletActivityDirection.received
      : WalletActivityDirection.sent,
  status: WalletActivityStatus.succeeded,
  txid: 'a' * 64,
  batchTransferIndex: batch,
  transferIndex: asset.kind == WalletAssetKind.usdt ? 1 : null,
);

WalletActivityFeed _feed(WalletAsset asset, List<WalletActivity> activities) {
  final zero = WalletAmount.onchain(assetId: asset.id, units: 0);
  final noLightning = WalletAmount.lightning(assetId: asset.id, units: 0);
  return WalletActivityFeed(
    balance: WalletBalance(
      asset: asset,
      onchainSettled: zero,
      onchainFuture: zero,
      onchainSpendable: zero,
      onchainLocked: zero,
      lightningOwned: noLightning,
      lightningSpendable: noLightning,
      lightningReceivable: noLightning,
    ),
    networkStatus: WalletNetworkStatus(
      environment: BlockchainEnvironment.regtest,
      blockHeight: 0,
      nodePublicKey:
          '020000000000000000000000000000000000000000000000000000000000000000',
      channelCount: 0,
      usableChannelCount: 0,
      peerCount: 0,
    ),
    activities: activities,
  );
}
