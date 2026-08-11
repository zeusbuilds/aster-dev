import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/wallet_viewmodel.dart';
import '../models/models.dart';

part 'create_wallet_view_model.g.dart';

/// Owns generated phrase display, bounded clipboard access, and provisioning.
@riverpod
class CreateWalletViewModel extends _$CreateWalletViewModel {
  late SensitiveClipboardService _clipboard;

  @override
  Future<CreateWalletState> build() async {
    _clipboard = ref.watch(sensitiveClipboardServiceProvider);
    ref.onDispose(() => unawaited(_clipboard.clearSensitive()));
    final result = await _generateMnemonic();
    return switch (result) {
      AppSuccess<String>(:final value) => CreateWalletState(
        words: value.split(' '),
      ),
      AppFailureResult<String>(:final failure) => throw AppFailureException(
        failure,
      ),
    };
  }

  /// Copies the phrase under a bounded matching-content clipboard lease.
  Future<AppResult<void>> copyMnemonic() async {
    final current = state.value;
    if (current == null || current.copying || !current.canSubmit) {
      return AppResult.failure(
        const AppFailure(
          code: 'clipboard_action_unavailable',
          kind: AppFailureKind.conflict,
          userMessage: 'The recovery phrase is not available to copy.',
          retryable: false,
        ),
      );
    }
    state = AsyncData(current.copyWith(copying: true));
    final result = await _clipboard.copySensitive(current.mnemonic);
    if (!ref.mounted) return result;
    state = AsyncData(current.copyWith(copying: false));
    final intent = result is AppSuccess<void>
        ? HapticIntent.lightImpact
        : HapticIntent.error;
    unawaited(ref.read(hapticFeedbackServiceProvider).trigger(intent));
    return result;
  }

  /// Provisions the displayed phrase and publishes only its committed registry.
  Future<bool> submit() async {
    final current = state.value;
    if (current == null || !current.canSubmit) return false;
    state = AsyncData(current.copyWith(submitting: true, failure: null));
    final result = await _createWallet(current.mnemonic);
    if (!ref.mounted) return result is AppSuccess<WalletRegistry>;
    return switch (result) {
      AppSuccess<WalletRegistry>(:final value) => _completeProvisioning(
        current,
        value,
      ),
      AppFailureResult<WalletRegistry>(:final failure) => () {
        state = AsyncData(
          current.copyWith(submitting: false, failure: failure),
        );
        unawaited(
          ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.error),
        );
        return false;
      }(),
    };
  }

  Future<bool> _completeProvisioning(
    CreateWalletState current,
    WalletRegistry registry,
  ) async {
    // The durable wallet commit must not retain the clipboard lease. A failed
    // clear remains leased and is retried by the clipboard service.
    await _clipboard.clearSensitive();
    if (!ref.mounted) return true;
    state = AsyncData(current.cleared());
    unawaited(
      ref.read(hapticFeedbackServiceProvider).trigger(HapticIntent.success),
    );
    ref.read(walletViewModelProvider.notifier).adoptCommittedRegistry(registry);
    return true;
  }

  Future<AppResult<String>> _generateMnemonic() async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return repository.generateMnemonic();
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  Future<AppResult<WalletRegistry>> _createWallet(String mnemonic) async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      return repository.createFromMnemonic(
        mnemonic: mnemonic,
        name: 'Primary Wallet',
      );
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }
}
