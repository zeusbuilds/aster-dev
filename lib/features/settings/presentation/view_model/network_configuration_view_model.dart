import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../wallet/domain/models/models.dart';
import '../models/models.dart';

part 'network_configuration_view_model.g.dart';

/// Loads non-secret configuration and live native node status.
@riverpod
class NetworkConfigurationViewModel extends _$NetworkConfigurationViewModel {
  var _stateGeneration = 0;

  @override
  Future<NetworkConfigurationState> build() {
    _stateGeneration += 1;
    return _load();
  }

  /// Refreshes health while preserving the last confirmed status.
  Future<void> retryHealth() async {
    final current = state.value;
    if (current == null ||
        current.refreshing ||
        current.healthFailure?.retryable != true) {
      return;
    }
    final generation = _stateGeneration;
    state = AsyncData(current.copyWith(refreshing: true));
    final result = await _readNetworkStatus();
    if (!ref.mounted || generation != _stateGeneration) return;
    state = AsyncData(switch (result) {
      AppSuccess(:final value) => current.copyWith(
        status: value,
        healthFailure: null,
        refreshing: false,
      ),
      AppFailureResult(:final failure) => current.copyWith(
        healthFailure: failure,
        refreshing: false,
      ),
    });
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
