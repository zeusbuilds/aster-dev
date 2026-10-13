import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../domain/models/models.dart';
import 'rgb_wallet_native_value_parser.dart';

/// Maps native transaction, RGB transfer, and Lightning payment records.
///
/// This adapter collaborator is intentionally absent from `runtime.dart`;
/// consumers receive only app-owned [WalletActivity] values from the engine.
final class RgbWalletActivityMapper {
  const RgbWalletActivityMapper([
    this._values = const RgbWalletNativeValueParser(),
  ]);

  final RgbWalletNativeValueParser _values;

  WalletActivity bitcoin(WalletAsset asset, CoreTransaction transaction) {
    final txid = _values.identifier(transaction.txid, 'CoreTransaction.txid');
    _values.requireNonNegative(
      transaction.received,
      'CoreTransaction.received',
    );
    _values.requireNonNegative(transaction.sent, 'CoreTransaction.sent');
    _values.requireNonNegative(transaction.fee, 'CoreTransaction.fee');
    final confirmation = transaction.confirmationTime;
    final confirmedAt = confirmation == null
        ? null
        : _values.unixSeconds(
            confirmation.timestamp,
            'CoreTransaction.confirmationTime.timestamp',
          );
    if (confirmation != null && confirmation.height < 0) {
      throw const NativeProtocolException(
        'Native transaction confirmation height must not be negative.',
        field: 'CoreTransaction.confirmationTime.height',
      );
    }
    final (
      operation,
      direction,
      amountUnits,
    ) = switch (transaction.transactionType) {
      'Incoming' => (
        WalletActivityOperation.bitcoinReceive,
        WalletActivityDirection.received,
        transaction.received,
      ),
      'SendBtc' => (
        WalletActivityOperation.bitcoinSend,
        WalletActivityDirection.sent,
        _externalBitcoinAmount(transaction),
      ),
      'Drain' => (
        WalletActivityOperation.bitcoinDrain,
        WalletActivityDirection.sent,
        _externalBitcoinAmount(transaction),
      ),
      'CreateUtxos' => (
        WalletActivityOperation.bitcoinUtxoCreation,
        WalletActivityDirection.internal,
        0,
      ),
      'RgbSend' => (
        WalletActivityOperation.rgbAnchor,
        WalletActivityDirection.internal,
        0,
      ),
      _ => throw const NativeProtocolException(
        'Native wallet returned an unknown transaction type.',
        field: 'CoreTransaction.transactionType',
      ),
    };
    return WalletActivity(
      id: _activityId('bitcoin-transaction', asset, txid),
      source: WalletActivitySource.bitcoinTransaction,
      operation: operation,
      asset: asset,
      rail: PaymentRail.onchain,
      direction: direction,
      status: confirmation == null
          ? WalletActivityStatus.pending
          : WalletActivityStatus.succeeded,
      amount: amountUnits == 0
          ? null
          : WalletAmount.onchain(assetId: asset.id, units: amountUnits),
      fee: transaction.fee == 0
          ? null
          : WalletAmount.onchain(
              assetId: WalletAsset.bitcoin.id,
              units: transaction.fee,
            ),
      occurredAt: confirmedAt,
      confirmedAt: confirmedAt,
      confirmationHeight: confirmation?.height,
      txid: txid,
    );
  }

  WalletActivity rgb(WalletAsset asset, CoreTransfer transfer) {
    if (transfer.idx < 0) {
      throw const NativeProtocolException(
        'Native RGB transfer index must not be negative.',
        field: 'CoreTransfer.idx',
      );
    }
    final (operation, direction) = switch (transfer.kind) {
      'Send' => (WalletActivityOperation.rgbSend, WalletActivityDirection.sent),
      'ReceiveBlind' || 'ReceiveWitness' => (
        WalletActivityOperation.rgbReceive,
        WalletActivityDirection.received,
      ),
      'Issuance' => (
        WalletActivityOperation.rgbIssuance,
        WalletActivityDirection.received,
      ),
      'Inflation' => (
        WalletActivityOperation.rgbInflation,
        WalletActivityDirection.received,
      ),
      'Burn' => (WalletActivityOperation.rgbBurn, WalletActivityDirection.sent),
      _ => throw const NativeProtocolException(
        'Native wallet returned an unknown RGB transfer kind.',
        field: 'CoreTransfer.kind',
      ),
    };
    final createdAt = _values.optionalUnixSeconds(
      transfer.createdAt,
      'CoreTransfer.createdAt',
    );
    final updatedAt = _values.optionalUnixSeconds(
      transfer.updatedAt,
      'CoreTransfer.updatedAt',
    );
    final endpoints = transfer.transportEndpoints;
    final amountUnits = _transferAmount(transfer);
    final transportTypes =
        endpoints
            .map((endpoint) => endpoint.transportType)
            .toSet()
            .toList(growable: false)
          ..sort();
    return WalletActivity(
      id: _activityId('rgb-transfer', asset, transfer.idx.toString()),
      source: WalletActivitySource.rgbTransfer,
      operation: operation,
      asset: asset,
      rail: PaymentRail.onchain,
      direction: direction,
      status: _transferStatus(transfer.status),
      amount: amountUnits == null
          ? null
          : WalletAmount.onchain(assetId: asset.id, units: amountUnits),
      occurredAt: createdAt ?? updatedAt,
      updatedAt: updatedAt,
      expiresAt: _values.optionalUnixSeconds(
        transfer.expiration,
        'CoreTransfer.expiration',
      ),
      txid: _values.optionalIdentifier(transfer.txid, 'CoreTransfer.txid'),
      recipientId: _values.optionalIdentifier(
        transfer.recipientId,
        'CoreTransfer.recipientId',
      ),
      transferIndex: transfer.idx,
      batchTransferIndex: _values.optionalIndex(
        transfer.batchTransferIdx,
        'CoreTransfer.batchTransferIdx',
      ),
      receiveOutpoint: _outpoint(
        transfer.receiveUtxo,
        'CoreTransfer.receiveUtxo',
      ),
      changeOutpoint: _outpoint(transfer.changeUtxo, 'CoreTransfer.changeUtxo'),
      transportEndpointCount: endpoints.length,
      usedTransportEndpointCount: endpoints
          .where((endpoint) => endpoint.used)
          .length,
      transportTypes: transportTypes,
    );
  }

  WalletActivity lightning(WalletAsset asset, LightningPayment payment) {
    final paymentHash = _values.identifier(
      payment.paymentHash,
      'LightningPayment.paymentHash',
    );
    final amountUnits = asset.kind == WalletAssetKind.bitcoin
        ? payment.amtMsat
        : payment.assetAmount == null
        ? null
        : _values.exactUnits(
            payment.assetAmount!,
            'LightningPayment.assetAmount',
          );
    if (asset.kind == WalletAssetKind.bitcoin && payment.assetAmount != null) {
      throw const NativeProtocolException(
        'Bitcoin Lightning payment unexpectedly contains an RGB amount.',
        field: 'LightningPayment.assetAmount',
      );
    }
    if (amountUnits != null && amountUnits <= 0) {
      throw const NativeProtocolException(
        'Native Lightning payment amount must be positive.',
        field: 'LightningPayment.amount',
      );
    }
    final createdAt = _values.optionalUnixSeconds(
      payment.createdAt,
      'LightningPayment.createdAt',
    );
    final updatedAt = _values.optionalUnixSeconds(
      payment.updatedAt,
      'LightningPayment.updatedAt',
    );
    return WalletActivity(
      id: _activityId('lightning-payment', asset, paymentHash),
      source: WalletActivitySource.lightningPayment,
      operation: WalletActivityOperation.lightningPayment,
      asset: asset,
      rail: PaymentRail.lightning,
      direction: switch (payment.inbound) {
        true => WalletActivityDirection.received,
        false => WalletActivityDirection.sent,
        null => WalletActivityDirection.unknown,
      },
      status: _lightningStatus(payment.status),
      amount: amountUnits == null
          ? null
          : WalletAmount.lightning(assetId: asset.id, units: amountUnits),
      occurredAt: createdAt ?? updatedAt,
      updatedAt: updatedAt,
      paymentHash: paymentHash,
      invoice: payment.invoice,
      payeePublicKey: _values.optionalIdentifier(
        payment.payeePubkey,
        'LightningPayment.payeePubkey',
      ),
    );
  }

  bool paymentBelongsToAsset(LightningPayment payment, WalletAsset asset) {
    final nativeAssetId = payment.assetId;
    if (asset.kind == WalletAssetKind.bitcoin) return nativeAssetId == null;
    return nativeAssetId == asset.id.value;
  }

  List<WalletActivity> normalize(Iterable<WalletActivity> activities) {
    final byId = <String, WalletActivity>{};
    for (final activity in activities) {
      final existing = byId[activity.id];
      if (existing == null) {
        byId[activity.id] = activity;
      } else if (existing != activity) {
        throw const NativeProtocolException(
          'Native wallet returned conflicting duplicate activity.',
          field: 'WalletActivity.id',
        );
      }
    }
    final normalized = byId.values.toList(growable: false)
      ..sort(WalletActivityFeed.compareByRecency);
    return List<WalletActivity>.unmodifiable(normalized);
  }

  int _externalBitcoinAmount(CoreTransaction transaction) {
    final value =
        BigInt.from(transaction.sent) -
        BigInt.from(transaction.received) -
        BigInt.from(transaction.fee);
    if (value.isNegative || value > BigInt.from(WalletAmount.maxNativeUnits)) {
      throw const NativeProtocolException(
        'Native Bitcoin transaction amounts are inconsistent.',
        field: 'CoreTransaction.sent',
      );
    }
    return value.toInt();
  }

  int? _transferAmount(CoreTransfer transfer) {
    // Outgoing allocations can be change. Use the SDK's exact recipient amount,
    // and preserve an absent request as unknown, never as wallet change.
    if (transfer.kind == 'Send' ||
        transfer.kind == 'Burn' ||
        transfer.kind == 'Inflation') {
      final amount = transfer.amount;
      if (amount == null) return null;
      if (amount.isNegative ||
          amount > BigInt.from(WalletAmount.maxNativeUnits)) {
        throw const NativeProtocolException(
          'Native outgoing RGB amount exceeds supported bounds.',
          field: 'CoreTransfer.amount',
        );
      }
      return amount.toInt();
    }
    // A receive request is not an allocation. Empty pending/failed receives
    // stay amount-unknown even when requestedAssignment names an amount.
    final assignments = transfer.assignments;
    if (assignments.isEmpty &&
        (transfer.kind == 'ReceiveBlind' ||
            transfer.kind == 'ReceiveWitness') &&
        transfer.status != CoreTransferStatuses.settled) {
      return null;
    }
    var total = BigInt.zero;
    var foundAmount = false;
    for (final assignment in assignments) {
      final amount = assignment.amount;
      if (assignment.type != 'Fungible' || amount == null) {
        throw const NativeProtocolException(
          'Native fungible transfer has an invalid assignment.',
          field: 'CoreTransfer.assignments',
        );
      }
      foundAmount = true;
      if (amount.isNegative) {
        throw const NativeProtocolException(
          'Native RGB assignment amount must not be negative.',
          field: 'CoreTransfer.assignments.amount',
        );
      }
      total += amount;
      if (total > BigInt.from(WalletAmount.maxNativeUnits)) {
        throw const NativeProtocolException(
          'Native RGB transfer amount exceeds supported bounds.',
          field: 'CoreTransfer.assignments.amount',
        );
      }
    }
    if (!foundAmount || total == BigInt.zero) {
      throw const NativeProtocolException(
        'Native fungible RGB transfer has no positive amount.',
        field: 'CoreTransfer.assignments.amount',
      );
    }
    return total.toInt();
  }

  WalletActivityStatus _transferStatus(String status) => switch (status) {
    'Initiated' => WalletActivityStatus.pending,
    'WaitingCounterparty' => WalletActivityStatus.waitingCounterparty,
    'WaitingSafeHeight' => WalletActivityStatus.waitingSafeHeight,
    'WaitingBroadcast' => WalletActivityStatus.waitingBroadcast,
    'WaitingConfirmations' => WalletActivityStatus.waitingConfirmations,
    'Settled' => WalletActivityStatus.succeeded,
    'Failed' => WalletActivityStatus.failed,
    _ => throw const NativeProtocolException(
      'Native wallet returned an unknown RGB transfer status.',
      field: 'CoreTransfer.status',
    ),
  };

  WalletActivityStatus _lightningStatus(String status) => switch (status) {
    RlnPaymentStatuses.pending => WalletActivityStatus.pending,
    RlnPaymentStatuses.claimable => WalletActivityStatus.claimable,
    RlnPaymentStatuses.claiming => WalletActivityStatus.claiming,
    RlnPaymentStatuses.succeeded => WalletActivityStatus.succeeded,
    RlnPaymentStatuses.cancelled => WalletActivityStatus.cancelled,
    RlnPaymentStatuses.failed => WalletActivityStatus.failed,
    RlnInvoiceStatuses.expired => WalletActivityStatus.expired,
    _ => throw const NativeProtocolException(
      'Native wallet returned an unknown Lightning payment status.',
      field: 'LightningPayment.status',
    ),
  };

  String? _outpoint(Outpoint? outpoint, String field) {
    if (outpoint == null) return null;
    final txid = _values.identifier(outpoint.txid, '$field.txid');
    if (outpoint.vout < 0) {
      throw NativeProtocolException(
        'Native RGB outpoint index must not be negative.',
        field: '$field.vout',
      );
    }
    return '$txid:${outpoint.vout}';
  }

  String _activityId(String source, WalletAsset asset, String nativeId) {
    final digest = sha256.convert(
      utf8.encode('v1|$source|${asset.id.value}|$nativeId'),
    );
    return 'activity-$digest';
  }
}
