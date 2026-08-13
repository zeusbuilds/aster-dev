import 'package:shared_preferences/shared_preferences.dart';

import '../errors/errors.dart';

/// Service for preferences storage operations backed by `SharedPreferences`.
class PreferencesService {
  PreferencesService(this._prefs);

  final SharedPreferences _prefs;

  /// Retrieves a string value for the given [key].
  ///
  /// Returns the string value if found, `null` otherwise.
  Future<String?> getString(String key) =>
      _read('getString', () => _prefs.getString(key));

  /// Stores a string [value] for the given [key].
  Future<void> setString(String key, String value) =>
      _write('setString', () => _prefs.setString(key, value));

  /// Retrieves a boolean value for the given [key].
  ///
  /// Returns the boolean value if found, `null` otherwise.
  Future<bool?> getBool(String key) =>
      _read('getBool', () => _prefs.getBool(key));

  /// Stores a boolean [value] for the given [key].
  Future<void> setBool(String key, bool value) =>
      _write('setBool', () => _prefs.setBool(key, value));

  /// Removes the value associated with the given [key].
  Future<void> remove(String key) => _write('remove', () => _prefs.remove(key));

  /// Returns `true` if the given [key] exists in preferences.
  Future<bool> containsKey(String key) =>
      _read('containsKey', () => _prefs.containsKey(key));

  static Future<T> _read<T>(String operation, T Function() action) async {
    try {
      return action();
    } catch (error, stackTrace) {
      throw StorageOperationException(
        operation,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> _write(
    String operation,
    Future<bool> Function() action,
  ) async {
    try {
      if (!await action()) throw StorageOperationException(operation);
    } on StorageOperationException {
      rethrow;
    } catch (error, stackTrace) {
      throw StorageOperationException(
        operation,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}
