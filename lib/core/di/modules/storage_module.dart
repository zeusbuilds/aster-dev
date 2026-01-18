import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../storage/secure_storage_service.dart';
import '../../storage/preferences_service.dart';
import '../../storage/database_service.dart';
import '../providers.dart';

/// Storage module for dependency injection
class StorageModule {
  static void setup(ProviderContainer container) {
    // Storage providers are already set up in providers.dart
    // This module can be extended for additional storage-related setup
  }

  /// Initializes database
  static Future<void> initDatabase(Ref ref) async {
    final databaseService = ref.read(databaseServiceProvider);
    await databaseService.init();
  }
}
