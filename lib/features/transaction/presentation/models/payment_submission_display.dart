import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../../shared/formatting/bitcoin_unit.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/formatting/formatting.dart';

/// Presents a saved send without inventing a native transaction or chain status.
/// The opaque route remains scoped to this exact wallet and attempt.
final class PaymentSubmissionDisplay {
  PaymentSubmissionDisplay(this.submission);

  final WalletPaymentSubmission submission;

  String get id =>
      'activity-${sha256.convert(utf8.encode('aster-send:${submission.walletId}:${submission.id}'))}';

  String get status => switch (submission.outcome) {
    WalletPaymentSubmissionOutcome.accepted => 'Submitted',
    WalletPaymentSubmissionOutcome.notSubmitted => 'Not sent',
    WalletPaymentSubmissionOutcome.unknown => 'Status unavailable',
  };

  bool visibleIn(WalletActivityFeed feed) =>
      submission.command.route.asset == feed.balance.asset &&
      (submission.requiresReconciliation ||
          submission.phase == WalletPaymentSubmissionPhase.accepted) &&
      nativeActivityIn(feed) == null;

  /// A txid alone does not identify an RGB transfer: several asset/batch
  /// records may share its Bitcoin anchor. Never hide a saved send behind a
  /// different native operation or ambiguous matching records.
  bool matchesNative(WalletActivity record) {
    final receipt = submission.result;
    if (receipt == null ||
        record.asset != submission.command.route.asset ||
        record.rail != PaymentRail.onchain ||
        record.txid != receipt.referenceId) {
      return false;
    }
    return switch (record.source) {
      WalletActivitySource.bitcoinTransaction =>
        submission.command.route.asset.kind == WalletAssetKind.bitcoin &&
            (record.operation == WalletActivityOperation.bitcoinSend ||
                record.operation ==
                    WalletActivityOperation.bitcoinSelfTransfer),
      WalletActivitySource.rgbTransfer =>
        submission.command.route.asset.kind == WalletAssetKind.usdt &&
            record.operation == WalletActivityOperation.rgbSend &&
            receipt.batchTransferIndex != null &&
            record.batchTransferIndex == receipt.batchTransferIndex,
      WalletActivitySource.lightningPayment => false,
    };
  }

  WalletActivity? nativeActivityIn(WalletActivityFeed feed) {
    final matches = feed.activities.where(matchesNative).take(2).toList();
    return matches.length == 1 ? matches.single : null;
  }

  String amount(BitcoinUnit unit) => WalletAmountDisplayFormatter()
      .format(
        units: submission.command.amount.units,
        route: submission.command.route,
        bitcoinUnit: unit,
      )
      .text;
}
