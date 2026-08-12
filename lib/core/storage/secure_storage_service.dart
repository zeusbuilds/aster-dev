import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../errors/errors.dart';

/// Minimal encrypted key-value contract used by wallet credential storage.
abstract interface class SecureKeyValueStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
  Future<bool> containsKey({required String key});
  Future<Set<String>> keys();
}

/// Platform secure-storage adapter with non-destructive wallet defaults.
///
/// Secrets do not synchronize or migrate to another Apple device. Android
/// corruption is surfaced instead of silently deleting all wallet secrets.
final class SecureStorageService implements SecureKeyValueStore {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accountName: 'com.utexo.wallet.secrets.v1',
              accessibility: KeychainAccessibility.unlocked_this_device,
              synchronizable: false,
            ),
            aOptions: AndroidOptions(
              resetOnError: false,
              // Pin the cryptographic contract instead of inheriting mutable
              // plugin defaults. Version 10.3.1 treats absent first-install
              // markers as legacy, so crash-safe migration must stay enabled.
              migrateOnAlgorithmChange: true,
              migrateWithBackup: true,
              keyCipherAlgorithm:
                  KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
              storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
              storageNamespace: 'utexo_wallet_secrets_v1',
            ),
          );

  final FlutterSecureStorage _storage;

  /// Reads a value from secure storage for the given [key].
  ///
  /// Returns the stored value if found, `null` otherwise.
  @override
  Future<String?> read({required String key}) =>
      _perform('secureRead', () => _storage.read(key: key));

  /// Writes a [value] to secure storage under the given [key].
  @override
  Future<void> write({required String key, required String value}) =>
      _perform('secureWrite', () => _storage.write(key: key, value: value));

  /// Deletes the value associated with the given [key] from secure storage.
  @override
  Future<void> delete({required String key}) =>
      _perform('secureDelete', () => _storage.delete(key: key));

  /// Returns `true` if a value exists in secure storage for the given [key].
  @override
  Future<bool> containsKey({required String key}) =>
      _perform('secureContainsKey', () => _storage.containsKey(key: key));

  /// Returns only keys from the dedicated wallet-secret namespace.
  ///
  /// The plugin exposes this through `readAll`, so values exist only in the
  /// adapter's short native-call scope and are never returned to callers.
  @override
  Future<Set<String>> keys() => _perform('secureKeys', () async {
    final records = await _storage.readAll();
    return Set<String>.unmodifiable(records.keys);
  });

  static Future<T> _perform<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      throw StorageOperationException(
        operation,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}
