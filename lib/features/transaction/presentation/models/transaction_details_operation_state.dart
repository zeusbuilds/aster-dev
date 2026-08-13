import 'package:flutter/foundation.dart';

/// Copyable identifiers exposed by the transaction-details presentation.
enum TransactionDetailField {
  transactionId,
  paymentHash,
  invoice,
  recipient,
  payeePublicKey,
  receiveOutpoint,
  changeOutpoint,
}

/// Immutable route-scoped state for transaction-details platform operations.
@immutable
final class TransactionDetailsOperationState {
  const TransactionDetailsOperationState({
    required this.explorerUri,
    this.copyingField,
    this.openingExplorer = false,
  });

  /// Validated public explorer destination, or `null` when unavailable.
  final Uri? explorerUri;

  /// Detail currently awaiting a clipboard result.
  final TransactionDetailField? copyingField;

  /// Whether the explorer launch is awaiting a platform result.
  final bool openingExplorer;

  /// Starts one clipboard operation while preserving explorer state.
  TransactionDetailsOperationState beginCopy(TransactionDetailField field) {
    return TransactionDetailsOperationState(
      explorerUri: explorerUri,
      copyingField: field,
      openingExplorer: openingExplorer,
    );
  }

  /// Completes the active clipboard operation.
  TransactionDetailsOperationState completeCopy() {
    return TransactionDetailsOperationState(
      explorerUri: explorerUri,
      openingExplorer: openingExplorer,
    );
  }

  /// Starts the explorer operation while preserving clipboard state.
  TransactionDetailsOperationState beginExplorer() {
    return TransactionDetailsOperationState(
      explorerUri: explorerUri,
      copyingField: copyingField,
      openingExplorer: true,
    );
  }

  /// Completes the explorer operation.
  TransactionDetailsOperationState completeExplorer() {
    return TransactionDetailsOperationState(
      explorerUri: explorerUri,
      copyingField: copyingField,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TransactionDetailsOperationState &&
      other.explorerUri == explorerUri &&
      other.copyingField == copyingField &&
      other.openingExplorer == openingExplorer;

  @override
  int get hashCode => Object.hash(explorerUri, copyingField, openingExplorer);
}
