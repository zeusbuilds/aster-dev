import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/errors/errors.dart';

/// Narrow source for seed records written by the pre-SDK wallet architecture.
abstract interface class LegacyWalletSeedSource {
  Future<Set<String>> keys();
}

/// Reads the plugin's historical default namespace for migration detection.
final class FlutterLegacyWalletSeedSource implements LegacyWalletSeedSource {
  FlutterLegacyWalletSeedSource({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accountName: 'flutter_secure_storage_service',
              synchronizable: false,
            ),
            aOptions: AndroidOptions(
              resetOnError: false,
              migrateOnAlgorithmChange: true,
              migrateWithBackup: true,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<Set<String>> keys() async {
    try {
      // The plugin has no keys-only API. Values stay inside this short scope
      // and are never returned, logged, copied, or exposed to app state.
      final records = await _storage.readAll();
      return Set<String>.unmodifiable(records.keys);
    } catch (error, stackTrace) {
      throw StorageOperationException(
        'legacySecureReadAll',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// Detects seed records that require an explicit, ownership-safe migration.
abstract interface class LegacyWalletSeedPreflight {
  Future<AppResult<void>> verify();
}

/// Prevents the app from discarding wallets created by the legacy store.
///
/// The old store has no ownership token connecting its encrypted seed records
/// to a native RLN database. Until a deliberate migration verifies and adopts
/// that ownership, matching records are preserved and bootstrap fails closed.
final class LegacyWalletSeedMigrationGuard
    implements LegacyWalletSeedPreflight {
  const LegacyWalletSeedMigrationGuard(this._source);

  static final _legacySeedKey = RegExp(r'^wallet_seed_[a-fA-F0-9]{16}$');

  final LegacyWalletSeedSource _source;

  @override
  Future<AppResult<void>> verify() async {
    try {
      final keys = await _source.keys();
      if (keys.any(_legacySeedKey.hasMatch)) {
        return const AppResult.failure(
          AppFailure(
            code: 'wallet_recovery_required',
            kind: AppFailureKind.storage,
            userMessage:
                'A wallet from an earlier app version needs to be recovered '
                'before you can continue.',
            retryable: false,
          ),
        );
      }
      return const AppResult.success(null);
    } catch (error, stackTrace) {
      return AppResult.failure(
        FailureMapper.from(
          error,
          stackTrace,
          fallbackCode: 'legacy_wallet_seed_preflight_failed',
        ),
      );
    }
  }
}
