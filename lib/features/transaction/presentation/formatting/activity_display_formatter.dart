import 'package:intl/intl.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../shared/formatting/bitcoin_unit.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/formatting/formatting.dart';

/// Exact monetary and local-time formatting for Activity presentation.
final class ActivityDisplayFormatter {
  ActivityDisplayFormatter({String? locale})
    : _amounts = WalletAmountDisplayFormatter(locale: locale),
      _date = DateFormat.yMMMd(locale),
      _time = DateFormat.jm(locale),
      _dateTime = DateFormat.yMMMd(locale).add_jm();

  final WalletAmountDisplayFormatter _amounts;
  final DateFormat _date;
  final DateFormat _time;
  final DateFormat _dateTime;

  String assetTitle(WalletAssetKind kind) => switch (kind) {
    WalletAssetKind.bitcoin => 'Bitcoin',
    WalletAssetKind.usdt => 'USDT',
  };

  String activityTitle(WalletActivity activity) => switch (activity.direction) {
    WalletActivityDirection.sent => 'Sent',
    WalletActivityDirection.received => 'Received',
    WalletActivityDirection.internal => switch (activity.operation) {
      WalletActivityOperation.bitcoinSelfTransfer => 'Transfer to self',
      WalletActivityOperation.bitcoinUtxoCreation => 'UTXO preparation',
      WalletActivityOperation.rgbAnchor => 'RGB anchor',
      _ => 'Wallet operation',
    },
    WalletActivityDirection.unknown => 'Lightning payment',
  };

  String operationLabel(WalletActivityOperation operation) =>
      switch (operation) {
        WalletActivityOperation.bitcoinSend => 'Bitcoin send',
        WalletActivityOperation.bitcoinSelfTransfer => 'Transfer to self',
        WalletActivityOperation.bitcoinReceive => 'Bitcoin receive',
        WalletActivityOperation.bitcoinDrain => 'Wallet drain',
        WalletActivityOperation.bitcoinUtxoCreation => 'UTXO preparation',
        WalletActivityOperation.rgbAnchor => 'RGB anchor transaction',
        WalletActivityOperation.rgbSend => 'RGB send',
        WalletActivityOperation.rgbReceive => 'RGB receive',
        WalletActivityOperation.rgbIssuance => 'RGB issuance',
        WalletActivityOperation.rgbInflation => 'RGB inflation',
        WalletActivityOperation.rgbBurn => 'RGB burn',
        WalletActivityOperation.lightningPayment => 'Lightning payment',
      };

  String railLabel(PaymentRail rail) => switch (rail) {
    PaymentRail.onchain => 'On-chain',
    PaymentRail.lightning => 'Lightning',
  };

  String networkLabel(BlockchainEnvironment environment) =>
      switch (environment) {
        BlockchainEnvironment.mainnet => 'Mainnet',
        BlockchainEnvironment.signet => 'Signet',
        BlockchainEnvironment.regtest => 'Regtest',
      };

  String statusLabel(WalletActivityStatus status) => switch (status) {
    WalletActivityStatus.pending => 'Pending',
    WalletActivityStatus.waitingCounterparty => 'Waiting for counterparty',
    WalletActivityStatus.waitingSafeHeight => 'Waiting for safe height',
    WalletActivityStatus.waitingBroadcast => 'Waiting for broadcast',
    WalletActivityStatus.waitingConfirmations => 'Waiting for confirmations',
    WalletActivityStatus.claimable => 'Claimable',
    WalletActivityStatus.claiming => 'Claiming',
    WalletActivityStatus.succeeded => 'Completed',
    WalletActivityStatus.failed => 'Failed',
    WalletActivityStatus.cancelled => 'Cancelled',
    WalletActivityStatus.expired => 'Expired',
  };

  String? amountText(WalletActivity activity, BitcoinUnit bitcoinUnit) {
    final amount = activity.amount;
    if (amount == null) return null;
    final formatted = _amounts.format(
      units: amount.units,
      route: PaymentRoute(asset: activity.asset, rail: activity.rail),
      bitcoinUnit: bitcoinUnit,
    );
    final sign = switch (activity.direction) {
      WalletActivityDirection.sent => '-',
      WalletActivityDirection.received => '+',
      WalletActivityDirection.internal || WalletActivityDirection.unknown => '',
    };
    return '$sign${formatted.text}';
  }

  String? feeText(WalletActivity activity, BitcoinUnit bitcoinUnit) {
    final fee = activity.fee;
    if (fee == null) return null;
    return _amounts
        .format(
          units: fee.units,
          route: const PaymentRoute(
            asset: WalletAsset.bitcoin,
            rail: PaymentRail.onchain,
          ),
          bitcoinUnit: bitcoinUnit,
        )
        .text;
  }

  String totalBalanceText(WalletBalance balance, BitcoinUnit bitcoinUnit) {
    final isBitcoin = balance.asset.kind == WalletAssetKind.bitcoin;
    return _amounts
        .format(
          units: isBitcoin
              ? balance.totalBitcoinMillisatoshis!
              : balance.totalAssetUnits,
          route: PaymentRoute(
            asset: balance.asset,
            rail: isBitcoin ? PaymentRail.lightning : PaymentRail.onchain,
          ),
          bitcoinUnit: bitcoinUnit,
        )
        .text;
  }

  String availableBalanceText(WalletBalance balance, BitcoinUnit bitcoinUnit) {
    final isBitcoin = balance.asset.kind == WalletAssetKind.bitcoin;
    return _amounts
        .format(
          units: isBitcoin
              ? balance.availableBitcoinMillisatoshis!
              : balance.availableAssetUnits,
          route: PaymentRoute(
            asset: balance.asset,
            rail: isBitcoin ? PaymentRail.lightning : PaymentRail.onchain,
          ),
          bitcoinUnit: bitcoinUnit,
        )
        .text;
  }

  String groupLabel(DateTime? occurredAt, DateTime now) {
    if (occurredAt == null) return 'Date unavailable';
    final local = occurredAt.toLocal();
    final localNow = now.toLocal();
    final day = DateTime.utc(local.year, local.month, local.day);
    final today = DateTime.utc(localNow.year, localNow.month, localNow.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return _date.format(local);
  }

  String timeLabel(DateTime? occurredAt) {
    return occurredAt == null
        ? 'Time unavailable'
        : _time.format(occurredAt.toLocal());
  }

  String dateTimeLabel(DateTime? value) {
    return value == null ? 'Unavailable' : _dateTime.format(value.toLocal());
  }

  String compactIdentifier(String value) {
    if (value.length <= 24) return value;
    return '${value.substring(0, 12)}...${value.substring(value.length - 8)}';
  }
}
