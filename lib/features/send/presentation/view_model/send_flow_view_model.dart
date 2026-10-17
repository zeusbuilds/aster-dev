import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../../settings/domain/models/models.dart';
import '../../../wallet/data/repository/repository.dart';
import '../../../wallet/domain/models/models.dart';
import '../models/models.dart';
import 'send_destination_handoff.dart';

part 'send_flow_view_model.g.dart';

/// Owns one route-scoped Send flow from destination validation through submit.
@riverpod
class SendFlowViewModel extends _$SendFlowViewModel {
  static const _amountCodec = WalletAmountInputCodec();

  late WalletPaymentTarget _target;
  // Riverpod can rebuild a retained notifier while a read is still pending.
  // Only reads from the current build may publish back into the form.
  var _generation = 0;

  @override
  Future<SendFlowState> build(WalletPaymentTarget target) {
    _generation += 1;
    ref.onDispose(() => _generation += 1);
    _target = target;
    return _load();
  }

  /// Retries loading route metadata, display settings, balance, and fee state.
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

  /// Invalidates a prior preview whenever destination text changes.
  void updateDestination(String value) {
    final current = state.value;
    if (current == null || !current.canChangeDestination) return;
    if (value == current.destination) return;
    state = AsyncData(
      current.copyWith(
        destination: value,
        preview: null,
        amountText: '',
        amountInput: _parseAmount('', current),
        retainedFailure: null,
      ),
    );
  }

  /// Reads a bounded non-secret payment destination from the clipboard.
  Future<AppResult<String>> pasteDestination() async {
    final current = state.value;
    if (current == null || !current.canReadClipboard) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    state = AsyncData(
      current.copyWith(
        operation: SendFlowOperation.readingClipboard,
        retainedFailure: null,
      ),
    );
    final result = await ref.read(clipboardServiceProvider).readText();
    if (!ref.mounted) return _clipboardResult(result);
    return switch (result) {
      AppSuccess<String?>(:final value) => () {
        final destination = value?.trim() ?? '';
        if (destination.isEmpty) {
          state = AsyncData(current.copyWith(operation: null));
          return AppResult<String>.failure(_clipboardEmptyFailure());
        }
        state = AsyncData(
          current.copyWith(
            destination: destination,
            preview: null,
            amountText: '',
            amountInput: _parseAmount('', current),
            operation: null,
            retainedFailure: null,
          ),
        );
        unawaited(
          ref
              .read(hapticFeedbackServiceProvider)
              .trigger(HapticIntent.lightImpact),
        );
        return AppResult<String>.success(destination);
      }(),
      AppFailureResult<String?>(:final failure) => () {
        state = AsyncData(current.copyWith(operation: null));
        unawaited(
          ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.error),
        );
        return AppResult<String>.failure(failure);
      }(),
    };
  }

  /// Validates the destination on demand and adopts any encoded amount.
  Future<bool> validateDestination() async {
    final current = state.value;
    if (current == null ||
        !current.canStart(SendFlowOperation.validatingDestination) ||
        current.destination.isEmpty) {
      return false;
    }
    state = AsyncData(
      current.copyWith(
        operation: SendFlowOperation.validatingDestination,
        retainedFailure: null,
      ),
    );
    final result = await _walletOperation(
      (repository) => repository.previewPayment(_target, current.destination),
    );
    if (!ref.mounted) return result is AppSuccess<WalletPaymentPreview>;
    return switch (result) {
      AppSuccess<WalletPaymentPreview>(:final value) => _acceptPreview(
        current,
        value,
      ),
      AppFailureResult<WalletPaymentPreview>(:final failure) => _fail(
        current,
        failure,
        failedOperation: SendFlowOperation.validatingDestination,
        emitErrorHaptic: true,
      ),
    };
  }

  /// Updates exact amount state without invoking native code per key press.
  void updateAmount(String value) {
    final current = state.value;
    if (current == null || !current.canChangeAmount || current.amountIsLocked) {
      return;
    }
    if (value == current.amountText) return;
    state = AsyncData(
      current.copyWith(
        amountText: value,
        amountInput: _parseAmount(value, current),
        retainedFailure: null,
      ),
    );
  }

  /// Fills the available asset amount exactly, without estimating a fee.
  /// Bitcoin on-chain fees still require BTC in addition to this amount.
  void useMaxAmount() {
    final current = state.value;
    if (current == null || !current.canChangeAmount || current.amountIsLocked) {
      return;
    }
    var units = current.availableUnits;
    if (current.route.target == WalletPaymentTarget.bitcoinLightning) {
      units -= units % WalletAmount.millisatoshisPerSatoshi;
    }
    updateAmount(
      _amountCodec.formatUnits(
        units: units,
        route: current.route,
        bitcoinUnit: current.bitcoinUnit,
      ),
    );
  }

  /// Refreshes the selected rail's available balance.
  /// [silent] suppresses feedback for screen-owned read recovery.
  Future<bool> refreshBalance({bool silent = false}) async {
    final generation = _generation;
    final current = state.value;
    if (state.isLoading ||
        state.hasError ||
        current == null ||
        !current.canStart(SendFlowOperation.refreshingBalance)) {
      return false;
    }
    state = AsyncData(
      current.copyWith(
        operation: SendFlowOperation.refreshingBalance,
        retainedFailure: null,
      ),
    );
    final result = await _walletOperation(
      (repository) => repository.balance(current.route.asset.kind),
    );
    if (!ref.mounted || generation != _generation) return false;
    return switch (result) {
      AppSuccess<WalletBalance>(:final value) => () {
        state = AsyncData(
          current.copyWith(
            balance: value,
            operation: null,
            retainedFailure: null,
          ),
        );
        if (!silent) {
          unawaited(
            ref
                .read(hapticFeedbackServiceProvider)
                .trigger(HapticIntent.lightImpact),
          );
        }
        return true;
      }(),
      AppFailureResult<WalletBalance>(:final failure) => _fail(
        current,
        failure,
        failedOperation: SendFlowOperation.refreshingBalance,
        emitErrorHaptic: !silent,
      ),
    };
  }

  /// Refreshes the displayed quote without submitting or retrying a payment.
  /// [silent] suppresses feedback for screen-owned read recovery.
  Future<bool> refreshFee({bool silent = false}) async {
    final generation = _generation;
    final current = state.value;
    if (state.isLoading ||
        state.hasError ||
        current == null ||
        !current.canRefreshFee) {
      return false;
    }
    state = AsyncData(
      current.copyWith(
        operation: SendFlowOperation.refreshingFee,
        feeFailure: null,
        retainedFailure: null,
      ),
    );
    final result = await _walletOperation(
      (repository) => repository.estimateFeeRate(),
    );
    if (!ref.mounted || generation != _generation) return false;
    return switch (result) {
      AppSuccess<WalletFeeRateEstimate>(:final value) => () {
        state = AsyncData(
          current.copyWith(
            feeEstimate: value,
            feeFailure: null,
            operation: null,
            retainedFailure: null,
          ),
        );
        if (!silent) {
          unawaited(
            ref
                .read(hapticFeedbackServiceProvider)
                .trigger(HapticIntent.lightImpact),
          );
        }
        return true;
      }(),
      AppFailureResult<WalletFeeRateEstimate>(:final failure) => () {
        state = AsyncData(
          current.copyWith(
            feeEstimate: null,
            feeFailure: failure,
            operation: null,
          ),
        );
        if (!silent) {
          unawaited(
            ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.error),
          );
        }
        return false;
      }(),
    };
  }

  /// Submits exactly once and leaves navigation to the observing screen.
  Future<bool> submit() async {
    final current = state.value;
    if (current == null || !current.canStart(SendFlowOperation.submitting)) {
      return false;
    }
    final now = ref.read(utcClockProvider)();
    // A normal BTC send pays its network fee in addition to the recipient
    // amount. Reject the full available balance before creating any durable
    // dispatch marker; RGB token balances do not pay this fee themselves.
    if (current.hasValidatedDestination &&
        !current.isExpiredAt(now) &&
        current.route.target == WalletPaymentTarget.bitcoinOnchain &&
        current.amountInput.isValid &&
        current.amountInput.units == current.availableUnits) {
      final rejected = _fail(
        current,
        const AppFailure(
          code: 'payment_amount_leaves_no_fee',
          kind: AppFailureKind.validation,
          userMessage: 'Leave some BTC for the network fee. Lower the amount and try again.',
          retryable: false,
        ),
        failedOperation: SendFlowOperation.submitting,
      );
      unawaited(
        ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.warning),
      );
      return rejected;
    }
    if (!current.canSubmitAt(now)) {
      if (current.feeFailure != null) return false;
      final failure = _submissionFailure(current, now);
      if (failure.code == 'payment_fee_refresh_required') {
        state = AsyncData(
          current.copyWith(
            feeEstimate: null,
            feeFailure: failure,
            retainedFailure: null,
          ),
        );
        return false;
      }
      state = AsyncData(
        current.copyWith(
          retainedFailure: SendFlowFailure(
            operation: SendFlowOperation.submitting,
            failure: failure,
          ),
        ),
      );
      return false;
    }
    final preview = current.preview!;
    final units = current.amountInput.units!;
    state = AsyncData(
      current.copyWith(
        operation: SendFlowOperation.submitting,
        retainedFailure: null,
      ),
    );
    final result = await _walletOperation(
      (repository) => repository.sendPayment(
        target: _target,
        destination: preview.encodedDestination,
        amountUnits: units,
        rgbRecipientType: preview.rgbRecipientType,
        witnessBitcoinAmountSats: preview.witnessBitcoinAmountSats,
        reviewedFeeRate: current.feeEstimate,
      ),
    );
    if (!ref.mounted) return result is AppSuccess<WalletSendResult>;
    return switch (result) {
      AppSuccess<WalletSendResult>(:final value) => () {
        state = AsyncData(
          current.copyWith(
            result: value,
            operation: null,
            retainedFailure: null,
          ),
        );
        unawaited(
          ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.success),
        );
        return true;
      }(),
      AppFailureResult<WalletSendResult>(:final failure)
          when failure.code == walletFeeReviewRequiredFailure.code ||
              failure.code == walletFeeReviewChangedFailure.code =>
        () {
          state = AsyncData(
            current.copyWith(
              operation: null,
              feeEstimate: null,
              feeFailure: failure,
              retainedFailure: null,
            ),
          );
          return false;
        }(),
      AppFailureResult<WalletSendResult>(:final failure) => _fail(
        current,
        failure,
        failedOperation: SendFlowOperation.submitting,
        emitErrorHaptic: true,
      ),
    };
  }

  Future<SendFlowState> _load() async {
    try {
      return await _loadUnsafe();
    } catch (error, stackTrace) {
      throw AppFailureException(FailureMapper.from(error, stackTrace));
    }
  }

  Future<SendFlowState> _loadUnsafe() async {
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
    final balanceResult = await repository.balance(route.asset.kind);
    if (balanceResult case AppFailureResult<WalletBalance>(:final failure)) {
      throw AppFailureException(failure);
    }
    final balance = (balanceResult as AppSuccess<WalletBalance>).value;
    WalletFeeRateEstimate? feeEstimate;
    AppFailure? feeFailure;
    if (route.rail == PaymentRail.onchain) {
      final feeResult = await repository.estimateFeeRate();
      switch (feeResult) {
        case AppSuccess<WalletFeeRateEstimate>(:final value):
          feeEstimate = value;
        case AppFailureResult<WalletFeeRateEstimate>(:final failure):
          feeFailure = failure;
      }
    }
    final stagedDestination = ref
        .read(sendDestinationHandoffProvider.notifier)
        .take();
    return SendFlowState(
      route: route,
      bitcoinUnit: bitcoinUnit,
      currencyCode: settingsSnapshot.preferences.currencyCode,
      balance: balance,
      destination: stagedDestination ?? '',
      amountText: '',
      amountInput: _amountCodec.parse(
        text: '',
        route: route,
        bitcoinUnit: bitcoinUnit,
      ),
      feeEstimate: feeEstimate,
      feeFailure: feeFailure,
    );
  }

  bool _acceptPreview(SendFlowState previous, WalletPaymentPreview preview) {
    if (preview.isExpiredAt(ref.read(utcClockProvider)())) {
      return _fail(
        previous,
        _expiredRequestFailure(),
        failedOperation: SendFlowOperation.validatingDestination,
      );
    }
    final encodedAmount = preview.amount;
    final amountText = encodedAmount == null
        ? ''
        : _amountCodec.formatUnits(
            units: encodedAmount.units,
            route: previous.route,
            bitcoinUnit: previous.bitcoinUnit,
          );
    state = AsyncData(
      previous.copyWith(
        preview: preview,
        amountText: amountText,
        amountInput: _parseAmount(amountText, previous),
        operation: null,
        retainedFailure: null,
      ),
    );
    return true;
  }

  WalletAmountInput _parseAmount(String text, SendFlowState state) {
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

  bool _fail(
    SendFlowState previous,
    AppFailure failure, {
    required SendFlowOperation failedOperation,
    bool emitErrorHaptic = false,
  }) {
    state = AsyncData(
      previous.copyWith(
        operation: null,
        retainedFailure: SendFlowFailure(
          operation: failedOperation,
          failure: failure,
        ),
      ),
    );
    if (emitErrorHaptic) {
      unawaited(
        ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.error),
      );
    }
    return false;
  }

  static AppFailure _submissionFailure(SendFlowState state, DateTime now) {
    if (state.isExpiredAt(now)) {
      return _expiredRequestFailure();
    }
    if (!state.amountInput.isValid) {
      return const AppFailure(
        code: 'payment_amount_invalid',
        kind: AppFailureKind.validation,
        userMessage: 'Enter a valid amount.',
        retryable: false,
      );
    }
    if (!state.amountUsesSupportedGranularity) {
      return const AppFailure(
        code: 'payment_amount_requires_whole_satoshis',
        kind: AppFailureKind.validation,
        userMessage: 'Enter a whole-satoshi Lightning amount.',
        retryable: false,
      );
    }
    if (!state.hasSufficientBalance) {
      return const AppFailure(
        code: 'payment_balance_insufficient',
        kind: AppFailureKind.validation,
        userMessage: 'The available balance is too low for this amount.',
        retryable: false,
      );
    }
    if (state.route.rail == PaymentRail.onchain) {
      return AppFailure(
        code: 'payment_fee_refresh_required',
        kind: AppFailureKind.unavailable,
        userMessage:
            state.feeEstimate?.source == WalletFeeRateSource.localRegtestPolicy
            ? 'Refresh the local test fee rate before sending.'
            : 'Refresh the network fee before sending.',
        retryable: true,
      );
    }
    return const AppFailure(
      code: 'payment_not_ready',
      kind: AppFailureKind.conflict,
      userMessage: 'Review the payment details before sending.',
      retryable: false,
    );
  }

  static AppFailure _expiredRequestFailure() => const AppFailure(
    code: 'payment_request_expired',
    kind: AppFailureKind.validation,
    userMessage: 'This payment request has expired.',
    retryable: false,
  );

  static AppResult<String> _clipboardResult(AppResult<String?> result) {
    return switch (result) {
      AppSuccess<String?>(:final value)
          when value != null && value.trim().isNotEmpty =>
        AppResult.success(value.trim()),
      AppSuccess<String?>() => AppResult.failure(_clipboardEmptyFailure()),
      AppFailureResult<String?>(:final failure) => AppResult.failure(failure),
    };
  }

  static AppFailure _clipboardEmptyFailure() => const AppFailure(
    code: 'clipboard_empty',
    kind: AppFailureKind.validation,
    userMessage: 'The clipboard does not contain a payment address.',
    retryable: false,
  );

  static AppFailure _operationUnavailableFailure() => const AppFailure(
    code: 'payment_operation_in_progress',
    kind: AppFailureKind.conflict,
    userMessage: 'Wait for the current payment action to finish.',
    retryable: false,
  );
}
