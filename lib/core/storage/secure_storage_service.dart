import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for secure storage operations
abstract class SecureStorageService {
  /// Reads a value from secure storage
  ///
  /// [key] - The key to read the value for
  ///
  /// Returns the stored value if found, null otherwise
  Future<String?> read({required String key});

  /// Writes a value to secure storage
  ///
  /// [key] - The key to store the value under
  ///
  /// [value] - The value to store
  Future<void> write({required String key, required String value});

  /// Deletes a value from secure storage
  ///
  /// [key] - The key to delete
  Future<void> delete({required String key});

  /// Deletes all values from secure storage
  Future<void> deleteAll();

  /// Checks if a key exists in secure storage
  ///
  /// [key] - The key to check
  ///
  /// Returns true if the key exists, false otherwise
  Future<bool> containsKey({required String key});
}

/// Implementation of SecureStorageService using FlutterSecureStorage
class SecureStorageServiceImpl implements SecureStorageService {
  SecureStorageServiceImpl({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();

  @override
  Future<bool> containsKey({required String key}) =>
      _storage.containsKey(key: key);
}
