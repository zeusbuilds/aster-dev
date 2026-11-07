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
    switch (result) {
      case AppSuccess<WalletActivityFeed>(:final value):
        state = AsyncData(ActivityState(feed: value));
        return true;
      case AppFailureResult<WalletActivityFeed>(:final failure):
        var feed = current.feed;
        var refreshFailure = failure;
        // Status is local evidence and must not depend on a failed chain sync.
        try {
          final repository = await ref.read(walletRepositoryProvider.future);
          final submission = await repository.paymentSubmissionStatus();
          switch (submission) {
            case AppSuccess<WalletPaymentSubmission?>(:final value):
              feed = _withSubmission(feed, value);
            case AppFailureResult<WalletPaymentSubmission?>(:final failure):
              refreshFailure = failure;
          }
        } catch (error, stackTrace) {
          // Keep the loaded history readable, while retaining the authoritative
          // status-read failure and its captured diagnostic stack for this check.
          refreshFailure = FailureMapper.from(error, stackTrace);
        }
        if (!ref.mounted || generation != _stateGeneration) return false;
        state = AsyncData(
          current.copyWith(
            feed: feed,
            refreshing: false,
            refreshFailure: refreshFailure,
          ),
        );
        return false;
    }
  }

  void clearRefreshFailure() {
    final current = state.value;
    if (current?.refreshFailure == null) return;
    state = AsyncData(current!.copyWith(clearRefreshFailure: true));
  }

  /// Inspects the exact saved send independently of Esplora/proxy sync.
  /// This never submits a payment or retries Commit.
  Future<AppResult<WalletPaymentSubmission?>> checkPaymentStatus() async {
    final current = state.value;
    if (current == null || current.refreshing) {
      return const AppResult.failure(
        AppFailure(
          code: 'payment_status_busy',
          kind: AppFailureKind.conflict,
          userMessage: 'Please wait for the current check.',
          retryable: true,
        ),
      );
    }
    final generation = _stateGeneration;
    state = AsyncData(current.copyWith(refreshing: true));
    AppResult<WalletPaymentSubmission?> result;
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      final check = await repository.reconcilePaymentSubmission();
      result = await repository.paymentSubmissionStatus();
      if (result case AppSuccess<WalletPaymentSubmission?>(:final value)) {
        if (ref.mounted && generation == _stateGeneration) {
          state = AsyncData(
            current.copyWith(
              feed: _withSubmission(current.feed, value),
              refreshing: false,
            ),
          );
        }
        if (check case AppFailureResult<void>(:final failure)
            when !isWalletPaymentSubmissionFenceFailure(failure) &&
                value?.outcome != WalletPaymentSubmissionOutcome.accepted) {
          return AppResult.failure(failure);
        }
        return result;
      }
    } catch (error, stackTrace) {
      result = AppResult.failure(FailureMapper.from(error, stackTrace));
    }
    if (ref.mounted && generation == _stateGeneration) {
      state = AsyncData(current.copyWith(refreshing: false));
    }
    return result;
  }

  /// Details-only eligibility; this performs observations and never cancels.
  Future<AppResult<bool>> canRevokePayment(
    WalletPaymentSubmission expected,
  ) async {
    final current = state.value;
    if (current == null ||
        current.refreshing ||
        current.feed.paymentSubmission != expected) {
      return const AppResult.success(false);
    }
    final generation = _stateGeneration;
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      final result = await repository.canRevokePaymentSubmission(expected);
      return ref.mounted && generation == _stateGeneration
          ? result
          : const AppResult.success(false);
    } catch (error, stack) {
      return AppResult.failure(FailureMapper.from(error, stack));
    }
  }

  /// One user-confirmed revocation of this exact details entry. It shares the
  /// refresh lease so Check and repeated taps cannot overlap cancellation.
  Future<AppResult<WalletPaymentSubmission?>> revokePayment(
    WalletPaymentSubmission expected,
  ) async {
    final current = state.value;
    final lifecycle = ref.read(walletLifecycleViewModelProvider);
    if (current == null ||
        current.refreshing ||
        lifecycle.blocksInteraction ||
        current.feed.paymentSubmission != expected ||
        ref.read(walletViewModelProvider).value?.activeWallet?.id !=
            expected.walletId) {
      return const AppResult<WalletPaymentSubmission?>.failure(
        _paymentActionContextChanged,
      );
    }
    final generation = _stateGeneration;
    final foreground = lifecycle.foregroundGeneration;
    state = AsyncData(current.copyWith(refreshing: true));
    AppResult<WalletPaymentSubmission?> result;
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      final revoked = await repository.revokePaymentSubmission(expected);
      result = await repository.paymentSubmissionStatus();
      if (result case AppSuccess<WalletPaymentSubmission?>(:final value)) {
        if (value?.id != expected.id || value?.walletId != expected.walletId) {
          result = const AppResult<WalletPaymentSubmission?>.failure(
            _paymentActionContextChanged,
          );
        } else if (ref.mounted && generation == _stateGeneration) {
          state = AsyncData(
            current.copyWith(
              feed: _withSubmission(current.feed, value),
              refreshing: false,
            ),
          );
          if (revoked case AppFailureResult<void>(:final failure)
              when value?.outcome == WalletPaymentSubmissionOutcome.unknown) {
            result = AppResult<WalletPaymentSubmission?>.failure(failure);
          }
        }
      }
    } catch (error, stack) {
      result = AppResult.failure(FailureMapper.from(error, stack));
    }
    if (!ref.mounted || generation != _stateGeneration) {
      return const AppResult<WalletPaymentSubmission?>.failure(
        _paymentActionContextChanged,
      );
    }
    if (state.value?.refreshing == true) {
      state = AsyncData(current.copyWith(refreshing: false));
    }
    final now = ref.read(walletLifecycleViewModelProvider);
    if (now.blocksInteraction ||
        now.foregroundGeneration != foreground ||
        ref.read(walletViewModelProvider).value?.activeWallet?.id !=
            expected.walletId) {
      return const AppResult<WalletPaymentSubmission?>.failure(
        _paymentActionContextChanged,
      );
    }
    return result;
  }

  static WalletActivityFeed _withSubmission(
    WalletActivityFeed feed,
    WalletPaymentSubmission? submission,
  ) => WalletActivityFeed(
    balance: feed.balance,
    networkStatus: feed.networkStatus,
    activities: feed.activities,
    paymentSubmission: submission,
  );

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
      // This explicit check never sends. It may resolve an exact durable native
      // receipt or cancel a certified undispatched preparation. Legacy
      // unidentified submissions remain visible and fenced.
      final reconciliation = await repository.reconcilePaymentSubmission();
      if (reconciliation case AppFailureResult<void>(:final failure)
          when !isWalletPaymentSubmissionFenceFailure(failure)) {
        return AppResult.failure(failure);
      }
      final sync = await repository.sync();
      if (sync case AppFailureResult<void>(:final failure)) {
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

const _paymentActionContextChanged = AppFailure(
  code: 'payment_action_context_changed',
  kind: AppFailureKind.conflict,
  userMessage: 'Open this payment again to continue.',
  retryable: false,
);
