import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/wallet/data/repository/repository.dart';
import '../network/network_info.dart';
import '../storage/storage.dart';

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
  return NetworkInfo(ref.read(connectivityProvider));
}

// Storage providers
/// Provides SharedPreferences instance for persistent key-value storage
@riverpod
Future<SharedPreferences> sharedPreferences(Ref ref) async {
  return SharedPreferences.getInstance();
}

/// Provides SecureStorageService implementation for encrypted storage
@riverpod
SecureStorageService secureStorageService(Ref ref) {
  return SecureStorageService();
}

@riverpod
Future<PreferencesService> preferencesService(Ref ref) async {
  final preferences = await ref.watch(sharedPreferencesProvider.future);
  return PreferencesService(preferences);
}

// Wallet providers
/// Provides WalletRepository implementation for wallet operations
///
/// Wallet profiles contain display metadata only. Native wallet state and seed
/// material are owned by the SDK lifecycle layer.
@riverpod
Future<WalletRepository> walletRepository(Ref ref) async {
  final preferences = await ref.watch(preferencesServiceProvider.future);
  return WalletRepository(preferences);
}
