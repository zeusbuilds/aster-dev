import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../data/repository/repository.dart';
import '../../domain/models/wallet_access_recovery.dart';
import '../models/models.dart';
import 'wallet_view_model.dart';

part 'wallet_lifecycle_view_model.g.dart';

/// Exposes only the lifecycle subset of the process-owned wallet repository.
@Riverpod(keepAlive: true)
Future<WalletLifecycleRepository> walletLifecycleOperations(Ref ref) async {
  return await ref.watch(walletRepositoryProvider.future);
}

/// Serializes system lifecycle intent and keeps wallet UI hidden until native
/// state reaches a confirmed foreground result.
@Riverpod(keepAlive: true)
class WalletLifecycleViewModel extends _$WalletLifecycleViewModel {
  Future<void> _tail = Future<void>.value();
  var _revision = 0;

  @override
  WalletLifecycleState build() => const WalletLifecycleState();

  /// Applies one Flutter lifecycle event in arrival order.
  Future<bool> handle(AppLifecycleState lifecycle) {
    return _schedule(lifecycle);
  }

  /// Retries a failed foreground resume while retaining its failure surface.
  Future<bool> retry({AppFailure? accessFailure}) {
    final failure = state.recoveryFailure(accessFailure);
    if (state.obscured ||
        state.transitioning ||
        failure == null ||
        WalletAccessRecovery.forFailure(failure) == null) {
      return Future<bool>.value(false);
    }
    return _schedule(AppLifecycleState.resumed, retryFailure: failure);
  }

  Future<bool> _schedule(
    AppLifecycleState lifecycle, {
    AppFailure? retryFailure,
  }) {
    final userInitiated = retryFailure != null;
    final revision = ++_revision;
    state = WalletLifecycleState(
      obscured: !userInitiated,
      transitioning: lifecycle != AppLifecycleState.inactive,
      foregroundGeneration: state.foregroundGeneration,
      failure: retryFailure,
    );

    final completer = Completer<bool>();
    _tail = _tail.then((_) async {
      final result = await _apply(lifecycle, retryFailure);
      final succeeded = result is AppSuccess<void>;
      final current = ref.mounted && revision == _revision;
      if (current) {
        _publishResult(lifecycle, result);
        if (userInitiated) {
          unawaited(
            ref
                .read(hapticFeedbackServiceProvider)
                .trigger(succeeded ? HapticIntent.success : HapticIntent.error),
          );
        }
      }
      completer.complete(succeeded);
    });
    unawaited(_tail);
    return completer.future;
  }

  Future<AppResult<void>> _apply(
    AppLifecycleState lifecycle,
    AppFailure? retryFailure,
  ) async {
    if (lifecycle == AppLifecycleState.inactive) {
      return const AppResult.success(null);
    }
    try {
      if (retryFailure != null &&
          WalletViewModel.canResumeDeletion(retryFailure)) {
        return await ref
            .read(walletViewModelProvider.notifier)
            .recoverCommittedDeletion(retryFailure);
      }
      final repository = await ref.read(
        walletLifecycleOperationsProvider.future,
      );
      return switch (lifecycle) {
        AppLifecycleState.resumed => await repository.resume(),
        AppLifecycleState.hidden ||
        AppLifecycleState.paused => await repository.suspend(),
        AppLifecycleState.detached => await repository.dispose(),
        AppLifecycleState.inactive => const AppResult.success(null),
      };
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  void _publishResult(AppLifecycleState lifecycle, AppResult<void> result) {
    final generation = state.foregroundGeneration;
    switch (result) {
      case AppSuccess<void>():
        state = WalletLifecycleState(
          obscured: lifecycle != AppLifecycleState.resumed,
          foregroundGeneration: lifecycle == AppLifecycleState.resumed
              ? generation + 1
              : generation,
        );
      case AppFailureResult<void>(:final failure):
        state = WalletLifecycleState(
          obscured: lifecycle != AppLifecycleState.resumed,
          foregroundGeneration: generation,
          failure: failure,
        );
    }
  }
}
