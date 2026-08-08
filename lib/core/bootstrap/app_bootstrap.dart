import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/wallet/data/repository/repository.dart';
import '../di/providers.dart';
import '../errors/errors.dart';

/// Creates and fully bootstraps the application provider container.
///
/// This function owns [container] on failure. It attempts awaited native
/// runtime cleanup before disposing Riverpod and never returns a partially
/// initialized container.
Future<ProviderContainer> bootstrapApplicationContainer(
  ProviderContainer container,
) async {
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

/// Creates the production container with an already-resolved preferences
/// instance so startup never creates two competing preference owners.
Future<ProviderContainer> bootstrapApplication(
  SharedPreferences sharedPreferences,
) {
  return bootstrapApplicationContainer(
    ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => sharedPreferences),
      ],
    ),
  );
}

Future<AppResult<void>> _disposePartiallyConstructedRuntime(
  ProviderContainer container,
) async {
  try {
    final runtime = await container.read(walletRuntimeProvider.future);
    return runtime.dispose();
  } catch (_) {
    // WalletRuntime is assigned only after all of its dependencies resolve.
    // A provider construction failure before that point owns no native handle.
    return const AppResult.success(null);
  }
}
