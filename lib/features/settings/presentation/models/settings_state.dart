import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../domain/models/models.dart';

/// Settings field currently being committed to durable preferences.
enum SettingsOperation { currency, region, bitcoinUnit, balanceVisibility }

/// Immutable settings presentation state with operation-specific progress.
@immutable
final class SettingsState {
  const SettingsState({
    required this.snapshot,
    this.operation,
    this.operationFailure,
  });

  final SettingsSnapshot snapshot;
  final SettingsOperation? operation;
  final AppFailure? operationFailure;

  bool get isSaving => operation != null;

  SettingsState copyWith({
    SettingsSnapshot? snapshot,
    Object? operation = _unset,
    Object? operationFailure = _unset,
  }) {
    return SettingsState(
      snapshot: snapshot ?? this.snapshot,
      operation: identical(operation, _unset)
          ? this.operation
          : operation as SettingsOperation?,
      operationFailure: identical(operationFailure, _unset)
          ? this.operationFailure
          : operationFailure as AppFailure?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SettingsState &&
      other.snapshot == snapshot &&
      other.operation == operation &&
      other.operationFailure == operationFailure;

  @override
  int get hashCode => Object.hash(snapshot, operation, operationFailure);
}

const _unset = Object();
