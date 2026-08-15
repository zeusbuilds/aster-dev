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
    final available = this.capabilities
        .where((item) => item.isAvailable)
        .map((item) => item.target)
        .toSet();
    if (!available.contains(from) || !available.contains(to)) {
      throw ArgumentError('Swap selections must be available targets.');
    }
  }

  final List<WalletPaymentCapability> capabilities;
  final WalletPaymentTarget from;
  final WalletPaymentTarget to;

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
