import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/wallet/data/repository/repository.dart';
import '../../features/wallet/presentation/view_model/wallet_view_model.dart';
import '../di/providers.dart';
import '../errors/errors.dart';

/// Production policy that keeps provider-build retry under app ownership.
///
/// Dependency changes may still rebuild providers. A failed build remains in
/// its typed error state until a ViewModel retry command or deliberate
/// invalidation runs; Riverpod never repeats it on a timer.
Duration? applicationProviderRetryPolicy(int _, Object _) => null;

/// Creates and fully bootstraps the application provider container.
///
/// [container] must use [applicationProviderRetryPolicy]. This function owns
/// the container on failure, attempts awaited native runtime cleanup before
/// disposing Riverpod, and never returns a partially initialized container.
Future<ProviderContainer> bootstrapApplicationContainer(
  ProviderContainer container,
) async {
  if (!identical(container.retry, applicationProviderRetryPolicy)) {
    container.dispose();
    throw ArgumentError(
      'Application bootstrap requires the explicit provider retry policy.',
    );
  }

  WalletRepository? repository;
  try {
    final resolvedRepository = await container.read(
      walletRepositoryProvider.future,
    );
    repository = resolvedRepository;
    final result = await resolvedRepository.bootstrap();
    if (result case AppFailureResult(:final failure)) {
      throw AppFailureException(failure);
    }
    // Preload the keep-alive wallet session before constructing GoRouter so
    // access guards never race startup or discard an incoming deep link.
    await container.read(walletViewModelProvider.future);
    return container;
  } catch (error, stackTrace) {
    final bootstrapFailure = FailureMapper.from(
      error,
      stackTrace,
      fallbackCode: 'app_bootstrap_failed',
    );
    final cleanup = repository == null
        ? await _disposePartiallyConstructedRuntime(container)
        : await repository.dispose();
    container.dispose();
    if (cleanup case AppFailureResult<void>(:final failure)) {
      throw AppFailureException(
        AppFailure(
          code: 'app_bootstrap_cleanup_failed',
          kind: AppFailureKind.storage,
          userMessage:
              'Wallet startup and cleanup did not complete safely. Restart '
              'the app before trying again.',
          retryable: false,
          requiresReconciliation: true,
          outcomeUnknown:
              bootstrapFailure.outcomeUnknown || failure.outcomeUnknown,
          cause: <AppFailure>[bootstrapFailure, failure],
          stackTrace: stackTrace,
        ),
      );
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

/// Creates the production Riverpod composition root.
ProviderContainer createApplicationProviderContainer(
  SharedPreferences sharedPreferences,
) {
  return ProviderContainer(
    retry: applicationProviderRetryPolicy,
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => sharedPreferences),
    ],
  );
}

/// Creates the production container with an already-resolved preferences
/// instance so startup never creates two competing preference owners.
Future<ProviderContainer> bootstrapApplication(
  SharedPreferences sharedPreferences,
) {
  return bootstrapApplicationContainer(
    createApplicationProviderContainer(sharedPreferences),
  );
}

Future<AppResult<void>> _disposePartiallyConstructedRuntime(
  ProviderContainer container,
) async {
  try {
    final runtime = await container.read(walletRuntimeProvider.future);
    return await runtime.dispose();
  } catch (_) {
    // WalletRuntime is assigned only after all of its dependencies resolve.
    // A provider construction failure before that point owns no native handle.
    return const AppResult.success(null);
  }
}
