import 'package:chopper/chopper.dart';
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
@riverpod
Connectivity connectivity(ConnectivityRef ref) {
  return Connectivity();
}

@riverpod
NetworkInfo networkInfo(NetworkInfoRef ref) {
  return NetworkInfoImpl(ref.read(connectivityProvider));
}

@riverpod
ChopperClient chopperClient(ChopperClientRef ref) {
  return NetworkModule.getChopperClient(
    ref,
    enableLogging: false, // Set to true for debugging
  );
}

// Storage providers
@riverpod
Future<SharedPreferences> sharedPreferences(SharedPreferencesRef ref) async {
  return await SharedPreferences.getInstance();
}

@riverpod
SecureStorageService secureStorageService(SecureStorageServiceRef ref) {
  return SecureStorageServiceImpl();
}

@riverpod
PreferencesService preferencesService(PreferencesServiceRef ref) {
  final prefsAsync = ref.watch(sharedPreferencesProvider);
  return prefsAsync.when(
    data: (prefs) => PreferencesServiceImpl(prefs),
    loading: () => throw StateError('SharedPreferences not initialized'),
    error: (error, stack) =>
        throw StateError('Failed to initialize SharedPreferences: $error'),
  );
}

@riverpod
DatabaseService databaseService(DatabaseServiceRef ref) {
  return DatabaseServiceImpl();
}

// Wallet providers
@riverpod
WalletRepository walletRepository(WalletRepositoryRef ref) {
  return WalletRepositoryImpl(
    databaseService: ref.read(databaseServiceProvider),
    secureStorageService: ref.read(secureStorageServiceProvider),
    preferencesService: ref.read(preferencesServiceProvider),
  );
}
