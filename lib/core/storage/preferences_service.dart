import 'package:shared_preferences/shared_preferences.dart';

/// Service for preferences storage operations backed by `SharedPreferences`.
class PreferencesService {
  PreferencesService(this._prefs);

  final SharedPreferences _prefs;

  /// Retrieves a string value for the given [key].
  ///
  /// Returns the string value if found, `null` otherwise.
  Future<String?> getString(String key) async => _prefs.getString(key);

  /// Stores a string [value] for the given [key].
  Future<void> setString(String key, String value) async =>
      await _prefs.setString(key, value);

  /// Retrieves a boolean value for the given [key].
  ///
  /// Returns the boolean value if found, `null` otherwise.
  Future<bool?> getBool(String key) async => _prefs.getBool(key);

  /// Stores a boolean [value] for the given [key].
  Future<void> setBool(String key, bool value) async =>
      await _prefs.setBool(key, value);

  /// Retrieves an integer value for the given [key].
  ///
  /// Returns the integer value if found, `null` otherwise.
  Future<int?> getInt(String key) async => _prefs.getInt(key);

  /// Stores an integer [value] for the given [key].
  Future<void> setInt(String key, int value) async =>
      await _prefs.setInt(key, value);

  /// Retrieves a double value for the given [key].
  ///
  /// Returns the double value if found, `null` otherwise.
  Future<double?> getDouble(String key) async => _prefs.getDouble(key);

  /// Stores a double [value] for the given [key].
  Future<void> setDouble(String key, double value) async =>
      await _prefs.setDouble(key, value);

  /// Retrieves a list of strings for the given [key].
  ///
  /// Returns the list if found, `null` otherwise.
  Future<List<String>?> getStringList(String key) async =>
      _prefs.getStringList(key);

  /// Stores a list of strings [value] for the given [key].
  Future<void> setStringList(String key, List<String> value) async =>
      await _prefs.setStringList(key, value);

  /// Removes the value associated with the given [key].
  Future<void> remove(String key) async => await _prefs.remove(key);

  /// Clears all stored preferences.
  Future<void> clear() async => await _prefs.clear();

  /// Returns `true` if the given [key] exists in preferences.
  Future<bool> containsKey(String key) async => _prefs.containsKey(key);
}
