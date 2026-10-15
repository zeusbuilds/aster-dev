import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../models/models.dart';

part 'activity_view_model.g.dart';

/// Owns one asset's real cross-rail activity and explicit refresh state.
@riverpod
class ActivityViewModel extends _$ActivityViewModel {
  var _stateGeneration = 0;

  @override
  Future<ActivityState> build(WalletAssetKind kind) async {
    _stateGeneration += 1;
    ref.watch(
      walletLifecycleViewModelProvider.select(
        (state) => state.foregroundGeneration,
      ),
    );
    final wallet = await ref.watch(walletViewModelProvider.future);
    if (wallet.activeWallet == null) {
      throw AppFailureException(_missingWalletFailure);
    }
    return _load(kind);
  }

  /// Retries initial loading without overlapping an active operation.
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
    if (ref.read(walletViewModelProvider).hasError) {
      await ref.read(walletViewModelProvider.notifier).reload();
    }
    final next = await AsyncValue.guard(() async {
      final wallet = await ref.read(walletViewModelProvider.future);
      if (wallet.activeWallet == null) {
        throw AppFailureException(_missingWalletFailure);
      }
      return _load(kind);
    });
    if (ref.mounted && generation == _stateGeneration) state = next;
  }

  /// Synchronizes native state, then atomically replaces the visible feed.
  Future<bool> refresh() async {
    final current = state.value;
    if (current == null || current.refreshing) return false;
    final generation = _stateGeneration;
    state = AsyncData(
      current.copyWith(refreshing: true, clearRefreshFailure: true),
    );
    final result = await _syncAndLoad(kind);
    if (!ref.mounted || generation != _stateGeneration) return false;
    return switch (result) {
      AppSuccess<WalletActivityFeed>(:final value) => () {
        state = AsyncData(ActivityState(feed: value));
        return true;
      }(),
      AppFailureResult<WalletActivityFeed>(:final failure) => () {
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
    state = AsyncData(current!.copyWith(clearRefreshFailure: true));
  }

  Future<ActivityState> _load(WalletAssetKind kind) async {
    final result = await _feed(kind);
    return switch (result) {
      AppSuccess<WalletActivityFeed>(:final value) => ActivityState(
        feed: value,
      ),
      AppFailureResult<WalletActivityFeed>(:final failure) =>
        throw AppFailureException(failure),
    };
  }

  Future<AppResult<WalletActivityFeed>> _feed(WalletAssetKind kind) async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return await repository.activityFeed(kind);
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  Future<AppResult<WalletActivityFeed>> _syncAndLoad(
    WalletAssetKind kind,
  ) async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      final sync = await repository.sync();
      if (sync case AppFailureResult<void>(:final failure)) {
        return AppResult.failure(failure);
      }
      // This explicit read-only check can resolve only an exact durable native
      // receipt. An unidentified submission remains visible and fenced.
      final reconciliation = await repository.reconcilePaymentSubmission();
      if (reconciliation case AppFailureResult<void>(:final failure)
          when failure.code != walletPaymentSubmissionPendingFailure.code) {
        return AppResult.failure(failure);
      }
      return await repository.activityFeed(kind);
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
