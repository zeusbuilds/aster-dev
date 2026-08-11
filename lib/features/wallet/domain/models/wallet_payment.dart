import 'package:flutter/foundation.dart';

import 'wallet_amount.dart';
import 'wallet_asset.dart';

/// App-owned lifecycle state for a payment or transfer.
enum WalletPaymentStatus { pending, succeeded, failed, cancelled, expired }

/// Validated destination preview returned before a send is submitted.
///
/// [encodedDestination] may be an address, BIP321 URI, RGB invoice, or BOLT11
/// invoice. It is intentionally never included in `toString` output.
@immutable
final class WalletPaymentPreview {
  WalletPaymentPreview({
    required this.route,
    required this.encodedDestination,
    required this.displayDestination,
    this.amount,
    this.expiresAt,
    this.referenceId,
    this.recipientLabel,
    this.message,
  }) {
    _requireEncoded(encodedDestination, 'encodedDestination');
    _requireEncoded(displayDestination, 'displayDestination');
    final value = amount;
    if (value != null) _requireRouteAmount(route, value);
    _requireUtc(expiresAt, 'expiresAt');
    _requireOptionalIdentifier(referenceId, 'referenceId');
    _requireOptionalDisplayText(recipientLabel, 'recipientLabel', 256);
    _requireOptionalDisplayText(message, 'message', 1024);
  }

  final PaymentRoute route;
  final String encodedDestination;
  final String displayDestination;

  /// Amount encoded by the destination, in exact app-owned integer units.
  final WalletAmount? amount;
  final DateTime? expiresAt;

  /// Payment hash or RGB recipient identifier, when available.
  final String? referenceId;

  /// Optional recipient-authored display metadata from a payment instruction.
  final String? recipientLabel;

  /// Optional recipient-authored payment-purpose text.
  final String? message;

  bool get requiresAmount => amount == null;

  bool isExpiredAt(DateTime now) {
    final expiry = expiresAt;
    return expiry != null && !now.toUtc().isBefore(expiry);
  }

  /// Adds safe URI display metadata without retaining the original URI.
  WalletPaymentPreview withDisplayMetadata({
    String? recipientLabel,
    String? message,
  }) {
    return WalletPaymentPreview(
      route: route,
      encodedDestination: encodedDestination,
      displayDestination: displayDestination,
      amount: amount,
      expiresAt: expiresAt,
      referenceId: referenceId,
      recipientLabel: recipientLabel ?? this.recipientLabel,
      message: message ?? this.message,
    );
  }

  @override
  String toString() => 'WalletPaymentPreview(${route.target.slug})';

  @override
  bool operator ==(Object other) =>
      other is WalletPaymentPreview &&
      other.route == route &&
      other.encodedDestination == encodedDestination &&
      other.displayDestination == displayDestination &&
      other.amount == amount &&
      other.expiresAt == expiresAt &&
      other.referenceId == referenceId &&
      other.recipientLabel == recipientLabel &&
      other.message == message;

  @override
  int get hashCode => Object.hash(
    route,
    encodedDestination,
    displayDestination,
    amount,
    expiresAt,
    referenceId,
    recipientLabel,
    message,
  );
}

/// A newly-created receive request suitable for display, copy, share, and QR.
@immutable
final class WalletReceiveRequest {
  WalletReceiveRequest({
    required this.route,
    required this.encodedRequest,
    required this.displayValue,
    this.amount,
    this.expiresAt,
    this.referenceId,
    this.batchTransferIndex,
  }) {
    _requireEncoded(encodedRequest, 'encodedRequest');
    _requireEncoded(displayValue, 'displayValue');
    final value = amount;
    if (value != null) _requireRouteAmount(route, value);
    _requireUtc(expiresAt, 'expiresAt');
    _requireOptionalIdentifier(referenceId, 'referenceId');
    final index = batchTransferIndex;
    if (index != null && index < 0) {
      throw ArgumentError.value(index, 'batchTransferIndex');
    }
  }

  final PaymentRoute route;

  /// Full value encoded into the QR and copied or shared.
  final String encodedRequest;

  /// Human-readable address or invoice rendered on-screen.
  final String displayValue;
  final WalletAmount? amount;
  final DateTime? expiresAt;
  final String? referenceId;
  final int? batchTransferIndex;

  bool isExpiredAt(DateTime now) {
    final expiry = expiresAt;
    return expiry != null && !now.toUtc().isBefore(expiry);
  }

  @override
  String toString() => 'WalletReceiveRequest(${route.target.slug})';

  @override
  bool operator ==(Object other) =>
      other is WalletReceiveRequest &&
      other.route == route &&
      other.encodedRequest == encodedRequest &&
      other.displayValue == displayValue &&
      other.amount == amount &&
      other.expiresAt == expiresAt &&
      other.referenceId == referenceId &&
      other.batchTransferIndex == batchTransferIndex;

  @override
  int get hashCode => Object.hash(
    route,
    encodedRequest,
    displayValue,
    amount,
    expiresAt,
    referenceId,
    batchTransferIndex,
  );
}

/// Fully specified mutation submitted to the native wallet.
@immutable
final class WalletSendCommand {
  WalletSendCommand({
    required this.route,
    required this.destination,
    required this.amount,
    this.feeRateSatsPerVbyte = 1,
  }) {
    _requireEncoded(destination, 'destination');
    _requireRouteAmount(route, amount);
    if (amount.isZero) throw ArgumentError.value(amount.units, 'amount');
    if (feeRateSatsPerVbyte <= 0 || feeRateSatsPerVbyte > 1000000) {
      throw ArgumentError.value(feeRateSatsPerVbyte, 'feeRateSatsPerVbyte');
    }
  }

  final PaymentRoute route;
  final String destination;
  final WalletAmount amount;

  /// Integer satoshis per virtual byte used only for on-chain sends.
  final int feeRateSatsPerVbyte;

  @override
  String toString() => 'WalletSendCommand(${route.target.slug})';

  @override
  bool operator ==(Object other) =>
      other is WalletSendCommand &&
      other.route == route &&
      other.destination == destination &&
      other.amount == amount &&
      other.feeRateSatsPerVbyte == feeRateSatsPerVbyte;

  @override
  int get hashCode =>
      Object.hash(route, destination, amount, feeRateSatsPerVbyte);
}

/// Confirmed native acceptance of a send mutation.
@immutable
final class WalletSendResult {
  WalletSendResult({
    required this.route,
    required this.amount,
    required this.referenceId,
    required this.status,
    this.batchTransferIndex,
  }) {
    _requireRouteAmount(route, amount);
    _requireOptionalIdentifier(referenceId, 'referenceId');
    final index = batchTransferIndex;
    if (index != null && index < 0) {
      throw ArgumentError.value(index, 'batchTransferIndex');
    }
  }

  final PaymentRoute route;
  final WalletAmount amount;

  /// Bitcoin transaction ID or Lightning payment hash.
  final String referenceId;
  final WalletPaymentStatus status;
  final int? batchTransferIndex;

  @override
  String toString() => 'WalletSendResult(${route.target.slug}, ${status.name})';

  @override
  bool operator ==(Object other) =>
      other is WalletSendResult &&
      other.route == route &&
      other.amount == amount &&
      other.referenceId == referenceId &&
      other.status == status &&
      other.batchTransferIndex == batchTransferIndex;

  @override
  int get hashCode =>
      Object.hash(route, amount, referenceId, status, batchTransferIndex);
}

void _requireRouteAmount(PaymentRoute route, WalletAmount amount) {
  if (amount.assetId != route.asset.id || amount.rail != route.rail) {
    throw ArgumentError.value(amount, 'amount', 'Asset or rail mismatch.');
  }
}

void _requireEncoded(String value, String field) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.length > 8192 ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw ArgumentError.value(value, field, 'Invalid encoded payment value.');
  }
}

void _requireOptionalIdentifier(String? value, String field) {
  if (value == null) return;
  if (value.isEmpty ||
      value != value.trim() ||
      value.length > 1024 ||
      value.contains(RegExp(r'\s'))) {
    throw ArgumentError.value(value, field, 'Invalid payment identifier.');
  }
}

void _requireUtc(DateTime? value, String field) {
  if (value != null && !value.isUtc) {
    throw ArgumentError.value(value, field, 'Must use UTC.');
  }
}

void _requireOptionalDisplayText(String? value, String field, int maxLength) {
  if (value == null) return;
  if (value != value.trim() ||
      value.length > maxLength ||
      _unsafeDisplayCharacters.hasMatch(value)) {
    throw ArgumentError.value(value, field, 'Unsafe display text.');
  }
}

final _unsafeDisplayCharacters = RegExp(
  r'[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u070f\u180e'
  r'\u200b-\u200f\u2028\u2029\u202a-\u202e\u2060-\u206f'
  r'\ufeff\ufff9-\ufffb]',
);
