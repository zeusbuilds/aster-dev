import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

part 'wallet_viewmodel.g.dart';

/// Loads wallet metadata and coordinates transactional wallet switching.
@riverpod
class WalletViewModel extends _$WalletViewModel {
  @override
  Future<WalletState> build() => _loadWallets();

  Future<void> reload() async {
    if (state.isLoading || state.value?.switchingWalletId != null) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(_loadWallets);
    if (ref.mounted) state = next;
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
      return repository.switchWallet(walletId);
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
