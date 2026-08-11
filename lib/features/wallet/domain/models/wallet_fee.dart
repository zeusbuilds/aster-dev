import 'package:flutter/foundation.dart';

/// Fresh app-owned on-chain fee-rate estimate.
@immutable
final class WalletFeeRateEstimate {
  WalletFeeRateEstimate({
    required this.targetBlocks,
    required this.satsPerVbyte,
    required this.observedAt,
  }) {
    if (targetBlocks < minimumTargetBlocks ||
        targetBlocks > maximumTargetBlocks) {
      throw ArgumentError.value(targetBlocks, 'targetBlocks');
    }
    if (satsPerVbyte <= 0 || satsPerVbyte > maximumSatsPerVbyte) {
      throw ArgumentError.value(satsPerVbyte, 'satsPerVbyte');
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

  bool isStaleAt(DateTime now) {
    final age = now.toUtc().difference(observedAt);
    return age.isNegative || age > maximumAge;
  }

  @override
  bool operator ==(Object other) =>
      other is WalletFeeRateEstimate &&
      other.targetBlocks == targetBlocks &&
      other.satsPerVbyte == satsPerVbyte &&
      other.observedAt == observedAt;

  @override
  int get hashCode => Object.hash(targetBlocks, satsPerVbyte, observedAt);
}
