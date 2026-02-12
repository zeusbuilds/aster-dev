import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../objectbox.g.dart';

/// Service for database operations using ObjectBox.
///
/// Manages the lifecycle of the underlying `Store` and provides typed boxes
/// for entities.
class DatabaseService {
  DatabaseService();

  Store? _store;
  String? _directory;

  /// Returns the ObjectBox [Store] instance.
  ///
  /// Throws a [StateError] if [init] has not been called yet.
  Store get store {
    if (_store == null) {
      throw StateError('Database not initialized. Call init() first.');
    }
    return _store!;
  }

  /// Returns a typed ObjectBox [Box] for the given entity type [T].
  Box<T> box<T>() {
    return store.box<T>();
  }

  /// Initializes the ObjectBox store and creates the backing directory if
  /// needed.
  ///
  /// Calling this method multiple times is safe; subsequent calls are no-ops.
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

  /// Closes the underlying ObjectBox store and releases resources.
  ///
  /// After calling this, [store] and [box] must not be used until [init] is
  /// called again.
  Future<void> close() async {
    _store?.close();
    _store = null;
  }
}
