import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import 'settings_app_view_model.dart';
import 'settings_view_model.dart';

final settingsRecoveryViewModelProvider =
    NotifierProvider<SettingsRecoveryViewModel, AppFailure?>(
      SettingsRecoveryViewModel.new,
    );

/// Retries read-only Settings dependencies without presenting action feedback.
///
/// Visibility and backoff belong to the screen; failures remain typed for
/// diagnostics and never replace the defaults or become messages/toasts.
final class SettingsRecoveryViewModel extends Notifier<AppFailure?> {
  @override
  AppFailure? build() => null;

  Future<void> recover({
    required bool wallet,
    required bool preferences,
    required bool metadata,
  }) async {
    try {
      await Future.wait([
        if (wallet) ref.read(walletViewModelProvider.notifier).reload(),
        if (preferences) ref.read(settingsViewModelProvider.notifier).retry(),
        if (metadata) _retryMetadata(),
      ]);
      if (ref.mounted) state = null;
    } catch (error, stackTrace) {
      if (ref.mounted) state = FailureMapper.from(error, stackTrace);
    }
  }

  Future<void> _retryMetadata() async {
    final current = ref.read(settingsAppViewModelProvider).value;
    if (current == null) {
      ref.invalidate(settingsAppViewModelProvider);
      return;
    }
    await ref.read(settingsAppViewModelProvider.notifier).retryMetadata();
  }
}
