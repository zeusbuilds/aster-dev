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

/// Platform secure-storage adapter for Aster wallet credentials.
///
/// Secrets do not synchronize to another Apple device. Android records live in
/// one Aster-owned namespace and are never imported from an earlier app schema
/// or namespace. Corruption is surfaced instead of deleting data.
final class SecureStorageService implements SecureKeyValueStore {
  SecureStorageService({FlutterSecureStorage? storage, bool devBridge = false})
    : _storage =
          storage ??
          FlutterSecureStorage(
            iOptions: devBridge ? _devIosOptions : _iosOptions,
            aOptions: devBridge
                ? _androidOptions.copyWith(
                    storageNamespace: 'aster_devbridge_wallet_secrets',
                  )
                : _androidOptions,
          );

  static const _iosOptions = IOSOptions(
    accountName: 'com.aster.wallet.secrets',
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  static const _devIosOptions = IOSOptions(
    accountName: 'com.aster.wallet.devbridge.secrets',
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  static const _androidOptions = AndroidOptions(
    resetOnError: false,
    // Version 10.3.1 treats absent cipher markers as its historical
    // defaults, including in a fresh namespace. This initializes the
    // selected OAEP/GCM markers inside Aster's isolated namespace; it
    // does not import an earlier app-owned wallet contract.
    migrateOnAlgorithmChange: true,
    // The plugin's backup path still addresses compatibility data.
    // Aster has no released Android storage contract to recover.
    migrateWithBackup: false,
    keyCipherAlgorithm:
        KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    storageNamespace: 'aster_wallet_secrets',
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
