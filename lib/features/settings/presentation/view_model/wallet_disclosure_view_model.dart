import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../wallet/domain/models/models.dart';

final walletDisclosureViewModelProvider = Provider<WalletDisclosureViewModel>(
  WalletDisclosureViewModel.new,
);

/// Performs authorized disclosure reads and explicit platform actions.
///
/// Sensitive material is returned directly to the process-local handoff, never
/// retained as provider state. The caller owns route and wallet authority.
final class WalletDisclosureViewModel {
  WalletDisclosureViewModel(this._ref);

  final Ref _ref;

  Future<AppResult<String>> recoveryMnemonic({
    required String walletId,
    required SensitiveAuthorization authorization,
    required bool Function() current,
  }) => _guard(() async {
    if (!current()) return const AppResult.failure(_staleFailure);
    final repository = await _ref.read(walletRepositoryProvider.future);
    if (!current()) return const AppResult.failure(_staleFailure);
    return repository.recoveryMnemonic(walletId, authorization: authorization);
  });

  Future<AppResult<WalletPublicKeys>> publicKeys({
    required String walletId,
    required SensitiveAuthorization authorization,
    required bool Function() current,
  }) => _guard(() async {
    if (!current()) return const AppResult.failure(_staleFailure);
    final repository = await _ref.read(walletRepositoryProvider.future);
    if (!current()) return const AppResult.failure(_staleFailure);
    return repository.publicKeys(
      walletId: walletId,
      authorization: authorization,
    );
  });

  Future<AppResult<void>> copyPublicKeys(
    String text, {
    required bool Function() current,
  }) => _guard(() async {
    if (!current()) return const AppResult.failure(_staleFailure);
    return _ref.read(clipboardServiceProvider).writeText(text);
  });

  Future<AppResult<ShareDisposition>> sharePublicKeys(
    String text, {
    required ShareOrigin origin,
    required bool Function() current,
  }) => _guard(() async {
    if (!current()) return const AppResult.failure(_staleFailure);
    return _ref
        .read(shareServiceProvider)
        .shareText(text, subject: 'Aster extended public keys', origin: origin);
  });

  Future<AppResult<T>> _guard<T>(Future<AppResult<T>> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  static const _staleFailure = AppFailure(
    code: 'wallet_disclosure_context_changed',
    kind: AppFailureKind.unavailable,
    userMessage: 'Wallet access changed. Open the wallet information again.',
    retryable: true,
  );
}
