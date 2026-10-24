import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../models/models.dart';

part 'network_configuration_view_model.g.dart';

/// Loads non-secret configuration and live native node status.
@riverpod
class NetworkConfigurationViewModel extends _$NetworkConfigurationViewModel {
  var _stateGeneration = 0;

  @override
  Future<NetworkConfigurationState> build() {
    _stateGeneration += 1;
    ref.watch(
      walletLifecycleViewModelProvider.select(
        (state) => state.foregroundGeneration,
      ),
    );
    return _load();
  }

  /// Refreshes health and discards a previous status if the check fails.
  Future<bool> refreshHealth() async {
    final current = state.value;
    if (current == null ||
        current.refreshing ||
        current.healthFailure?.retryable == false) {
      return false;
    }
    final generation = _stateGeneration;
    final toasts = ref.read(toastControllerProvider.notifier).captureOrigin();
    state = AsyncData(current.copyWith(refreshing: true));
    final result = await _readNetworkStatus();
    if (!ref.mounted || generation != _stateGeneration) return false;
    state = AsyncData(switch (result) {
      AppSuccess(:final value) => current.copyWith(
        status: value,
        healthFailure: null,
        refreshing: false,
      ),
      AppFailureResult(:final failure) => current.copyWith(
        status: null,
        healthFailure: failure,
        refreshing: false,
      ),
    });
    final succeeded = result is AppSuccess<WalletNetworkStatus>;
    if (!succeeded) {
      toasts.show(title: 'Health check failed', variant: ToastVariant.failure);
    }
    unawaited(
      ref
          .read(hapticFeedbackServiceProvider)
          .trigger(succeeded ? HapticIntent.success : HapticIntent.error),
    );
    return succeeded;
  }

  Future<NetworkConfigurationState> _load() async {
    final configuration = ref.watch(walletServiceConfigurationProvider);
    final repository = await ref.watch(walletRepositoryProvider.future);
    final result = await repository.networkStatus();
    return switch (result) {
      AppSuccess(:final value) => NetworkConfigurationState(
        configuration: configuration,
        status: value,
      ),
      AppFailureResult(:final failure) => NetworkConfigurationState(
        configuration: configuration,
        healthFailure: failure,
      ),
    };
  }

  Future<AppResult<WalletNetworkStatus>> _readNetworkStatus() async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return await repository.networkStatus();
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }
}
