import 'package:shared_preferences/shared_preferences.dart';

/// Service for preferences storage operations
abstract class PreferencesService {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);
  Future<int?> getInt(String key);
  Future<void> setInt(String key, int value);
  Future<double?> getDouble(String key);
  Future<void> setDouble(String key, double value);
  Future<List<String>?> getStringList(String key);
  Future<void> setStringList(String key, List<String> value);
  Future<void> remove(String key);
  Future<void> clear();
  Future<bool> containsKey(String key);
}

/// Implementation of PreferencesService using SharedPreferences
class PreferencesServiceImpl implements PreferencesService {
  PreferencesServiceImpl(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> getString(String key) async => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) async =>
      await _prefs.setString(key, value);

  @override
  Future<bool?> getBool(String key) async => _prefs.getBool(key);

  @override
  Future<void> setBool(String key, bool value) async =>
      await _prefs.setBool(key, value);

  @override
  Future<int?> getInt(String key) async => _prefs.getInt(key);

  @override
  Future<void> setInt(String key, int value) async =>
      await _prefs.setInt(key, value);

  @override
  Future<double?> getDouble(String key) async => _prefs.getDouble(key);

  @override
  Future<void> setDouble(String key, double value) async =>
      await _prefs.setDouble(key, value);

  @override
  Future<List<String>?> getStringList(String key) async =>
      _prefs.getStringList(key);

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      await _prefs.setStringList(key, value);

  @override
  Future<void> remove(String key) async => await _prefs.remove(key);

  @override
  Future<void> clear() async => await _prefs.clear();

  @override
  Future<bool> containsKey(String key) async => _prefs.containsKey(key);
}

