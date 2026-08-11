import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/onboarding/data/repository/repository.dart';
import '../../features/settings/data/repository/repository.dart';
import '../../features/wallet/data/repository/repository.dart';
import '../../features/wallet/data/runtime/runtime.dart';
import '../../features/wallet/data/storage/storage.dart';
import '../../features/wallet/data/validation/validation.dart';
import '../config/config.dart';
import '../network/network.dart';
import '../platform/platform.dart';
import '../storage/storage.dart';

part 'providers.g.dart';

@riverpod
AssetBundle appAssetBundle(Ref ref) => rootBundle;

@riverpod
Future<SharedPreferences> sharedPreferences(Ref ref) {
  return SharedPreferences.getInstance();
}

@riverpod
SecureKeyValueStore secureStorageService(Ref ref) {
  return SecureStorageService();
}

@riverpod
Future<PreferencesService> preferencesService(Ref ref) async {
  final preferences = await ref.watch(sharedPreferencesProvider.future);
  return PreferencesService(preferences);
}

@riverpod
Future<SettingsRepository> settingsRepository(Ref ref) async {
  final preferences = await ref.watch(preferencesServiceProvider.future);
  return SettingsRepository(preferences, ref.watch(appAssetBundleProvider));
}

@riverpod
Bip39WordListRepository bip39WordListRepository(Ref ref) {
  return Bip39WordListRepository(ref.watch(appAssetBundleProvider));
}

@Riverpod(keepAlive: true)
SensitiveClipboardService sensitiveClipboardService(Ref ref) {
  final service = PlatformSensitiveClipboardService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
}

@Riverpod(keepAlive: true)
ResilientHttpClient resilientHttpClient(Ref ref) {
  final client = ResilientHttpClient();
  ref.onDispose(client.close);
  return client;
}

@riverpod
WalletServiceConfiguration walletServiceConfiguration(Ref ref) {
  return WalletServiceConfiguration.fromEnvironment()..validate();
}

@riverpod
WalletEngineFactory walletEngineFactory(Ref ref) {
  return RgbWalletEngineFactory.withAddresses(
    ref.watch(bitcoinPaymentInstructionDecoderProvider),
  );
}

@riverpod
WalletKeyGenerator walletKeyGenerator(Ref ref) {
  return const RgbWalletKeyGenerator();
}

@riverpod
WalletIdentityGenerator walletIdentityGenerator(Ref ref) {
  return SecureWalletIdentityGenerator();
}

@riverpod
BitcoinPaymentInstructionDecoder bitcoinPaymentInstructionDecoder(Ref ref) {
  return const BitcoinPaymentInstructionParser();
}

@riverpod
WalletStorageSecurity walletStorageSecurity(Ref ref) {
  return const PlatformWalletStorageSecurity();
}

@riverpod
Future<WalletDirectoryManager> walletDirectoryManager(Ref ref) async {
  final support = await getApplicationSupportDirectory();
  return IoWalletDirectoryManager(
    '${support.path}${Platform.pathSeparator}utexo_wallets',
    ref.watch(walletStorageSecurityProvider),
  );
}

@riverpod
Future<WalletRegistryDocumentStore> walletRegistryDocumentStore(Ref ref) async {
  final support = await getApplicationSupportDirectory();
  return IoWalletRegistryDocumentStore(
    '${support.path}${Platform.pathSeparator}utexo_wallet_metadata',
    ref.watch(walletStorageSecurityProvider),
  );
}

@riverpod
Future<WalletProfilePersistence> walletProfileStore(Ref ref) async {
  final preferences = await ref.watch(preferencesServiceProvider.future);
  final documents = await ref.watch(walletRegistryDocumentStoreProvider.future);
  return WalletProfileStore(documents, preferences);
}

@riverpod
WalletSecretStore walletSecretStore(Ref ref) {
  return WalletSecretStore(ref.watch(secureStorageServiceProvider));
}

@riverpod
LegacyWalletSeedSource legacyWalletSeedSource(Ref ref) {
  return FlutterLegacyWalletSeedSource();
}

@riverpod
LegacyWalletSeedPreflight legacyWalletSeedPreflight(Ref ref) {
  return LegacyWalletSeedMigrationGuard(
    ref.watch(legacyWalletSeedSourceProvider),
  );
}

/// The only app-owned native wallet runtime.
///
/// Explicit app lifecycle disposal is the authoritative awaited cleanup path.
/// Provider teardown also starts best-effort cleanup because Riverpod dispose
/// callbacks are synchronous and cannot await native destruction.
@Riverpod(keepAlive: true)
Future<WalletRuntime> walletRuntime(Ref ref) async {
  final engineFactory = ref.watch(walletEngineFactoryProvider);
  final directories = ref.watch(walletDirectoryManagerProvider.future);
  final secrets = ref.watch(walletSecretStoreProvider);
  final services = ref.watch(walletServiceConfigurationProvider);
  final runtime = WalletRuntime(
    engineFactory,
    await directories,
    secrets,
    services,
  );
  ref.onDispose(() => unawaited(runtime.dispose()));
  return runtime;
}

@Riverpod(keepAlive: true)
Future<WalletRepository> walletRepository(Ref ref) async {
  final profiles = ref.watch(walletProfileStoreProvider.future);
  final runtime = ref.watch(walletRuntimeProvider.future);
  final keyGenerator = ref.watch(walletKeyGeneratorProvider);
  final identityGenerator = ref.watch(walletIdentityGeneratorProvider);
  final services = ref.watch(walletServiceConfigurationProvider);
  final legacySeedPreflight = ref.watch(legacyWalletSeedPreflightProvider);
  return WalletRepository(
    await profiles,
    await runtime,
    keyGenerator,
    identityGenerator,
    services,
    legacySeedPreflight,
    bitcoinInstructions: ref.watch(bitcoinPaymentInstructionDecoderProvider),
  );
}
