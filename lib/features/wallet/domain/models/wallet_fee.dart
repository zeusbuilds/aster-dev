import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';

/// Provenance of the selected rate; local test policy is never a network quote.
enum WalletFeeRateSource { networkEstimate, localRegtestPolicy }

/// Known pre-dispatch failures: refreshing a quote never submits a payment.
const walletFeeReviewRequiredFailure = AppFailure(
  code: 'payment_fee_review_required',
  kind: AppFailureKind.conflict,
  userMessage: 'The network fee needs checking. Tap Send to try again.',
  retryable: true,
);

const walletFeeReviewChangedFailure = AppFailure(
  code: 'payment_fee_review_changed',
  kind: AppFailureKind.conflict,
  userMessage: 'The fee changed. Tap Send to check it again.',
  retryable: true,
);

/// A fresh quote is displayed, but only another deliberate Send may dispatch.
const walletFeeUpdatedReviewFailure = AppFailure(
  code: 'payment_fee_review_updated',
  kind: AppFailureKind.conflict,
  userMessage: 'The fee is updated. Review it and send again.',
  retryable: true,
);

/// App-owned on-chain fee rate with a bounded review lifetime.
@immutable
final class WalletFeeRateEstimate {
  WalletFeeRateEstimate({
    required this.targetBlocks,
    required this.satsPerVbyte,
    required this.observedAt,
    this.source = WalletFeeRateSource.networkEstimate,
  }) {
    if (targetBlocks < minimumTargetBlocks ||
        targetBlocks > maximumTargetBlocks) {
      throw ArgumentError.value(targetBlocks, 'targetBlocks');
    }
    if (satsPerVbyte <= 0 || satsPerVbyte > maximumSatsPerVbyte) {
      throw ArgumentError.value(satsPerVbyte, 'satsPerVbyte');
    }
    if (source == WalletFeeRateSource.localRegtestPolicy && satsPerVbyte != 1) {
      throw ArgumentError.value(
        satsPerVbyte,
        'satsPerVbyte',
        'Local regtest policy is one sat/vbyte.',
      );
    }
    if (!observedAt.isUtc) {
      throw ArgumentError.value(observedAt, 'observedAt', 'Must use UTC.');
    }
  }

  static const minimumTargetBlocks = 1;
  static const maximumTargetBlocks = 65535;
  static const maximumSatsPerVbyte = 1000000;
  static const maximumAge = Duration(minutes: 2);

  final int targetBlocks;
  final int satsPerVbyte;
  final DateTime observedAt;
  final WalletFeeRateSource source;

  bool isStaleAt(DateTime now) {
    final age = now.toUtc().difference(observedAt);
    return age.isNegative || age > maximumAge;
  }

  @override
  bool operator ==(Object other) =>
      other is WalletFeeRateEstimate &&
      other.targetBlocks == targetBlocks &&
      other.satsPerVbyte == satsPerVbyte &&
      other.observedAt == observedAt &&
      other.source == source;

  @override
  int get hashCode =>
      Object.hash(targetBlocks, satsPerVbyte, observedAt, source);
}
