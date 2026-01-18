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
@riverpod
Connectivity connectivity(Ref ref) {
  return Connectivity();
}

@riverpod
NetworkInfo networkInfo(Ref ref) {
  return NetworkInfoImpl(ref.read(connectivityProvider));
}

@riverpod
ChopperClient chopperClient(Ref ref) {
  return NetworkModule.getChopperClient(
    ref,
    enableLogging: false, // Set to true for debugging
  );
}

// Storage providers
@riverpod
Future<SharedPreferences> sharedPreferences(Ref ref) async {
  return await SharedPreferences.getInstance();
}

@riverpod
SecureStorageService secureStorageService(Ref ref) {
  return SecureStorageServiceImpl();
}

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

@riverpod
DatabaseService databaseService(Ref ref) {
  return DatabaseServiceImpl();
}

// Wallet providers
@riverpod
WalletRepository walletRepository(Ref ref) {
  return WalletRepositoryImpl(
    databaseService: ref.read(databaseServiceProvider),
    secureStorageService: ref.read(secureStorageServiceProvider),
    preferencesService: ref.read(preferencesServiceProvider),
  );
}
