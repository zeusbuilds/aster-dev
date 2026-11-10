import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/errors/errors.dart';
import '../models/models.dart';

part 'send_destination_handoff.g.dart';

/// Owns the one-shot, in-memory handoff from the persistent Scan tab to Send.
@Riverpod(keepAlive: true)
class SendDestinationHandoff extends _$SendDestinationHandoff {
  @override
  SendDestinationHandoffValue? build() => null;

  /// Replaces the pending destination only when [value] is bounded and safe.
  AppResult<void> stage(String value) {
    try {
      state = SendDestinationHandoffValue(value);
      return const AppResult.success(null);
    } on InvalidSendDestinationHandoffException catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'send_destination_handoff_invalid',
          kind: AppFailureKind.validation,
          userMessage: 'This code is not a supported payment value.',
          retryable: false,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Consumes only the scan that was pending when this form began loading.
  String? take(SendDestinationHandoffValue staged) {
    if (!identical(state, staged)) return null;
    state = null;
    return staged.value;
  }

  /// Removes any unconsumed destination when its owning Send flow exits.
  void clear() {
    state = null;
  }
}
