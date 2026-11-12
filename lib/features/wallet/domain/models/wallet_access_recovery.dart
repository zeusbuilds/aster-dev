import '../../../../core/errors/errors.dart';

/// Recovery that a blocked wallet session can offer without replaying a mutation.
enum WalletAccessRecovery {
  retry,
  finishRemoval,
  openNextWallet;

  bool get resumesDeletion => this != retry;

  static WalletAccessRecovery? forFailure(AppFailure failure) =>
      switch (failure) {
        AppFailure(
          code: 'wallet_deletion_incomplete',
          requiresReconciliation: true,
        ) =>
          finishRemoval,
        AppFailure(
          code: 'wallet_deleted_activation_failed',
          requiresReconciliation: true,
        ) =>
          openNextWallet,
        AppFailure(retryable: true) => retry,
        _ => null,
      };
}
