import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for secure storage operations
abstract class SecureStorageService {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
  Future<void> deleteAll();
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
