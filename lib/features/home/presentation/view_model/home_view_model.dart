import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../models/models.dart';

part 'home_view_model.g.dart';

/// Owns the active wallet's cross-rail portfolio and explicit refresh state.
@riverpod
class HomeViewModel extends _$HomeViewModel {
  @override
  Future<HomeState> build() async {
    final wallet = await ref.watch(walletViewModelProvider.future);
    return _loadForActiveWallet(wallet.activeWallet);
  }

  Future<HomeState> _loadForActiveWallet(WalletProfile? activeWallet) async {
    if (activeWallet == null) {
      throw AppFailureException(_missingWalletFailure);
    }
    return _loadPortfolio();
  }

  /// Retries an initial portfolio failure without overlapping an active load.
  Future<void> retry() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    if (ref.read(walletViewModelProvider).hasError) {
      await ref.read(walletViewModelProvider.notifier).reload();
    }
    final next = await AsyncValue.guard(() async {
      final wallet = await ref.read(walletViewModelProvider.future);
      return _loadForActiveWallet(wallet.activeWallet);
    });
    if (ref.mounted) state = next;
  }

  /// Synchronizes the wallet and atomically replaces the displayed portfolio.
  /// Existing content remains visible while refresh is active or fails.
  Future<bool> refresh() async {
    final current = state.value;
    if (current == null || current.refreshing) return false;
    state = AsyncData(current.copyWith(refreshing: true, refreshFailure: null));
    final result = await _syncAndLoad();
    if (!ref.mounted) return result is AppSuccess<WalletPortfolio>;
    return switch (result) {
      AppSuccess<WalletPortfolio>(:final value) => () {
        state = AsyncData(HomeState(portfolio: value));
        return true;
      }(),
      AppFailureResult<WalletPortfolio>(:final failure) => () {
        state = AsyncData(
          current.copyWith(refreshing: false, refreshFailure: failure),
        );
        return false;
      }(),
    };
  }

  void clearRefreshFailure() {
    final current = state.value;
    if (current?.refreshFailure == null) return;
    state = AsyncData(current!.copyWith(refreshFailure: null));
  }

  Future<HomeState> _loadPortfolio() async {
    final result = await _portfolio();
    return switch (result) {
      AppSuccess<WalletPortfolio>(:final value) => HomeState(portfolio: value),
      AppFailureResult<WalletPortfolio>(:final failure) =>
        throw AppFailureException(failure),
    };
  }

  Future<AppResult<WalletPortfolio>> _portfolio() async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return repository.portfolio();
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  Future<AppResult<WalletPortfolio>> _syncAndLoad() async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      final sync = await repository.sync();
      if (sync case AppFailureResult<void>(:final failure)) {
        return AppResult.failure(failure);
      }
      return repository.portfolio();
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }
}

const _missingWalletFailure = AppFailure(
  code: 'wallet_active_missing',
  kind: AppFailureKind.configuration,
  userMessage: 'No active wallet is available.',
  retryable: false,
);
