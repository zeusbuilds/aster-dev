import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../../../core/config/app_environment.dart';
import '../../domain/models/models.dart';
import '../../domain/validation/validation.dart';

/// Fail-closed scalar conversion at the native SDK boundary.
///
/// This is an implementation collaborator of [RgbWalletEngine] and is not
/// exported from the wallet runtime barrel. Keeping wire vocabulary and
/// bounds here prevents individual API methods from inventing conversion
/// policy.
final class RgbWalletNativeValueParser {
  const RgbWalletNativeValueParser();

  static const _maximumUnixSeconds = 253402300799;

  String identifier(String value, String field) {
    if (!WalletProtocolText.isIdentifier(value)) {
      throw NativeProtocolException(
        'Native wallet returned a malformed payment identifier.',
        field: field,
      );
    }
    return value;
  }

  String? optionalIdentifier(String? value, String field) =>
      value == null ? null : identifier(value, field);

  int? optionalIndex(int? value, String field) {
    if (value != null && value < 0) {
      throw NativeProtocolException(
        'Native wallet returned an invalid transfer index.',
        field: field,
      );
    }
    return value;
  }

  WalletAmount amount(PaymentRoute route, int units, String field) {
    try {
      return route.rail == PaymentRail.onchain
          ? WalletAmount.onchain(assetId: route.asset.id, units: units)
          : WalletAmount.lightning(assetId: route.asset.id, units: units);
    } on ArgumentError {
      throw NativeProtocolException(
        'Native payment amount is outside supported bounds.',
        field: field,
      );
    }
  }

  DateTime? optionalUnixSeconds(int? value, String field) =>
      value == null ? null : unixSeconds(value, field);

  DateTime unixSeconds(int value, String field) {
    if (value < 0 || value > _maximumUnixSeconds) {
      throw NativeProtocolException(
        'Native timestamp is outside supported bounds.',
        field: field,
      );
    }
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }

  DateTime addSeconds(DateTime value, int seconds, String field) {
    if (seconds < 0) {
      throw NativeProtocolException(
        'Native duration must not be negative.',
        field: field,
      );
    }
    final resultMicros =
        BigInt.from(value.microsecondsSinceEpoch) +
        BigInt.from(seconds) * BigInt.from(Duration.microsecondsPerSecond);
    if (resultMicros >
        BigInt.from(_maximumUnixSeconds) *
            BigInt.from(Duration.microsecondsPerSecond)) {
      throw NativeProtocolException(
        'Native timestamp is outside supported bounds.',
        field: field,
      );
    }
    return DateTime.fromMicrosecondsSinceEpoch(
      resultMicros.toInt(),
      isUtc: true,
    );
  }

  WalletPaymentStatus paymentStatus(String? value) => switch (value) {
    null ||
    RlnPaymentStatuses.pending ||
    RlnPaymentStatuses.claimable ||
    RlnPaymentStatuses.claiming => WalletPaymentStatus.pending,
    RlnPaymentStatuses.succeeded => WalletPaymentStatus.succeeded,
    RlnPaymentStatuses.cancelled => WalletPaymentStatus.cancelled,
    RlnPaymentStatuses.failed => WalletPaymentStatus.failed,
    _ => throw const NativeProtocolException(
      'Native payment returned an unknown status.',
      field: 'LightningSendRequest.status',
    ),
  };

  BlockchainEnvironment environment(String value) => switch (value) {
    // These are pinned-SDK wire values, not Aster chain-environment names.
    'bitcoin' => BlockchainEnvironment.mainnet,
    'utexo' => BlockchainEnvironment.signet,
    _ => BlockchainEnvironment.parse(value),
  };

  void requireNonNegative(int value, String field) {
    if (value < 0) {
      throw NativeProtocolException(
        'Native monetary value must not be negative.',
        field: field,
      );
    }
  }

  int requirePresent(int? value, String field) {
    if (value == null) {
      throw NativeProtocolException(
        'Native monetary value is missing.',
        field: field,
      );
    }
    return value;
  }

  int sum(Iterable<int> values, String field) {
    var total = BigInt.zero;
    for (final value in values) {
      requireNonNegative(value, field);
      total += BigInt.from(value);
      if (total > BigInt.from(WalletAmount.maxNativeUnits)) {
        throw NativeProtocolException(
          'Native monetary aggregate exceeds supported bounds.',
          field: field,
        );
      }
    }
    return total.toInt();
  }

  /// Narrows exact SDK values to the app's signed native amount domain.
  /// Never use BigInt.toInt directly: it clamps out-of-range values.
  int exactUnits(BigInt value, String field) =>
      _checkedNativeValue(value, field);

  int requireExactUnits(BigInt? value, String field) {
    if (value == null) {
      throw NativeProtocolException(
        'Native monetary value is missing.',
        field: field,
      );
    }
    return exactUnits(value, field);
  }

  int checkedAdd(int left, int right, String field) =>
      _checkedNativeValue(BigInt.from(left) + BigInt.from(right), field);

  int checkedSubtract(int left, int right, String field) =>
      _checkedNativeValue(BigInt.from(left) - BigInt.from(right), field);

  int checkedMultiply(int left, int right, String field) =>
      _checkedNativeValue(BigInt.from(left) * BigInt.from(right), field);

  int _checkedNativeValue(BigInt value, String field) {
    if (value.isNegative || value > BigInt.from(WalletAmount.maxNativeUnits)) {
      throw NativeProtocolException(
        'Native monetary value exceeds supported bounds.',
        field: field,
      );
    }
    return value.toInt();
  }
}
