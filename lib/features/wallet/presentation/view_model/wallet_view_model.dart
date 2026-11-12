import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

part 'wallet_view_model.g.dart';

/// Loads wallet metadata and coordinates transactional wallet switching.
@Riverpod(keepAlive: true)
class WalletViewModel extends _$WalletViewModel {
  Future<AppResult<void>>? _deletionRecoveryInFlight;

  @override
  Future<WalletState> build() => _loadWallets();

  /// Reloads known state or retries an initial failure only when replay is safe.
  Future<void> reload() async {
    if (state.isLoading ||
        (!state.hasError && state.value?.isChangingWallet == true)) {
      return;
    }
    if (state case AsyncError(:final error, :final stackTrace)) {
      final failure = FailureMapper.from(error, stackTrace);
      if (canResumeDeletion(failure)) {
        await recoverCommittedDeletion(failure);
        return;
      }
      if (!failure.retryable) return;
    }
    state = const AsyncLoading();
    final next = await AsyncValue.guard(_loadWallets);
    if (ref.mounted) state = next;
  }

  /// These commands resume an already-authorized durable deletion. Retrying
  /// ordinary mutations with uncertain outcomes remains prohibited.
  static bool canResumeDeletion(AppFailure failure) =>
      WalletAccessRecovery.forFailure(failure)?.resumesDeletion == true;

  /// Finishes persisted deletion work or opens the surviving selection before
  /// publishing the registry. Foreground and route recovery share this command.
  Future<AppResult<void>> recoverCommittedDeletion(AppFailure failure) async {
    if (!canResumeDeletion(failure)) return AppResult.failure(failure);
    final inFlight = _deletionRecoveryInFlight;
    if (inFlight != null) return inFlight;
    if (state.isLoading ||
        (!state.hasError && state.value?.isChangingWallet == true)) {
      return AppResult.failure(failure);
    }

    final attempt = Future<AppResult<void>>.microtask(
      () => _recoverCommittedDeletion(failure),
    );
    _deletionRecoveryInFlight = attempt;
    state = const AsyncLoading();
    try {
      return await attempt;
    } finally {
      _deletionRecoveryInFlight = null;
    }
  }

  Future<AppResult<void>> _recoverCommittedDeletion(AppFailure previous) async {
    final next = await AsyncValue.guard(
      () => _loadWallets(resumeDeletion: true),
    );
    if (next case AsyncError(:final error, :final stackTrace)) {
      final failure = FailureMapper.from(error, stackTrace);
      // A transient read/open failure does not establish that the native wallet
      // is active. Keep the durable recovery command for the next attempt.
      final blocked = failure.retryable ? previous : failure;
      if (ref.mounted) {
        state = AsyncError(AppFailureException(blocked), stackTrace);
      }
      return AppResult.failure(blocked);
    }
    if (ref.mounted) state = next;
    return const AppResult.success(null);
  }

  /// Clears a transient switch failure after presentation consumes it.
  void clearOperationFailure() {
    final current = state.value;
    if (state.hasError || current == null || current.operationFailure == null) {
      return;
    }
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
    if (state.isLoading ||
        state.hasError ||
        current == null ||
        current.isChangingWallet ||
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
        if (failure.requiresReconciliation &&
            failure.code != walletPaymentSubmissionPendingFailure.code) {
          state = AsyncError(
            AppFailureException(failure),
            failure.stackTrace ?? StackTrace.current,
          );
          return false;
        }
        state = AsyncData(
          current.copyWith(switchingWalletId: null, operationFailure: failure),
        );
        return false;
      }(),
    };
  }

  /// Deletes only the wallet the user reviewed. The repository consumes the
  /// fresh device grant inside its serialized transaction, never in the UI.
  Future<bool> deleteWallet(
    String walletId, {
    SensitiveAuthorization? authorization,
  }) async {
    final current = state.value;
    if (state.isLoading ||
        state.hasError ||
        current == null ||
        current.isChangingWallet ||
        current.activeWallet?.id != walletId) {
      return false;
    }
    state = AsyncData(
      current.copyWith(deletingWalletId: walletId, operationFailure: null),
    );
    AppResult<WalletRegistry> result;
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      result = await repository.deleteWallet(
        walletId,
        authorization: authorization,
      );
    } catch (error, stackTrace) {
      result = AppResult.failure(FailureMapper.from(error, stackTrace));
    }
    if (!ref.mounted) return result is AppSuccess<WalletRegistry>;
    switch (result) {
      case AppSuccess<WalletRegistry>(:final value):
        if (value.profiles.isEmpty) {
          ref.read(securityControllerProvider).clearWalletPresence();
        }
        state = AsyncData(_toState(value));
        return true;
      case AppFailureResult<WalletRegistry>(:final failure):
        // Once destructive cleanup starts, the prior wallet must never be
        // restored optimistically. A reload resumes its durable deletion.
        if (failure.requiresReconciliation) {
          state = AsyncError(
            AppFailureException(failure),
            failure.stackTrace ?? StackTrace.current,
          );
        } else {
          state = AsyncData(
            current.copyWith(deletingWalletId: null, operationFailure: failure),
          );
        }
        return false;
    }
  }

  Future<AppResult<WalletRegistry>> _switchWallet(String walletId) async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return await repository.switchWallet(walletId);
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  Future<WalletState> _loadWallets({bool resumeDeletion = false}) async {
    final repository = await ref.read(walletRepositoryProvider.future);
    final result = resumeDeletion
        ? await repository.recoverWalletDeletion()
        : await repository.load();
    if (result case AppSuccess<WalletRegistry>(:final value)
        when ref.mounted && resumeDeletion && value.profiles.isEmpty) {
      ref.read(securityControllerProvider).clearWalletPresence();
    }
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
