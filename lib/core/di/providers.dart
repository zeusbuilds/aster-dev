import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../network/network_info.dart';
import '../storage/storage.dart';
import 'modules/network_module.dart';
import '../../features/wallet/data/repository/repository.dart';

part 'providers.g.dart';

/// Core dependency injection providers

// Network providers
/// Provides Connectivity instance for checking network status
@riverpod
Connectivity connectivity(Ref ref) {
  return Connectivity();
}

/// Provides NetworkInfo implementation for network connectivity checks
@riverpod
NetworkInfo networkInfo(Ref ref) {
  return NetworkInfoImpl(ref.read(connectivityProvider));
}

/// Provides ChopperClient configured with interceptors for API calls
///
/// Set [enableLogging] to true for debugging HTTP requests/responses
@riverpod
ChopperClient chopperClient(Ref ref) {
  return NetworkModule.getChopperClient(
    ref,
    enableLogging: false, // Set to true for debugging
  );
}

// Storage providers
/// Provides SharedPreferences instance for persistent key-value storage
@riverpod
Future<SharedPreferences> sharedPreferences(Ref ref) async {
  return await SharedPreferences.getInstance();
}

/// Provides SecureStorageService implementation for encrypted storage
@riverpod
SecureStorageService secureStorageService(Ref ref) {
  return SecureStorageServiceImpl();
}

/// Provides PreferencesService implementation for app preferences
///
/// Depends on [sharedPreferencesProvider] being initialized
@riverpod
PreferencesService preferencesService(Ref ref) {
  final prefsAsync = ref.watch(sharedPreferencesProvider);
  return prefsAsync.when(
    data: (prefs) => PreferencesServiceImpl(prefs),
    loading: () => throw StateError('SharedPreferences not initialized'),
    error: (error, stack) =>
        throw StateError('Failed to initialize SharedPreferences: $error'),
  );
}

/// Provides DatabaseService implementation using ObjectBox
@riverpod
DatabaseService databaseService(Ref ref) {
  return DatabaseServiceImpl();
}

// Wallet providers
/// Provides WalletRepository implementation for wallet operations
///
/// Depends on [databaseServiceProvider], [secureStorageServiceProvider],
///
/// and [preferencesServiceProvider]
@riverpod
WalletRepository walletRepository(Ref ref) {
  return WalletRepositoryImpl(
    databaseService: ref.read(databaseServiceProvider),
    secureStorageService: ref.read(secureStorageServiceProvider),
    preferencesService: ref.read(preferencesServiceProvider),
  );
}
