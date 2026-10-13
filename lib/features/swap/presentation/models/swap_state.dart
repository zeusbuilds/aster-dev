import 'package:flutter/foundation.dart';

import '../../../wallet/domain/models/models.dart';

/// In-memory selection state for the non-executable swap preview.
@immutable
final class SwapState {
  SwapState({
    required List<WalletPaymentCapability> capabilities,
    required this.from,
    required this.to,
  }) : capabilities = List<WalletPaymentCapability>.unmodifiable(capabilities) {
    if (from == to) {
      throw ArgumentError('Swap selections must be different.');
    }
    final targets = this.capabilities.map((item) => item.target).toSet();
    if (!targets.contains(from) || !targets.contains(to)) {
      throw ArgumentError('Swap selections must be known targets.');
    }
  }

  final List<WalletPaymentCapability> capabilities;
  final WalletPaymentTarget from;
  final WalletPaymentTarget to;

  /// Unconfigured targets may be displayed, but never selected or reversed.
  /// Swap is a non-executable preview even when both targets are available.
  bool get canReverse =>
      capabilities.any((item) => item.target == from && item.isAvailable) &&
      capabilities.any((item) => item.target == to && item.isAvailable);

  SwapState copyWith({WalletPaymentTarget? from, WalletPaymentTarget? to}) {
    return SwapState(
      capabilities: capabilities,
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SwapState &&
      listEquals(other.capabilities, capabilities) &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(Object.hashAll(capabilities), from, to);
}
