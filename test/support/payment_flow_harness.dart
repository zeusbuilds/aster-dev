import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/market/presentation/view_model/view_models.dart';
import 'package:aster/features/settings/data/repository/repository.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'presentation_fakes.dart';
import 'wallet_fakes.dart';

/// Configured RGB route for invoice tests; no production asset identity.
const testRgbServices = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
  usdtAsset: RgbAssetConfiguration(
    contractId: 'rgb:configured-usdt',
    precision: 6,
    requiresEvmValidation: false,
  ),
);

PaymentRoute get testRgbRoute => PaymentRoute(
  asset: WalletAsset.rgbUsdt(assetId: 'rgb:configured-usdt', precision: 6),
  rail: PaymentRail.onchain,
);

WalletBalance testRgbBalance(int units) {
  final asset = testRgbRoute.asset;
  WalletAmount onchain(int value) =>
      WalletAmount.onchain(assetId: asset.id, units: value);
  final noLightning = WalletAmount.lightning(assetId: asset.id, units: 0);
  return WalletBalance(
    asset: asset,
    onchainSettled: onchain(units),
    onchainFuture: onchain(units),
    onchainSpendable: onchain(units),
    onchainLocked: onchain(0),
    lightningOwned: noLightning,
    lightningSpendable: noLightning,
    lightningReceivable: noLightning,
  );
}

/// Real repository/runtime composition for payment ViewModel tests.
final class PaymentFlowTestHarness {
  PaymentFlowTestHarness._({
    required this.container,
    required this.repository,
    required this.engine,
    required this.haptics,
    required this.toasts,
    required this.clipboard,
    required this.share,
    required this.externalUris,
  });

  final ProviderContainer container;
  final WalletRepository repository;
  final FakeWalletEngine engine;
  final RecordingHapticFeedbackService haptics;
  final RecordingToastPresentationService toasts;
  final MemoryClipboardService clipboard;
  final RecordingShareService share;
  final RecordingExternalUriService externalUris;
  var _disposed = false;

  static Future<PaymentFlowTestHarness> create({
    FakeWalletEngine? engine,
    WalletServiceConfiguration services = const WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
    ),
    WalletServiceConfiguration? presentationServices,
    RgbWalletSetupStore? rgbSetupStore,
    Map<String, Object> preferenceValues = const {},
    PreferencesService Function(SharedPreferences preferences)?
    preferenceServiceBuilder,
    ResilientHttpClient? httpClient,
    UtcClock? clock,
    AssetBundle? settingsAssets,
  }) async {
    SharedPreferences.setMockInitialValues(preferenceValues);
    final preferences = await SharedPreferences.getInstance();
    final preferenceService =
        preferenceServiceBuilder?.call(preferences) ??
        PreferencesService(preferences);
    final effectiveClock = clock ?? () => DateTime.now().toUtc();
    final selectedEngine = engine ?? FakeWalletEngine();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([selectedEngine]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    const walletId = '11111111111111111111111111111111';
    final profile = WalletProfile(
      id: walletId,
      name: 'Active',
      createdAt: DateTime.utc(2026, 8, 11),
      updatedAt: DateTime.utc(2026, 8, 11),
      environment: services.environment,
      signetDeployment: services.environment == BlockchainEnvironment.signet
          ? services.signetDeployment
          : null,
      state: WalletProfileState.provisioning,
      storageToken: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final provisioned = await runtime.provision(
      profile: profile,
      mnemonic: 'test mnemonic',
      databasePassword: 'test-password',
    );
    if (provisioned is! AppSuccess<void>) {
      throw StateError('Payment test wallet runtime did not provision.');
    }
    final profileStore = WalletProfileStore(
      MemoryWalletRegistryDocumentStore(),
      clock: effectiveClock,
    );
    final staged = await profileStore.stageProvision(profile);
    if (staged is! AppSuccess<WalletRegistry>) {
      throw StateError('Payment test wallet profile did not stage.');
    }
    final committed = await profileStore.commitProvision(walletId);
    if (committed is! AppSuccess<WalletRegistry>) {
      throw StateError('Payment test wallet profile did not commit.');
    }
    final repository = WalletRepository(
      profileStore,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      clock: effectiveClock,
      paymentJournalStore: MemoryWalletPaymentJournalStore(),
      rgbSetupStore: rgbSetupStore,
    );
    final settings = SettingsRepository(
      preferenceService,
      settingsAssets ?? PaymentSettingsAssetBundle(),
    );
    final haptics = RecordingHapticFeedbackService();
    final toasts = RecordingToastPresentationService();
    final clipboard = MemoryClipboardService();
    final share = RecordingShareService();
    final externalUris = RecordingExternalUriService();
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        walletRepositoryProvider.overrideWith((ref) async => repository),
        settingsRepositoryProvider.overrideWith((ref) async => settings),
        hapticFeedbackServiceProvider.overrideWithValue(haptics),
        clipboardServiceProvider.overrideWithValue(clipboard),
        shareServiceProvider.overrideWithValue(share),
        externalUriServiceProvider.overrideWithValue(externalUris),
        walletServiceConfigurationProvider.overrideWithValue(
          presentationServices ?? services,
        ),
        utcClockProvider.overrideWithValue(effectiveClock),
        bitcoinMarketBackgroundRetryPolicyProvider.overrideWithValue(null),
        if (httpClient != null)
          resilientHttpClientProvider.overrideWithValue(httpClient),
      ],
    );
    return PaymentFlowTestHarness._(
      container: container,
      repository: repository,
      engine: selectedEngine,
      haptics: haptics,
      toasts: toasts,
      clipboard: clipboard,
      share: share,
      externalUris: externalUris,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    await repository.dispose();
  }
}

/// Minimal validated settings catalog for payment-flow tests.
///
/// Keeping this bundle local to tests avoids coupling deterministic provider
/// initialization to Flutter's process-wide asset channel.
final class PaymentSettingsAssetBundle extends CachingAssetBundle {
  static const _sources = <String, String>{
    'assets/data/currencies.json':
        '[{"name":"United States Dollar","symbol":"\$",'
        '"code":"USD","countryCode":"US"}]',
    'assets/data/countries.json': '[{"name":"United States","code":"US"}]',
  };

  @override
  Future<ByteData> load(String key) async {
    final source = _sources[key];
    if (source == null) {
      throw StateError('Test asset not found: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
  }
}
