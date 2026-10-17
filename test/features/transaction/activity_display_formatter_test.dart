import 'package:aster/core/config/app_environment.dart';
import 'package:aster/features/transaction/presentation/formatting/formatting.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/formatting/bitcoin_unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final formatter = ActivityDisplayFormatter(locale: 'en_US');

  test('self transfer shows reviewed amount neutrally and fee separately', () {
    final native = WalletActivity(
      id: 'activity-${'d' * 64}',
      source: WalletActivitySource.bitcoinTransaction,
      operation: WalletActivityOperation.bitcoinSelfTransfer,
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
      direction: WalletActivityDirection.internal,
      status: WalletActivityStatus.succeeded,
      fee: WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: 155),
      txid: 'd' * 64,
    );
    expect(formatter.activityTitle(native), 'Transfer to self');
    expect(formatter.operationLabel(native.operation), 'Transfer to self');
    expect(formatter.amountText(native, BitcoinUnit.bitcoin), isNull);
    final reviewed = native.withReviewedAmount(
      WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: 5000000),
    );
    expect(formatter.amountText(reviewed, BitcoinUnit.bitcoin), '0.05 BTC');
    expect(formatter.amountText(reviewed, BitcoinUnit.sats), '5,000,000 sats');
    expect(formatter.feeText(reviewed, BitcoinUnit.bitcoin), '0.00000155 BTC');
    expect(formatter.feeText(reviewed, BitcoinUnit.sats), '155 sats');
    expect(formatter.statusLabel(reviewed.status), 'Completed');
  });

  test('formats exact onchain and Lightning units with truthful signs', () {
    final received = _activity(
      idCharacter: 'a',
      rail: PaymentRail.onchain,
      direction: WalletActivityDirection.received,
      units: 123456789,
    );
    final sentLightning = _activity(
      idCharacter: 'b',
      rail: PaymentRail.lightning,
      direction: WalletActivityDirection.sent,
      units: 1500,
    );

    expect(
      formatter.amountText(received, BitcoinUnit.bitcoin),
      '+1.23456789 BTC',
    );
    expect(
      formatter.amountText(received, BitcoinUnit.sats),
      '+123,456,789 sats',
    );
    expect(formatter.amountText(sentLightning, BitcoinUnit.sats), '-1.5 sats');
    expect(
      formatter.amountText(sentLightning, BitcoinUnit.bitcoin),
      '-0.000000015 BTC',
    );
  });

  test(
    'formats aggregate cross-rail Bitcoin balance without precision loss',
    () {
      final balance = _bitcoinBalance();

      expect(
        formatter.totalBalanceText(balance, BitcoinUnit.sats),
        '2,001.5 sats',
      );
      expect(
        formatter.availableBalanceText(balance, BitcoinUnit.sats),
        '1,501.25 sats',
      );
    },
  );

  test('groups local calendar days and preserves unavailable timestamps', () {
    final now = DateTime(2026, 8, 12, 12).toUtc();

    expect(formatter.groupLabel(now, now), 'Today');
    expect(
      formatter.groupLabel(now.subtract(const Duration(days: 1)), now),
      'Yesterday',
    );
    expect(formatter.groupLabel(null, now), 'Date unavailable');
    expect(formatter.timeLabel(null), 'Time unavailable');
  });

  test('groups by local calendar date instead of elapsed duration', () {
    final now = DateTime(2026, 3, 9, 0, 5);
    final lateYesterday = DateTime(2026, 3, 8, 23, 55);
    final older = DateTime(2026, 3, 7, 23, 59);

    expect(formatter.groupLabel(lateYesterday, now), 'Yesterday');
    expect(formatter.groupLabel(older, now), 'Mar 7, 2026');
  });

  test('uses semantic labels and bounded identifiers', () {
    final activity = _activity(
      idCharacter: 'c',
      rail: PaymentRail.lightning,
      direction: WalletActivityDirection.unknown,
      units: null,
    );

    expect(formatter.activityTitle(activity), 'Lightning payment');
    expect(formatter.statusLabel(activity.status), 'Pending');
    expect(formatter.railLabel(activity.rail), 'Lightning');
    expect(formatter.networkLabel(BlockchainEnvironment.signet), 'Signet');
    expect(formatter.compactIdentifier('a' * 64), '${'a' * 12}...${'a' * 8}');
  });
}

WalletActivity _activity({
  required String idCharacter,
  required PaymentRail rail,
  required WalletActivityDirection direction,
  required int? units,
}) {
  return WalletActivity(
    id: 'activity-${idCharacter * 64}',
    source: rail == PaymentRail.onchain
        ? WalletActivitySource.bitcoinTransaction
        : WalletActivitySource.lightningPayment,
    operation: rail == PaymentRail.onchain
        ? WalletActivityOperation.bitcoinReceive
        : WalletActivityOperation.lightningPayment,
    asset: WalletAsset.bitcoin,
    rail: rail,
    direction: direction,
    status: WalletActivityStatus.pending,
    amount: units == null
        ? null
        : rail == PaymentRail.onchain
        ? WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: units)
        : WalletAmount.lightning(assetId: WalletAsset.bitcoin.id, units: units),
    txid: rail == PaymentRail.onchain ? 'txid' : null,
    paymentHash: rail == PaymentRail.lightning ? 'payment-hash' : null,
  );
}

WalletBalance _bitcoinBalance() {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: WalletAsset.bitcoin.id, units: units);
  return WalletBalance(
    asset: WalletAsset.bitcoin,
    onchainSettled: onchain(2000),
    onchainFuture: onchain(2000),
    onchainSpendable: onchain(1500),
    onchainLocked: onchain(500),
    lightningOwned: lightning(1500),
    lightningSpendable: lightning(1250),
    lightningReceivable: lightning(0),
  );
}
