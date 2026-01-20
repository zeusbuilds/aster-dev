import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../objectbox.g.dart';

/// Service for database operations using ObjectBox
abstract class DatabaseService {
  /// Get the ObjectBox Store instance
  Store get store;

  /// Initialize the database
  Future<void> init();

  /// Close the database
  Future<void> close();

  /// Get a box for a specific entity type
  Box<T> box<T>();
}

/// Implementation of DatabaseService using ObjectBox
class DatabaseServiceImpl implements DatabaseService {
  DatabaseServiceImpl();

  Store? _store;
  String? _directory;

  @override
  Store get store {
    if (_store == null) {
      throw StateError('Database not initialized. Call init() first.');
    }
    return _store!;
  }

  @override
  Box<T> box<T>() {
    return store.box<T>();
  }

  @override
  Future<void> init() async {
    if (_store != null) {
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    _directory = '${dir.path}/objectbox';

    // Ensure directory exists
    final directory = Directory(_directory!);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    _store = await openStore(directory: _directory!);
  }

  @override
  Future<void> close() async {
    _store?.close();
    _store = null;
  }
}
