import '../../../../core/core.dart';
import '../../../wallet/domain/models/models.dart';

/// One explicit Send action may review preparation, but never sends afterward.
enum RgbSendPreparationResult { ready, cancelled, prepared, pending, uncertain }

Future<RgbSendPreparationResult> prepareRgbSend({
  required WalletBackend backend,
  required WalletPaymentTarget target,
  required String walletId,
  required bool Function() isCurrent,
  required DateTime Function() clock,
  required Future<AppResult<RgbWalletSetupStatus>> Function() status,
  required Future<AppResult<RgbWalletSetupReview>> Function() review,
  required Future<AppResult<void>> Function(RgbWalletSetupReview) cancel,
  required Future<AppResult<RgbWalletSetupStatus>> Function(
    RgbWalletSetupReview,
  )
  prepare,
  required Future<bool> Function(RgbWalletSetupReview) confirm,
}) async {
  if (backend != WalletBackend.rgbL1 ||
      target != WalletPaymentTarget.usdtOnchain) {
    return RgbSendPreparationResult.ready;
  }
  void requireOwner() {
    if (!isCurrent()) {
      throw const AppFailureException(
        AppFailure(
          code: 'payment_wallet_changed',
          kind: AppFailureKind.conflict,
          userMessage:
              'Select the original wallet and review this payment again.',
          retryable: true,
        ),
      );
    }
  }

  T value<T>(AppResult<T> result) {
    if (result case AppSuccess<T>(:final value)) return value;
    final failure = (result as AppFailureResult<T>).failure;
    final message = switch (failure.code) {
      'rgb_wallet_setup_already_ready' =>
        'Wallet outputs are ready. Tap Send to review your payment again.',
      'rgb_wallet_setup_insufficient_bitcoin' => 'Add Bitcoin for wallet preparation and the network fee, then tap Send.',
      'rgb_wallet_setup_fee_stale' =>
        'The network fee is unavailable. Tap Send to check again.',
      'rgb_wallet_setup_review_changed' =>
        'This review changed. Tap Send to review preparation again.',
      _ => null,
    };
    // These pre-dispatch prerequisites may be checked again only by another
    // explicit Send. Unknown outcomes keep their original reconciliation fence.
    throw AppFailureException(
      message == null || failure.requiresReconciliation
          ? failure
          : AppFailure(
              code: failure.code,
              kind: failure.kind,
              userMessage: message,
              retryable: true,
              retryAfter: failure.retryAfter,
              cause: failure.cause,
              stackTrace: failure.stackTrace,
            ),
    );
  }

  RgbSendPreparationResult waiting(RgbWalletSetupStatus observed) =>
      observed.phase == RgbWalletSetupPhase.pending
      ? RgbSendPreparationResult.pending
      : RgbSendPreparationResult.uncertain;

  requireOwner();
  final observed = value(await status());
  requireOwner();
  if (observed.phase == RgbWalletSetupPhase.ready) {
    return RgbSendPreparationResult.ready;
  }
  if (observed.phase != RgbWalletSetupPhase.required) return waiting(observed);
  final approved = value(await review());
  requireOwner();
  void requireReview() {
    requireOwner();
    if (approved.walletId != walletId ||
        !clock().toUtc().isBefore(approved.expiresAt)) {
      throw const AppFailureException(
        AppFailure(
          code: 'rgb_wallet_setup_review_changed',
          kind: AppFailureKind.conflict,
          userMessage:
              'This review expired. Tap Send to review preparation again.',
          retryable: true,
        ),
      );
    }
  }

  requireReview();
  final accepted = await confirm(approved);
  requireOwner();
  if (!accepted) {
    value(await cancel(approved));
    return RgbSendPreparationResult.cancelled;
  }
  requireReview();
  final prepared = value(await prepare(approved));
  requireOwner();
  // Even immediate confirmation is not permission to send the user's asset.
  return prepared.phase == RgbWalletSetupPhase.ready
      ? RgbSendPreparationResult.prepared
      : waiting(prepared);
}
