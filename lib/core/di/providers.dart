import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/onboarding/data/repository/repository.dart';
import '../../features/scan/data/services/services.dart';
import '../../features/scan/domain/models/models.dart';
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

/// Injectable UTC wall clock shared by app-owned time-sensitive operations.
typedef UtcClock = DateTime Function();

@Riverpod(keepAlive: true)
UtcClock utcClock(Ref ref) => _systemUtcNow;

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
AppMetadataService appMetadataService(Ref ref) {
  return PlatformAppMetadataService();
}

@riverpod
PublicLinkConfiguration publicLinkConfiguration(Ref ref) {
  return PublicLinkConfiguration.fromEnvironment()..validate();
}

@riverpod
SettingsAppRepository settingsAppRepository(Ref ref) {
  return SettingsAppRepository(
    ref.watch(appMetadataServiceProvider),
    ref.watch(externalUriServiceProvider),
  );
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

@riverpod
ClipboardService clipboardService(Ref ref) {
  return PlatformClipboardService();
}

@riverpod
ShareService shareService(Ref ref) {
  return PlatformShareService();
}

@riverpod
ExternalUriService externalUriService(Ref ref) {
  return PlatformExternalUriService();
}

/// Injectable factory for native camera/gallery scan sessions.
@Riverpod(keepAlive: true)
ScanSessionFactory scanSessionFactory(Ref ref) {
  return MobileScanSessionFactory();
}

/// One isolated native scan session for each presentation purpose.
@riverpod
ScanSession scanSession(Ref ref, ScanPurpose purpose) {
  final session = ref.watch(scanSessionFactoryProvider).create();
  ref.onDispose(() => unawaited(session.close()));
  return session;
}

@Riverpod(keepAlive: true)
ResilientHttpClient resilientHttpClient(Ref ref) {
  final client = ResilientHttpClient(clock: ref.watch(utcClockProvider));
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
    utcClock: ref.watch(utcClockProvider),
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
  return WalletProfileStore(
    documents,
    preferences,
    clock: ref.watch(utcClockProvider),
  );
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
    clock: ref.watch(utcClockProvider),
  );
}

DateTime _systemUtcNow() => DateTime.now().toUtc();
