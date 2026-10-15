import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../../settings/data/repository/repository.dart';
import '../../../settings/domain/models/models.dart';
import '../../../wallet/data/repository/repository.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/models/models.dart';
import '../../../wallet/presentation/view_model/wallet_view_model.dart';
import '../models/models.dart';

part 'receive_flow_view_model.g.dart';

final class _ReceiveGeneration {
  _ReceiveGeneration(
    this.target,
    this.repository,
    this.settings,
    this.clock,
    this.wallet,
    this.walletId,
  );
  final WalletPaymentTarget target;
  final Future<WalletRepository> repository;
  final Future<SettingsRepository> settings;
  final DateTime Function() clock;
  final Future<WalletState> wallet;
  final String? walletId;
  bool active = true;
}

final class _ReceiveGenerationChanged implements Exception {
  const _ReceiveGenerationChanged();
}

/// Owns one route-scoped Receive request and its optional exact amount.
@riverpod
class ReceiveFlowViewModel extends _$ReceiveFlowViewModel {
  static const _amountCodec = WalletAmountInputCodec();

  late WalletPaymentTarget _target;
  _ReceiveGeneration? _generation;
  bool _isCurrent(_ReceiveGeneration? value) =>
      value != null && value.active && identical(value, _generation);
  void _requireCurrent(_ReceiveGeneration value) {
    if (!_isCurrent(value)) throw const _ReceiveGenerationChanged();
  }

  ReceiveFlowState? get _readyState {
    if (!_isCurrent(_generation) || state.isLoading || state.hasError) {
      return null;
    }
    return state.value;
  }

  static ({String? walletId, bool changing}) _walletContext(
    AsyncValue<WalletState> wallet,
  ) => (
    walletId: wallet.value?.activeWallet?.id,
    changing:
        wallet.isLoading ||
        wallet.hasError ||
        wallet.value?.switchingWalletId != null,
  );

  Future<void> _requireWalletContext(_ReceiveGeneration generation) async {
    final wallet = await generation.wallet;
    _requireCurrent(generation);
    if (generation.walletId == null ||
        wallet.activeWallet?.id != generation.walletId ||
        wallet.switchingWalletId != null) {
      throw AppFailureException(_operationUnavailableFailure());
    }
  }

  bool _setupCommandInFlight = false;
  RgbReceiveMode _rgbReceiveMode = RgbReceiveMode.witness;
  RgbReceiveMode get rgbReceiveMode => _rgbReceiveMode;

  Future<void> setRgbReceiveMode(RgbReceiveMode mode) async {
    final generation = _generation;
    if (!_isCurrent(generation)) return;
    if (_target != WalletPaymentTarget.usdtOnchain ||
        _setupCommandInFlight ||
        state.isLoading ||
        (state.value?.isBusy ?? false) ||
        mode == _rgbReceiveMode) {
      return;
    }
    _rgbReceiveMode = mode;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(() => _load(generation!, mode));
    if (_isCurrent(generation)) state = next;
  }

  Future<AppResult<RgbWalletSetupReview>> prepareRgbSetup() async {
    final generation = _generation;
    if (!_isCurrent(generation)) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    if (_setupCommandInFlight ||
        _target != WalletPaymentTarget.usdtOnchain ||
        _rgbReceiveMode != RgbReceiveMode.blind) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    _setupCommandInFlight = true;
    try {
      final result = await _walletOperation(
        (repository) => repository.prepareRgbWalletSetup(),
      );
      if (result case AppFailureResult<RgbWalletSetupReview>(:final failure)) {
        _setupFailure(failure, generation);
      }
      return result;
    } finally {
      _setupCommandInFlight = false;
    }
  }

  Future<void> cancelRgbSetup(RgbWalletSetupReview review) async {
    final generation = _generation;
    final result = await _walletOperation(
      (repository) => repository.cancelRgbWalletSetup(review),
    );
    if (result case AppFailureResult<void>(:final failure)) {
      _setupFailure(failure, generation);
    }
  }

  Future<void> confirmRgbSetup(RgbWalletSetupReview review) async {
    final generation = _generation;
    if (!_isCurrent(generation)) return;
    if (_setupCommandInFlight) return;
    _setupCommandInFlight = true;
    try {
      final result = await _walletOperation(
        (repository) => repository.confirmRgbWalletSetup(review),
      );
      if (!_isCurrent(generation)) return;
      switch (result) {
        case AppSuccess<RgbWalletSetupStatus>(:final value):
          await _adoptRgbSetupStatus(value, generation!);
        case AppFailureResult<RgbWalletSetupStatus>(:final failure):
          _setupFailure(failure, generation);
      }
    } finally {
      _setupCommandInFlight = false;
    }
  }

  Future<void> checkRgbSetup() async {
    final generation = _generation;
    if (!_isCurrent(generation)) return;
    if (_setupCommandInFlight) return;
    _setupCommandInFlight = true;
    try {
      final result = await _walletOperation(
        (repository) => repository.rgbWalletSetupStatus(),
      );
      if (!_isCurrent(generation)) return;
      switch (result) {
        case AppSuccess<RgbWalletSetupStatus>(:final value):
          await _adoptRgbSetupStatus(value, generation!);
        case AppFailureResult<RgbWalletSetupStatus>(:final failure):
          _setupFailure(failure, generation);
      }
    } finally {
      _setupCommandInFlight = false;
    }
  }

  Future<void> _adoptRgbSetupStatus(
    RgbWalletSetupStatus status,
    _ReceiveGeneration generation,
  ) async {
    if (!_isCurrent(generation)) return;
    if (status.phase == RgbWalletSetupPhase.ready ||
        status.phase == RgbWalletSetupPhase.required) {
      state = const AsyncLoading();
      final next = await AsyncValue.guard(
        () => _load(generation, _rgbReceiveMode),
      );
      if (_isCurrent(generation)) state = next;
    } else {
      _setupFailure(
        status.phase == RgbWalletSetupPhase.required
            ? rgbWalletSetupRequiredFailure
            : rgbWalletSetupPendingFailure,
        generation,
      );
    }
  }

  void _setupFailure(AppFailure failure, _ReceiveGeneration? generation) {
    if (_isCurrent(generation)) {
      state = AsyncError(AppFailureException(failure), StackTrace.current);
    }
  }

  @override
  Future<ReceiveFlowState> build(WalletPaymentTarget target) {
    _target = target;
    final walletContext = ref.watch(
      walletViewModelProvider.select(_walletContext),
    );
    final generation = _ReceiveGeneration(
      target,
      ref.watch(walletRepositoryProvider.future),
      ref.watch(settingsRepositoryProvider.future),
      ref.watch(utcClockProvider),
      ref.read(walletViewModelProvider.future),
      walletContext.walletId,
    );
    _generation = generation;
    // Invalidate immediately on a selection transition, including the gap
    // before Riverpod rebuilds this provider. A late old-wallet request must
    // never become the next visible or copyable request.
    ref.listen(walletViewModelProvider, (_, next) {
      if (_walletContext(next) != walletContext) generation.active = false;
    });
    ref.onDispose(() => generation.active = false);
    return _load(generation, _rgbReceiveMode);
  }

  /// Retries initial route resolution and request generation.
  Future<void> retry() async {
    final generation = _generation;
    if (!_isCurrent(generation)) return;
    final failure = switch (state) {
      AsyncError(:final error, :final stackTrace) => FailureMapper.from(
        error,
        stackTrace,
      ),
      _ => null,
    };
    if (failure == null || !failure.retryable) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => _load(generation!, _rgbReceiveMode),
    );
    if (_isCurrent(generation)) state = next;
  }

  /// A user-requested genuine receive attempt after native capacity changed.
  /// This never prepares outputs, spends Bitcoin, or cancels a probe invoice.
  Future<void> retryRgbReceive() async {
    final generation = _generation;
    if (!_isCurrent(generation) ||
        _rgbReceiveMode != RgbReceiveMode.blind ||
        _setupCommandInFlight ||
        state.isLoading ||
        (state.value?.isBusy ?? false)) {
      return;
    }
    state = const AsyncLoading();
    final next = await AsyncValue.guard(
      () => _load(generation!, RgbReceiveMode.blind),
    );
    if (_isCurrent(generation)) state = next;
  }

  /// Updates pending amount-sheet input without regenerating on every key.
  void updateAmount(String value) {
    final current = _readyState;
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
    final current = _readyState;
    if (current == null || !current.canApplyAmount) return false;
    final units = current.amountText.isEmpty ? null : current.amountInput.units;
    return _generate(current, amountUnits: units, emitSuccessHaptic: true);
  }

  /// Generates a new address or invoice while preserving the applied amount.
  Future<bool> regenerate() async {
    final current = _readyState;
    if (current == null || !current.canRegenerate) return false;
    return _generate(
      current,
      amountUnits: current.request!.amount?.units,
      emitSuccessHaptic: true,
    );
  }

  /// Copies the currently encoded request through the app platform boundary.
  Future<AppResult<void>> copyRequest() async {
    final generation = _generation;
    if (!_isCurrent(generation)) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    final current = _readyState;
    if (current == null) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    final clipboard = ref.read(clipboardServiceProvider);
    final haptics = ref.read(hapticFeedbackServiceProvider);
    if (_requestReadFailure(current) case final failure?) {
      return AppResult.failure(failure);
    }
    state = AsyncData(
      current.copyWith(operation: ReceiveFlowOperation.copyingRequest),
    );
    final request = current.request!;
    final result = await clipboard.writeText(request.encodedRequest);
    if (!_isCurrent(generation)) return result;
    state = AsyncData(current.copyWith(operation: null));
    unawaited(
      haptics.trigger(
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
    final generation = _generation;
    if (!_isCurrent(generation)) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    final current = _readyState;
    if (current == null) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    final share = ref.read(shareServiceProvider);
    final haptics = ref.read(hapticFeedbackServiceProvider);
    if (_requestReadFailure(current) case final failure?) {
      return AppResult.failure(failure);
    }
    state = AsyncData(
      current.copyWith(operation: ReceiveFlowOperation.sharingRequest),
    );
    final request = current.request!;
    final result = await share.shareText(
      request.encodedRequest,
      subject: '${current.route.asset.displayName} payment request',
      origin: origin,
    );
    if (!_isCurrent(generation)) return result;
    state = AsyncData(current.copyWith(operation: null));
    if (result case AppFailureResult<ShareDisposition>()) {
      unawaited(haptics.trigger(HapticIntent.error));
    }
    return result;
  }

  Future<ReceiveFlowState> _load(
    _ReceiveGeneration generation,
    RgbReceiveMode mode,
  ) async {
    try {
      return await _loadUnsafe(generation, mode);
    } on _ReceiveGenerationChanged {
      rethrow;
    } catch (error, stackTrace) {
      throw AppFailureException(FailureMapper.from(error, stackTrace));
    }
  }

  Future<ReceiveFlowState> _loadUnsafe(
    _ReceiveGeneration generation,
    RgbReceiveMode mode,
  ) async {
    await _requireWalletContext(generation);
    final repository = await generation.repository;
    _requireCurrent(generation);
    final settings = await generation.settings;
    _requireCurrent(generation);
    final routeResult = repository.resolvePaymentTarget(generation.target);
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      throw AppFailureException(failure);
    }
    final route = (routeResult as AppSuccess<PaymentRoute>).value;
    final settingsResult = await settings.load();
    _requireCurrent(generation);
    if (settingsResult case AppFailureResult<SettingsSnapshot>(
      :final failure,
    )) {
      throw AppFailureException(failure);
    }
    final settingsSnapshot =
        (settingsResult as AppSuccess<SettingsSnapshot>).value;
    final bitcoinUnit = settingsSnapshot.preferences.bitcoinUnit;
    final WalletReceiveRequest? request;
    if (generation.target.requiresReceiveAmount) {
      request = null;
    } else {
      final requestResult = await repository.createReceiveRequest(
        generation.target,
        rgbReceiveMode: mode,
      );
      _requireCurrent(generation);
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
    final generation = _generation;
    if (!_isCurrent(generation)) return false;
    final haptics = ref.read(hapticFeedbackServiceProvider);
    final mode = _rgbReceiveMode;
    state = AsyncData(
      previous.copyWith(
        operation: ReceiveFlowOperation.generatingRequest,
        retainedFailure: null,
      ),
    );
    final result = await _walletOperation(
      (repository) => repository.createReceiveRequest(
        generation!.target,
        amountUnits: amountUnits,
        rgbReceiveMode: mode,
      ),
    );
    if (!_isCurrent(generation)) {
      return result is AppSuccess<WalletReceiveRequest>;
    }
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
          unawaited(haptics.trigger(HapticIntent.success));
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
        unawaited(haptics.trigger(HapticIntent.error));
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
    final generation = _generation;
    if (!_isCurrent(generation)) {
      return AppResult.failure(_operationUnavailableFailure());
    }
    try {
      await _requireWalletContext(generation!);
      final repository = await generation.repository;
      if (!_isCurrent(generation)) {
        return AppResult.failure(_operationUnavailableFailure());
      }
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
    if (current.isExpiredAt(_generation!.clock())) {
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
