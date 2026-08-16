import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/formatting/bitcoin_unit.dart';
import '../../data/repository/repository.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

part 'settings_view_model.g.dart';

/// Owns settings catalog loading and serialized preference mutations.
@riverpod
class SettingsViewModel extends _$SettingsViewModel {
  var _stateGeneration = 0;

  @override
  Future<SettingsState> build() async {
    _stateGeneration += 1;
    final repository = await ref.watch(settingsRepositoryProvider.future);
    return _load(repository);
  }

  /// Retries an initial catalog or preference failure.
  Future<void> retry() async {
    final failure = switch (state) {
      AsyncError(:final error, :final stackTrace) => FailureMapper.from(
        error,
        stackTrace,
      ),
      _ => null,
    };
    if (failure == null || !failure.retryable) return;
    final generation = ++_stateGeneration;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(() async {
      final repository = await ref.read(settingsRepositoryProvider.future);
      return _load(repository);
    });
    if (ref.mounted && generation == _stateGeneration) state = next;
  }

  Future<bool> selectCurrency(String code) => _mutate(
    SettingsOperation.currency,
    (repository) => repository.selectCurrency(code),
  );

  Future<bool> selectRegion(String code) => _mutate(
    SettingsOperation.region,
    (repository) => repository.selectRegion(code),
  );

  Future<bool> selectBitcoinUnit(BitcoinUnit unit) => _mutate(
    SettingsOperation.bitcoinUnit,
    (repository) => repository.selectBitcoinUnit(unit),
  );

  Future<bool> setBalancesVisible(bool visible) => _mutate(
    SettingsOperation.balanceVisibility,
    (repository) => repository.setBalancesVisible(visible),
  );

  /// Clears a rendered transient mutation failure after presentation.
  void clearOperationFailure() {
    final current = state.value;
    if (current == null || current.operationFailure == null) return;
    state = AsyncData(current.copyWith(operationFailure: null));
  }

  Future<SettingsState> _load(SettingsRepository repository) async {
    final result = await repository.load();
    return switch (result) {
      AppSuccess(:final value) => SettingsState(snapshot: value),
      AppFailureResult(:final failure) => throw AppFailureException(failure),
    };
  }

  Future<bool> _mutate(
    SettingsOperation operation,
    Future<AppResult<SettingsSnapshot>> Function(SettingsRepository) action,
  ) async {
    final current = state.value;
    if (current == null || current.isSaving) return false;
    final generation = _stateGeneration;
    state = AsyncData(
      current.copyWith(operation: operation, operationFailure: null),
    );
    final result = await _guardMutation(action);
    if (!ref.mounted || generation != _stateGeneration) return false;
    return switch (result) {
      AppSuccess(:final value) => _complete(value),
      AppFailureResult(:final failure) => _fail(current, failure),
    };
  }

  Future<AppResult<SettingsSnapshot>> _guardMutation(
    Future<AppResult<SettingsSnapshot>> Function(SettingsRepository) action,
  ) async {
    try {
      final repository = await ref.read(settingsRepositoryProvider.future);
      return await action(repository);
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  bool _complete(SettingsSnapshot snapshot) {
    state = AsyncData(SettingsState(snapshot: snapshot));
    return true;
  }

  bool _fail(SettingsState previous, AppFailure failure) {
    state = AsyncData(
      previous.copyWith(operation: null, operationFailure: failure),
    );
    return false;
  }
}
