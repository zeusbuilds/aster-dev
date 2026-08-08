import 'dart:convert';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/errors/errors.dart';
import '../../../../core/storage/secure_storage_service.dart';

/// Ephemeral credential material required to open one native wallet store.
///
/// Dart strings cannot be reliably zeroized. Callers must keep this object in
/// the narrowest possible async scope and must never cache, log, or expose it
/// to presentation state.
final class WalletSecret {
  const WalletSecret({
    required this.databasePassword,
    required this.mnemonic,
    required this.storageToken,
  });

  final String databasePassword;
  final String mnemonic;
  final String storageToken;
}

/// Stores one atomic, versioned credential record per opaque wallet ID.
final class WalletSecretStore {
  const WalletSecretStore(this._storage);

  final SecureKeyValueStore _storage;

  /// Returns wallet IDs with current ownership-bound credential records.
  Future<AppResult<Set<String>>> walletIds() async {
    try {
      final ids = <String>{};
      for (final key in await _storage.keys()) {
        if (key.startsWith(StorageKeys.legacyWalletSecretPrefix)) {
          throw const LegacyWalletDataException();
        }
        if (!key.startsWith(StorageKeys.walletSecretPrefix)) continue;
        final walletId = key.substring(StorageKeys.walletSecretPrefix.length);
        if (!_walletIdPattern.hasMatch(walletId)) {
          throw const StoredDataCorruptionException();
        }
        ids.add(walletId);
      }
      return AppResult.success(Set<String>.unmodifiable(ids));
    } catch (error, stackTrace) {
      return AppResult.failure(
        FailureMapper.from(
          error,
          stackTrace,
          fallbackCode: 'wallet_secret_inventory_failed',
        ),
      );
    }
  }

  Future<AppResult<void>> verify(
    String walletId, {
    required String expectedStorageToken,
  }) async {
    final result = await read(
      walletId,
      expectedStorageToken: expectedStorageToken,
    );
    return switch (result) {
      AppSuccess<WalletSecret>() => const AppResult.success(null),
      AppFailureResult<WalletSecret>(:final failure) => AppResult.failure(
        failure,
      ),
    };
  }

  Future<AppResult<void>> write(String walletId, WalletSecret secret) async {
    try {
      _validateWalletId(walletId);
      _validateSecret(secret);
      _validateStorageToken(secret.storageToken);
      if (await _storage.containsKey(key: _key(walletId)) ||
          await _storage.containsKey(key: _legacyKey(walletId))) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_secret_already_exists',
            kind: AppFailureKind.conflict,
            userMessage: 'Wallet credentials already exist on this device.',
            retryable: false,
          ),
        );
      }
      final encoded = jsonEncode({
        'version': 2,
        'databasePassword': secret.databasePassword,
        'mnemonic': secret.mnemonic,
        'storageToken': secret.storageToken,
      });
      if (utf8.encode(encoded).length > _maximumRecordBytes) {
        throw ArgumentError('Wallet credential record is too large.');
      }
      await _writeVerified(_key(walletId), encoded);
      return const AppResult.success(null);
    } catch (error, stackTrace) {
      return AppResult.failure(
        FailureMapper.from(
          error,
          stackTrace,
          fallbackCode: 'wallet_secret_write_failed',
        ),
      );
    }
  }

  Future<AppResult<WalletSecret>> read(
    String walletId, {
    required String expectedStorageToken,
  }) async {
    try {
      _validateWalletId(walletId);
      _validateStorageToken(expectedStorageToken);
      final current = await _storage.read(key: _key(walletId));
      if (current == null) {
        if (await _storage.containsKey(key: _legacyKey(walletId))) {
          throw const LegacyWalletDataException();
        }
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_secret_missing',
            kind: AppFailureKind.notFound,
            userMessage: 'Wallet credentials are missing from this device.',
            retryable: false,
          ),
        );
      }
      final secret = _decodeSecret(current);
      if (secret.storageToken != expectedStorageToken) {
        return AppResult.failure(_ownershipFailure());
      }
      return AppResult.success(secret);
    } catch (error, stackTrace) {
      return AppResult.failure(
        FailureMapper.from(
          error,
          stackTrace,
          fallbackCode: 'wallet_secret_read_failed',
        ),
      );
    }
  }

  Future<AppResult<void>> delete(
    String walletId, {
    required String storageToken,
  }) async {
    try {
      _validateWalletId(walletId);
      _validateStorageToken(storageToken);
      final encoded = await _storage.read(key: _key(walletId));
      if (encoded == null) {
        if (await _storage.containsKey(key: _legacyKey(walletId))) {
          return AppResult.failure(_ownershipFailure());
        }
        return const AppResult.success(null);
      }
      final secret = _decodeSecret(encoded);
      if (secret.storageToken != storageToken) {
        return AppResult.failure(_ownershipFailure());
      }
      await _deleteVerified(_key(walletId), encoded);
      return const AppResult.success(null);
    } catch (error, stackTrace) {
      return AppResult.failure(
        FailureMapper.from(
          error,
          stackTrace,
          fallbackCode: 'wallet_secret_delete_failed',
        ),
      );
    }
  }

  static String _key(String walletId) =>
      '${StorageKeys.walletSecretPrefix}$walletId';

  static String _legacyKey(String walletId) =>
      '${StorageKeys.legacyWalletSecretPrefix}$walletId';

  Future<void> _writeVerified(String key, String encoded) async {
    Object? writeError;
    StackTrace? writeStackTrace;
    try {
      await _storage.write(key: key, value: encoded);
    } catch (error, stackTrace) {
      writeError = error;
      writeStackTrace = stackTrace;
    }

    final String? stored;
    try {
      stored = await _storage.read(key: key);
    } catch (verificationError, verificationStackTrace) {
      throw DurableStorageCommitException([
        ?writeError,
        StorageOperationException(
          'walletSecretWriteVerification',
          cause: verificationError,
          stackTrace: verificationStackTrace,
        ),
      ]);
    }
    if (stored == encoded) return;
    if (writeError != null && stored == null) {
      Error.throwWithStackTrace(writeError, writeStackTrace!);
    }
    throw DurableStorageCommitException([
      ?writeError,
      const StoredDataCorruptionException(),
    ]);
  }

  Future<void> _deleteVerified(String key, String encoded) async {
    Object? deleteError;
    StackTrace? deleteStackTrace;
    try {
      await _storage.delete(key: key);
    } catch (error, stackTrace) {
      deleteError = error;
      deleteStackTrace = stackTrace;
    }

    final String? stored;
    try {
      stored = await _storage.read(key: key);
    } catch (verificationError, verificationStackTrace) {
      throw DurableStorageCommitException([
        ?deleteError,
        StorageOperationException(
          'walletSecretDeleteVerification',
          cause: verificationError,
          stackTrace: verificationStackTrace,
        ),
      ]);
    }
    if (stored == null) return;
    if (deleteError != null && stored == encoded) {
      Error.throwWithStackTrace(deleteError, deleteStackTrace!);
    }
    throw DurableStorageCommitException([
      ?deleteError,
      const StoredDataCorruptionException(),
    ]);
  }

  static void _validateWalletId(String walletId) {
    if (!_walletIdPattern.hasMatch(walletId)) {
      throw ArgumentError.value(walletId, 'walletId', 'Has an invalid shape.');
    }
  }

  static final _walletIdPattern = RegExp(r'^[a-f0-9]{32}$');
  static const _maximumRecordBytes = 4096;
  static const _maximumMnemonicBytes = 2048;
  static const _maximumPasswordBytes = 512;

  static void _validateStorageToken(String storageToken) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(storageToken)) {
      throw ArgumentError.value(
        storageToken,
        'storageToken',
        'Has an invalid shape.',
      );
    }
  }

  static void _validateSecret(WalletSecret secret) {
    if (secret.databasePassword.isEmpty ||
        utf8.encode(secret.databasePassword).length > _maximumPasswordBytes ||
        secret.mnemonic.isEmpty ||
        secret.mnemonic != secret.mnemonic.trim() ||
        utf8.encode(secret.mnemonic).length > _maximumMnemonicBytes) {
      throw ArgumentError('Wallet credentials have an invalid shape.');
    }
  }

  static WalletSecret _decodeSecret(String encoded) {
    if (utf8.encode(encoded).length > _maximumRecordBytes) {
      throw const StoredDataCorruptionException();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const StoredDataCorruptionException();
    }
    if (decoded is! Map<String, Object?> || decoded['version'] != 2) {
      throw const StoredDataCorruptionException();
    }
    final password = decoded['databasePassword'];
    final mnemonic = decoded['mnemonic'];
    final storageToken = decoded['storageToken'];
    if (password is! String ||
        mnemonic is! String ||
        storageToken is! String ||
        !_walletIdPattern.hasMatch(storageToken)) {
      throw const StoredDataCorruptionException();
    }
    final secret = WalletSecret(
      databasePassword: password,
      mnemonic: mnemonic,
      storageToken: storageToken,
    );
    try {
      _validateSecret(secret);
    } on ArgumentError {
      throw const StoredDataCorruptionException();
    }
    return secret;
  }

  static AppFailure _ownershipFailure() => const AppFailure(
    code: 'wallet_secret_ownership_unverified',
    kind: AppFailureKind.conflict,
    userMessage: 'Wallet credential ownership could not be verified.',
    retryable: false,
  );
}
