import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for secure storage operations using `FlutterSecureStorage`.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Reads a value from secure storage for the given [key].
  ///
  /// Returns the stored value if found, `null` otherwise.
  Future<String?> read({required String key}) => _storage.read(key: key);

  /// Writes a [value] to secure storage under the given [key].
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  /// Deletes the value associated with the given [key] from secure storage.
  Future<void> delete({required String key}) => _storage.delete(key: key);

  /// Deletes all values from secure storage.
  Future<void> deleteAll() => _storage.deleteAll();

  /// Returns `true` if a value exists in secure storage for the given [key].
  Future<bool> containsKey({required String key}) =>
      _storage.containsKey(key: key);
}
