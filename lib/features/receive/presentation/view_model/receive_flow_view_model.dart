import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../../settings/domain/models/models.dart';
import '../../../wallet/data/repository/repository.dart';
import '../../../wallet/domain/models/models.dart';
import '../models/models.dart';

part 'receive_flow_view_model.g.dart';

/// Owns one route-scoped Receive request and its optional exact amount.
@riverpod
class ReceiveFlowViewModel extends _$ReceiveFlowViewModel {
  static const _amountCodec = WalletAmountInputCodec();

  late WalletPaymentTarget _target;

  @override
  Future<ReceiveFlowState> build(WalletPaymentTarget target) {
    _target = target;
    return _load();
  }

  /// Retries initial route resolution and request generation.
  Future<void> retry() async {
    final failure = switch (state) {
      AsyncError(:final error, :final stackTrace) => FailureMapper.from(
        error,
        stackTrace,
      ),
      _ => null,
    };
    if (failure == null || !failure.retryable) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(_load);
    if (ref.mounted) state = next;
  }

  /// Updates pending amount-sheet input without regenerating on every key.
  void updateAmount(String value) {
    final current = state.value;
    if (current == null || !current.canEditAmount) return;
    if (value == current.amountText) return;
    state = AsyncData(
      current.copyWith(
        amountText: value,
        amountInput: _parseAmount(value, current),
        retainedFailure: null,
      ),
    );
  }

  /// Applies the pending amount and replaces the QR only after native success.
  Future<bool> applyAmount() async {
    final current = state.value;
    if (current == null || !current.canApplyAmount) return false;
    final units = current.amountText.isEmpty ? null : current.amountInput.units;
    return _generate(current, amountUnits: units, emitSuccessHaptic: true);
  }

  /// Generates a new address or invoice while preserving the applied amount.
  Future<bool> regenerate() async {
    final current = state.value;
    if (current == null || !current.canRegenerate) return false;
    return _generate(
      current,
      amountUnits: current.request!.amount?.units,
      emitSuccessHaptic: true,
    );
  }

  /// Copies the currently encoded request through the app platform boundary.
  Future<AppResult<void>> copyRequest() async {
    final current = state.value;
    if (current == null) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    if (_requestReadFailure(current) case final failure?) {
      return AppResult.failure(failure);
    }
    state = AsyncData(
      current.copyWith(operation: ReceiveFlowOperation.copyingRequest),
    );
    final request = current.request!;
    final result = await ref
        .read(clipboardServiceProvider)
        .writeText(request.encodedRequest);
    if (!ref.mounted) return result;
    state = AsyncData(current.copyWith(operation: null));
    unawaited(
      ref
          .read(hapticFeedbackServiceProvider)
          .trigger(
            result is AppSuccess<void>
                ? HapticIntent.lightImpact
                : HapticIntent.error,
          ),
    );
    return result;
  }

  /// Opens the platform share sheet without exposing the request to widgets.
  Future<AppResult<ShareDisposition>> shareRequest({
    ShareOrigin? origin,
  }) async {
    final current = state.value;
    if (current == null) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    if (_requestReadFailure(current) case final failure?) {
      return AppResult.failure(failure);
    }
    state = AsyncData(
      current.copyWith(operation: ReceiveFlowOperation.sharingRequest),
    );
    final request = current.request!;
    final result = await ref
        .read(shareServiceProvider)
        .shareText(
          request.encodedRequest,
          subject: '${current.route.asset.displayName} payment request',
          origin: origin,
        );
    if (!ref.mounted) return result;
    state = AsyncData(current.copyWith(operation: null));
    if (result case AppFailureResult<ShareDisposition>()) {
      unawaited(
        ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.error),
      );
    }
    return result;
  }

  Future<ReceiveFlowState> _load() async {
    try {
      return await _loadUnsafe();
    } catch (error, stackTrace) {
      throw AppFailureException(FailureMapper.from(error, stackTrace));
    }
  }

  Future<ReceiveFlowState> _loadUnsafe() async {
    final repository = await ref.read(walletRepositoryProvider.future);
    final settings = await ref.read(settingsRepositoryProvider.future);
    final routeResult = repository.resolvePaymentTarget(_target);
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      throw AppFailureException(failure);
    }
    final route = (routeResult as AppSuccess<PaymentRoute>).value;
    final settingsResult = await settings.load();
    if (settingsResult case AppFailureResult<SettingsSnapshot>(
      :final failure,
    )) {
      throw AppFailureException(failure);
    }
    final settingsSnapshot =
        (settingsResult as AppSuccess<SettingsSnapshot>).value;
    final bitcoinUnit = settingsSnapshot.preferences.bitcoinUnit;
    final WalletReceiveRequest? request;
    if (_target.requiresReceiveAmount) {
      request = null;
    } else {
      final requestResult = await repository.createReceiveRequest(_target);
      if (requestResult case AppFailureResult<WalletReceiveRequest>(
        :final failure,
      )) {
        throw AppFailureException(failure);
      }
      request = (requestResult as AppSuccess<WalletReceiveRequest>).value;
    }
    return ReceiveFlowState(
      route: route,
      bitcoinUnit: bitcoinUnit,
      request: request,
      amountText: '',
      amountInput: _amountCodec.parse(
        text: '',
        route: route,
        bitcoinUnit: bitcoinUnit,
      ),
    );
  }

  Future<bool> _generate(
    ReceiveFlowState previous, {
    required int? amountUnits,
    required bool emitSuccessHaptic,
  }) async {
    state = AsyncData(
      previous.copyWith(
        operation: ReceiveFlowOperation.generatingRequest,
        retainedFailure: null,
      ),
    );
    final result = await _walletOperation(
      (repository) =>
          repository.createReceiveRequest(_target, amountUnits: amountUnits),
    );
    if (!ref.mounted) return result is AppSuccess<WalletReceiveRequest>;
    return switch (result) {
      AppSuccess<WalletReceiveRequest>(:final value) => () {
        final amount = value.amount;
        final amountText = amount == null
            ? ''
            : _amountCodec.formatUnits(
                units: amount.units,
                route: previous.route,
                bitcoinUnit: previous.bitcoinUnit,
              );
        state = AsyncData(
          previous.copyWith(
            request: value,
            amountText: amountText,
            amountInput: _parseAmount(amountText, previous),
            operation: null,
            retainedFailure: null,
          ),
        );
        if (emitSuccessHaptic) {
          unawaited(
            ref
                .read(hapticFeedbackServiceProvider)
                .trigger(HapticIntent.success),
          );
        }
        return true;
      }(),
      AppFailureResult<WalletReceiveRequest>(:final failure) => () {
        state = AsyncData(
          previous.copyWith(
            operation: null,
            retainedFailure: ReceiveFlowFailure(
              operation: ReceiveFlowOperation.generatingRequest,
              failure: failure,
            ),
          ),
        );
        unawaited(
          ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.error),
        );
        return false;
      }(),
    };
  }

  WalletAmountInput _parseAmount(String text, ReceiveFlowState state) {
    return _amountCodec.parse(
      text: text,
      route: state.route,
      bitcoinUnit: state.bitcoinUnit,
    );
  }

  Future<AppResult<T>> _walletOperation<T>(
    Future<AppResult<T>> Function(WalletRepository repository) operation,
  ) async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return await operation(repository);
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  AppFailure? _requestReadFailure(ReceiveFlowState current) {
    if (current.isBusy) {
      return _operationUnavailableFailure();
    }
    if (current.request == null) return _requestNotReadyFailure;
    if (current.isExpiredAt(ref.read(utcClockProvider)())) {
      return _requestExpiredFailure;
    }
    return null;
  }

  static AppFailure _operationUnavailableFailure() => const AppFailure(
    code: 'payment_operation_in_progress',
    kind: AppFailureKind.conflict,
    userMessage: 'Wait for the current payment action to finish.',
    retryable: false,
  );

  static const _requestExpiredFailure = AppFailure(
    code: 'payment_request_expired',
    kind: AppFailureKind.validation,
    userMessage: 'This payment request has expired. Generate a new request.',
    retryable: false,
  );

  static const _requestNotReadyFailure = AppFailure(
    code: 'payment_request_not_ready',
    kind: AppFailureKind.conflict,
    userMessage: 'Set an amount before using this payment request.',
    retryable: false,
  );
}
