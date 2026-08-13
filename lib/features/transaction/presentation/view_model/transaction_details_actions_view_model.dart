import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../models/models.dart';

part 'transaction_details_actions_view_model.g.dart';

/// Owns route-scoped copy and explorer operations for transaction details.
@riverpod
class TransactionDetailsActionsViewModel
    extends _$TransactionDetailsActionsViewModel {
  var _stateGeneration = 0;
  var _copyRevision = 0;
  var _explorerRevision = 0;

  @override
  TransactionDetailsOperationState build(
    String activityId,
    String? transactionId,
  ) {
    _stateGeneration += 1;
    _copyRevision += 1;
    _explorerRevision += 1;
    final configuration = ref.watch(walletServiceConfigurationProvider);
    return TransactionDetailsOperationState(
      explorerUri: transactionId == null
          ? null
          : configuration.transactionExplorerUri(transactionId),
    );
  }

  /// Copies one non-secret identifier and suppresses overlapping writes.
  ///
  /// Returns `null` when another copy is already active or this route owner has
  /// been disposed. Platform failures are converted to redacted app failures.
  Future<AppResult<void>?> copyField(
    TransactionDetailField field,
    String value,
  ) async {
    if (state.copyingField != null) return null;
    final generation = _stateGeneration;
    final revision = ++_copyRevision;
    state = state.beginCopy(field);
    final result = await _guard(() {
      return ref.read(clipboardServiceProvider).writeText(value);
    });
    if (!ref.mounted ||
        generation != _stateGeneration ||
        revision != _copyRevision) {
      return null;
    }
    state = state.completeCopy();
    _emitResultHaptic(result, success: HapticIntent.lightImpact);
    return result;
  }

  /// Opens the validated explorer destination and suppresses duplicate opens.
  ///
  /// Returns `null` when this build has no explorer, an open is already active,
  /// or this route owner has been disposed.
  Future<AppResult<void>?> openExplorer() async {
    final uri = state.explorerUri;
    if (uri == null || state.openingExplorer) return null;
    final generation = _stateGeneration;
    final revision = ++_explorerRevision;
    state = state.beginExplorer();
    final result = await _guard(() {
      return ref.read(externalUriServiceProvider).open(uri);
    });
    if (!ref.mounted ||
        generation != _stateGeneration ||
        revision != _explorerRevision) {
      return null;
    }
    state = state.completeExplorer();
    _emitResultHaptic(result, success: HapticIntent.lightImpact);
    return result;
  }

  Future<AppResult<void>> _guard(
    Future<AppResult<void>> Function() action,
  ) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  void _emitResultHaptic(
    AppResult<void> result, {
    required HapticIntent success,
  }) {
    final intent = switch (result) {
      AppSuccess<void>() => success,
      AppFailureResult<void>() => HapticIntent.error,
    };
    unawaited(ref.read(hapticFeedbackServiceProvider).trigger(intent));
  }
}
