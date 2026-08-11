import 'package:aster/core/core.dart';
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

/// Real repository/runtime composition for payment ViewModel tests.
final class PaymentFlowTestHarness {
  PaymentFlowTestHarness._({
    required this.container,
    required this.repository,
    required this.engine,
    required this.haptics,
  });

  final ProviderContainer container;
  final WalletRepository repository;
  final FakeWalletEngine engine;
  final RecordingHapticFeedbackService haptics;
  var _disposed = false;

  static Future<PaymentFlowTestHarness> create({
    FakeWalletEngine? engine,
    WalletServiceConfiguration services = const WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
    ),
    Map<String, Object> preferenceValues = const {},
  }) async {
    SharedPreferences.setMockInitialValues(preferenceValues);
    final preferences = await SharedPreferences.getInstance();
    final preferenceService = PreferencesService(preferences);
    final selectedEngine = engine ?? FakeWalletEngine();
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([selectedEngine]),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    const walletId = '11111111111111111111111111111111';
    final provisioned = await runtime.provision(
      profile: WalletProfile(
        id: walletId,
        name: 'Active',
        createdAt: DateTime.utc(2026, 8, 11),
        updatedAt: DateTime.utc(2026, 8, 11),
        environment: services.environment,
        state: WalletProfileState.provisioning,
        storageToken: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      mnemonic: 'test mnemonic',
      databasePassword: 'test-password',
    );
    if (provisioned is! AppSuccess<void>) {
      throw StateError('Payment test wallet runtime did not provision.');
    }
    final repository = WalletRepository(
      WalletProfileStore(
        MemoryWalletRegistryDocumentStore(),
        preferenceService,
      ),
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: walletId),
      services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );
    final settings = SettingsRepository(preferenceService, rootBundle);
    final haptics = RecordingHapticFeedbackService();
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        walletRepositoryProvider.overrideWith((ref) async => repository),
        settingsRepositoryProvider.overrideWith((ref) async => settings),
        hapticFeedbackServiceProvider.overrideWithValue(haptics),
      ],
    );
    return PaymentFlowTestHarness._(
      container: container,
      repository: repository,
      engine: selectedEngine,
      haptics: haptics,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    await repository.dispose();
  }
}
