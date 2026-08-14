import 'package:flutter/foundation.dart';

import '../validation/validation.dart';
import 'wallet_amount.dart';
import 'wallet_asset.dart';
import 'wallet_balance.dart';
import 'wallet_network.dart';

/// Native activity family after SDK DTOs have been isolated by the adapter.
enum WalletActivitySource { bitcoinTransaction, rgbTransfer, lightningPayment }

/// User-facing movement direction known from authoritative native data.
enum WalletActivityDirection { sent, received, internal, unknown }

/// App-owned lifecycle state shared by on-chain and Lightning activity.
enum WalletActivityStatus {
  pending,
  waitingCounterparty,
  waitingSafeHeight,
  waitingConfirmations,
  claimable,
  claiming,
  succeeded,
  failed,
  cancelled,
  expired,
}

/// Stable semantic operation independent from native enum spelling.
enum WalletActivityOperation {
  bitcoinSend,
  bitcoinReceive,
  bitcoinDrain,
  bitcoinUtxoCreation,
  rgbAnchor,
  rgbSend,
  rgbReceive,
  rgbIssuance,
  rgbInflation,
  rgbBurn,
  lightningPayment,
}

/// One normalized wallet activity record.
///
/// Monetary fields use canonical integer units. Encoded payment material is
/// intentionally excluded from [toString] and must never be placed in routes.
@immutable
final class WalletActivity {
  WalletActivity({
    required this.id,
    required this.source,
    required this.operation,
    required this.asset,
    required this.rail,
    required this.direction,
    required this.status,
    this.amount,
    this.fee,
    this.occurredAt,
    this.updatedAt,
    this.confirmedAt,
    this.expiresAt,
    this.confirmationHeight,
    this.txid,
    this.paymentHash,
    this.invoice,
    this.recipientId,
    this.payeePublicKey,
    this.transferIndex,
    this.batchTransferIndex,
    this.receiveOutpoint,
    this.changeOutpoint,
    this.transportEndpointCount = 0,
    this.usedTransportEndpointCount = 0,
    List<String> transportTypes = const <String>[],
  }) : transportTypes = List<String>.unmodifiable(transportTypes) {
    if (!_activityId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid opaque activity ID.');
    }
    final value = amount;
    if (value != null) {
      if (value.assetId != asset.id || value.rail != rail || value.isZero) {
        throw ArgumentError.value(value, 'amount', 'Asset or rail mismatch.');
      }
    }
    final feeValue = fee;
    if (feeValue != null &&
        (feeValue.assetId != WalletAsset.bitcoin.id ||
            feeValue.rail != PaymentRail.onchain)) {
      throw ArgumentError.value(feeValue, 'fee', 'Fee must be on-chain BTC.');
    }
    _requireUtc(occurredAt, 'occurredAt');
    _requireUtc(updatedAt, 'updatedAt');
    _requireUtc(confirmedAt, 'confirmedAt');
    _requireUtc(expiresAt, 'expiresAt');
    if (occurredAt != null &&
        updatedAt != null &&
        updatedAt!.isBefore(occurredAt!)) {
      throw ArgumentError.value(updatedAt, 'updatedAt', 'Precedes creation.');
    }
    _requireOptionalNonNegative(confirmationHeight, 'confirmationHeight');
    _requireOptionalNonNegative(transferIndex, 'transferIndex');
    _requireOptionalNonNegative(batchTransferIndex, 'batchTransferIndex');
    _requireIdentifier(txid, 'txid');
    _requireIdentifier(paymentHash, 'paymentHash');
    _requireEncoded(invoice, 'invoice');
    _requireEncoded(recipientId, 'recipientId');
    _requireIdentifier(payeePublicKey, 'payeePublicKey');
    _requireIdentifier(receiveOutpoint, 'receiveOutpoint');
    _requireIdentifier(changeOutpoint, 'changeOutpoint');
    if (transportEndpointCount < 0 ||
        usedTransportEndpointCount < 0 ||
        usedTransportEndpointCount > transportEndpointCount) {
      throw ArgumentError.value(
        usedTransportEndpointCount,
        'usedTransportEndpointCount',
      );
    }
    if (transportTypes.length > transportEndpointCount) {
      throw ArgumentError.value(transportTypes, 'transportTypes');
    }
    for (final type in transportTypes) {
      _requireDisplayValue(type, 'transportTypes');
    }
    _requireSourceShape();
  }

  /// Opaque deterministic ID suitable for route lookup without exposing a
  /// payment hash, transaction ID, invoice, or recipient identifier.
  final String id;
  final WalletActivitySource source;
  final WalletActivityOperation operation;
  final WalletAsset asset;
  final PaymentRail rail;
  final WalletActivityDirection direction;
  final WalletActivityStatus status;
  final WalletAmount? amount;

  /// Bitcoin network fee in satoshis when native reports it.
  final WalletAmount? fee;

  /// Best native event time used for feed ordering, in UTC.
  final DateTime? occurredAt;
  final DateTime? updatedAt;
  final DateTime? confirmedAt;
  final DateTime? expiresAt;
  final int? confirmationHeight;
  final String? txid;
  final String? paymentHash;
  final String? invoice;
  final String? recipientId;
  final String? payeePublicKey;
  final int? transferIndex;
  final int? batchTransferIndex;
  final String? receiveOutpoint;
  final String? changeOutpoint;

  /// Counts and transport type names are retained; endpoint URLs are not
  /// carried into presentation because they may contain deployment secrets.
  final int transportEndpointCount;
  final int usedTransportEndpointCount;
  final List<String> transportTypes;

  static bool isValidId(String? value) =>
      value != null && _activityId.hasMatch(value);

  void _requireSourceShape() {
    switch (source) {
      case WalletActivitySource.bitcoinTransaction:
        if (asset.kind != WalletAssetKind.bitcoin ||
            rail != PaymentRail.onchain ||
            txid == null ||
            paymentHash != null ||
            invoice != null ||
            recipientId != null ||
            payeePublicKey != null ||
            transferIndex != null ||
            batchTransferIndex != null ||
            receiveOutpoint != null ||
            changeOutpoint != null ||
            transportEndpointCount != 0 ||
            usedTransportEndpointCount != 0 ||
            transportTypes.isNotEmpty ||
            !_validBitcoinOperationDirection()) {
          throw ArgumentError('Invalid Bitcoin transaction activity shape.');
        }
        break;
      case WalletActivitySource.rgbTransfer:
        if (asset.kind != WalletAssetKind.usdt ||
            rail != PaymentRail.onchain ||
            transferIndex == null ||
            paymentHash != null ||
            invoice != null ||
            payeePublicKey != null ||
            confirmationHeight != null ||
            confirmedAt != null ||
            !_validRgbOperationDirection()) {
          throw ArgumentError('Invalid RGB transfer activity shape.');
        }
        break;
      case WalletActivitySource.lightningPayment:
        if (rail != PaymentRail.lightning ||
            paymentHash == null ||
            operation != WalletActivityOperation.lightningPayment ||
            direction == WalletActivityDirection.internal ||
            txid != null ||
            recipientId != null ||
            transferIndex != null ||
            batchTransferIndex != null ||
            receiveOutpoint != null ||
            changeOutpoint != null ||
            confirmationHeight != null ||
            confirmedAt != null ||
            transportEndpointCount != 0 ||
            usedTransportEndpointCount != 0 ||
            transportTypes.isNotEmpty) {
          throw ArgumentError('Invalid Lightning payment activity shape.');
        }
        break;
    }
  }

  bool _validBitcoinOperationDirection() => switch (operation) {
    WalletActivityOperation.bitcoinSend ||
    WalletActivityOperation.bitcoinDrain =>
      direction == WalletActivityDirection.sent,
    WalletActivityOperation.bitcoinReceive =>
      direction == WalletActivityDirection.received,
    WalletActivityOperation.bitcoinUtxoCreation ||
    WalletActivityOperation.rgbAnchor =>
      direction == WalletActivityDirection.internal,
    WalletActivityOperation.rgbSend ||
    WalletActivityOperation.rgbReceive ||
    WalletActivityOperation.rgbIssuance ||
    WalletActivityOperation.rgbInflation ||
    WalletActivityOperation.rgbBurn ||
    WalletActivityOperation.lightningPayment => false,
  };

  bool _validRgbOperationDirection() => switch (operation) {
    WalletActivityOperation.rgbSend || WalletActivityOperation.rgbBurn =>
      direction == WalletActivityDirection.sent,
    WalletActivityOperation.rgbReceive ||
    WalletActivityOperation.rgbIssuance ||
    WalletActivityOperation.rgbInflation =>
      direction == WalletActivityDirection.received,
    WalletActivityOperation.bitcoinSend ||
    WalletActivityOperation.bitcoinReceive ||
    WalletActivityOperation.bitcoinDrain ||
    WalletActivityOperation.bitcoinUtxoCreation ||
    WalletActivityOperation.rgbAnchor ||
    WalletActivityOperation.lightningPayment => false,
  };

  @override
  String toString() =>
      'WalletActivity($id, ${asset.kind.name}, ${rail.name}, ${status.name})';

  @override
  bool operator ==(Object other) =>
      other is WalletActivity &&
      other.id == id &&
      other.source == source &&
      other.operation == operation &&
      other.asset == asset &&
      other.rail == rail &&
      other.direction == direction &&
      other.status == status &&
      other.amount == amount &&
      other.fee == fee &&
      other.occurredAt == occurredAt &&
      other.updatedAt == updatedAt &&
      other.confirmedAt == confirmedAt &&
      other.expiresAt == expiresAt &&
      other.confirmationHeight == confirmationHeight &&
      other.txid == txid &&
      other.paymentHash == paymentHash &&
      other.invoice == invoice &&
      other.recipientId == recipientId &&
      other.payeePublicKey == payeePublicKey &&
      other.transferIndex == transferIndex &&
      other.batchTransferIndex == batchTransferIndex &&
      other.receiveOutpoint == receiveOutpoint &&
      other.changeOutpoint == changeOutpoint &&
      other.transportEndpointCount == transportEndpointCount &&
      other.usedTransportEndpointCount == usedTransportEndpointCount &&
      listEquals(other.transportTypes, transportTypes);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    id,
    source,
    operation,
    asset,
    rail,
    direction,
    status,
    amount,
    fee,
    occurredAt,
    updatedAt,
    confirmedAt,
    expiresAt,
    confirmationHeight,
    txid,
    paymentHash,
    invoice,
    recipientId,
    payeePublicKey,
    transferIndex,
    batchTransferIndex,
    receiveOutpoint,
    changeOutpoint,
    transportEndpointCount,
    usedTransportEndpointCount,
    Object.hashAll(transportTypes),
  ]);
}

/// Real balance and normalized, newest-first activity for one product asset.
@immutable
final class WalletActivityFeed {
  WalletActivityFeed({
    required this.balance,
    required this.networkStatus,
    required List<WalletActivity> activities,
  }) : activities = List<WalletActivity>.unmodifiable(activities) {
    final ids = <String>{};
    for (var index = 0; index < this.activities.length; index += 1) {
      final activity = this.activities[index];
      if (activity.asset != balance.asset || !ids.add(activity.id)) {
        throw ArgumentError.value(activities, 'activities');
      }
      final confirmationHeight = activity.confirmationHeight;
      if (confirmationHeight != null &&
          confirmationHeight > networkStatus.blockHeight) {
        throw ArgumentError.value(
          confirmationHeight,
          'activities',
          'Confirmation height exceeds the observed chain tip.',
        );
      }
      if (index > 0 &&
          compareByRecency(this.activities[index - 1], activity) > 0) {
        throw ArgumentError.value(
          activities,
          'activities',
          'Must be sorted newest first.',
        );
      }
    }
  }

  final WalletBalance balance;
  final WalletNetworkStatus networkStatus;
  final List<WalletActivity> activities;

  /// Orders dated records newest-first and undated records last, then uses the
  /// opaque ID as a deterministic tie-breaker.
  static int compareByRecency(WalletActivity left, WalletActivity right) {
    final leftTime = left.occurredAt;
    final rightTime = right.occurredAt;
    if (leftTime == null) {
      return rightTime == null ? left.id.compareTo(right.id) : 1;
    }
    if (rightTime == null) return -1;
    final newestFirst = rightTime.compareTo(leftTime);
    return newestFirst == 0 ? left.id.compareTo(right.id) : newestFirst;
  }

  WalletActivity? findById(String id) {
    for (final activity in activities) {
      if (activity.id == id) return activity;
    }
    return null;
  }

  int? confirmationsFor(WalletActivity activity) {
    final height = activity.confirmationHeight;
    if (height == null) return null;
    return networkStatus.blockHeight - height + 1;
  }

  @override
  bool operator ==(Object other) =>
      other is WalletActivityFeed &&
      other.balance == balance &&
      other.networkStatus == networkStatus &&
      listEquals(other.activities, activities);

  @override
  int get hashCode =>
      Object.hash(balance, networkStatus, Object.hashAll(activities));
}

final _activityId = RegExp(r'^activity-[0-9a-f]{64}$');

void _requireUtc(DateTime? value, String field) {
  if (value != null && !value.isUtc) {
    throw ArgumentError.value(value, field, 'Must use UTC.');
  }
}

void _requireOptionalNonNegative(int? value, String field) {
  if (value != null && value < 0) throw ArgumentError.value(value, field);
}

void _requireIdentifier(String? value, String field) {
  if (value == null) return;
  if (!WalletProtocolText.isIdentifier(value)) {
    throw ArgumentError.value(value, field, 'Invalid identifier.');
  }
}

void _requireEncoded(String? value, String field) {
  if (value == null) return;
  if (!WalletProtocolText.isEncodedValue(value)) {
    throw ArgumentError.value(value, field, 'Invalid encoded value.');
  }
}

void _requireDisplayValue(String value, String field) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.length > 64 ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw ArgumentError.value(value, field, 'Invalid display value.');
  }
}
