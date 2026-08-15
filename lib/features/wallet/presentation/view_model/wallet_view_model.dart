import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

part 'wallet_view_model.g.dart';

/// Loads wallet metadata and coordinates transactional wallet switching.
@Riverpod(keepAlive: true)
class WalletViewModel extends _$WalletViewModel {
  @override
  Future<WalletState> build() => _loadWallets();

  /// Reloads known state or retries an initial failure only when replay is safe.
  Future<void> reload() async {
    if (state.isLoading || state.value?.switchingWalletId != null) return;
    if (state case AsyncError(:final error, :final stackTrace)
        when !FailureMapper.from(error, stackTrace).retryable) {
      return;
    }
    state = const AsyncLoading();
    final next = await AsyncValue.guard(_loadWallets);
    if (ref.mounted) state = next;
  }

  /// Clears a transient switch failure after presentation consumes it.
  void clearOperationFailure() {
    final current = state.value;
    if (current == null || current.operationFailure == null) return;
    state = AsyncData(current.copyWith(operationFailure: null));
  }

  /// Publishes the exact registry returned by a successful repository commit.
  /// This avoids a second read and prevents onboarding from navigating on an
  /// optimistic or independently reconstructed wallet state.
  void adoptCommittedRegistry(WalletRegistry registry) {
    final active = registry.activeProfile;
    if (active == null) {
      throw ArgumentError.value(
        registry,
        'registry',
        'A committed onboarding registry must have an active wallet.',
      );
    }
    state = AsyncData(_toState(registry));
  }

  /// Returns true only after the native runtime and persisted selection both
  /// commit successfully.
  Future<bool> switchWallet(String walletId) async {
    final current = state.value;
    if (current == null ||
        current.switchingWalletId != null ||
        current.activeWallet?.id == walletId) {
      return false;
    }
    state = AsyncData(
      current.copyWith(switchingWalletId: walletId, operationFailure: null),
    );
    final result = await _switchWallet(walletId);
    if (!ref.mounted) return result is AppSuccess<WalletRegistry>;
    return switch (result) {
      AppSuccess<WalletRegistry>(:final value) => () {
        state = AsyncData(_toState(value));
        return true;
      }(),
      AppFailureResult<WalletRegistry>(:final failure) => () {
        state = AsyncData(
          current.copyWith(switchingWalletId: null, operationFailure: failure),
        );
        return false;
      }(),
    };
  }

  Future<AppResult<WalletRegistry>> _switchWallet(String walletId) async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return await repository.switchWallet(walletId);
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  Future<WalletState> _loadWallets() async {
    final repository = await ref.read(walletRepositoryProvider.future);
    final result = await repository.load();
    return switch (result) {
      AppSuccess<WalletRegistry>(:final value) => _toState(value),
      AppFailureResult<WalletRegistry>(:final failure) =>
        throw AppFailureException(failure),
    };
  }

  static WalletState _toState(WalletRegistry registry) {
    return WalletState(
      wallets: registry.readyProfiles,
      activeWallet: registry.activeProfile,
    );
  }
}
