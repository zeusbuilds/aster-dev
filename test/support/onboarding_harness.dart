import 'dart:async';
import 'dart:math';

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/onboarding/data/repository/repository.dart';
import 'package:aster/features/onboarding/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'presentation_fakes.dart';
import 'wallet_fakes.dart';

const validTestMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';
const validTestMnemonicWords = <String>[
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'about',
];

/// Deterministic test-only wallet composition for onboarding behavior.
final class OnboardingTestHarness {
  OnboardingTestHarness._({
    required this.container,
    required this.repository,
    required this.clipboard,
    required this.engine,
    required this.engines,
    required this.keyGenerator,
    required this.preferences,
    required this.haptics,
    required this.toasts,
    required this.security,
    required this.readClipboard,
  });

  final ProviderContainer container;
  final WalletRepository repository;
  final PlatformSensitiveClipboardService clipboard;
  final FakeWalletEngine engine;
  final List<FakeWalletEngine> engines;
  final FakeWalletKeyGenerator keyGenerator;
  final SharedPreferences preferences;
  final RecordingHapticFeedbackService haptics;
  final RecordingToastPresentationService toasts;
  final SecurityController security;
  final String Function() readClipboard;
  var _disposed = false;

  String get clipboardText => readClipboard();

  static Future<OnboardingTestHarness> create({
    Object? generationError,
    Object? validationError,
    ResilientHttpClient? httpClient,
    AssetBundle? onboardingAssets,
    SecurityController? securityController,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    // Most onboarding cases intentionally exercise a device with no screen
    // credential. This is the approved bypass policy, not an absent plugin.
    final security =
        securityController ??
        SecurityController(const _UnsecuredDeviceAuthentication());
    if (!security.initialized) await security.initialize(hasWallet: false);
    final engines = List<FakeWalletEngine>.generate(
      3,
      (_) => FakeWalletEngine(),
      growable: false,
    );
    final engine = engines.first;
    const services = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
    );
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(engines),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      services,
    );
    final keyGenerator = FakeWalletKeyGenerator()
      ..generatedMnemonic = validTestMnemonic
      ..generationError = generationError
      ..validationError = validationError;
    final repository = WalletRepository(
      WalletProfileStore(MemoryWalletRegistryDocumentStore()),
      runtime,
      keyGenerator,
      SecureWalletIdentityGenerator(random: Random(7)),
      services,
    );
    const clipboard = PlatformSensitiveClipboardService();
    final haptics = RecordingHapticFeedbackService();
    final toasts = RecordingToastPresentationService();
    final container = ProviderContainer(
      retry: applicationProviderRetryPolicy,
      overrides: [
        securityControllerProvider.overrideWithValue(security),
        walletRepositoryProvider.overrideWith((ref) async => repository),
        walletServiceConfigurationProvider.overrideWithValue(services),
        bip39WordListRepositoryProvider.overrideWithValue(
          Bip39WordListRepository(onboardingAssets ?? rootBundle),
        ),
        recoveryQuizRandomProvider.overrideWithValue(Random(19)),
        sensitiveClipboardServiceProvider.overrideWithValue(clipboard),
        hapticFeedbackServiceProvider.overrideWithValue(haptics),
        if (httpClient != null)
          resilientHttpClientProvider.overrideWithValue(httpClient),
      ],
    );
    return OnboardingTestHarness._(
      container: container,
      repository: repository,
      clipboard: clipboard,
      engine: engine,
      engines: engines,
      keyGenerator: keyGenerator,
      preferences: preferences,
      haptics: haptics,
      toasts: toasts,
      security: security,
      readClipboard: () => '',
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    security.dispose();
    await clipboard.dispose();
    await repository.dispose();
  }
}

final class _UnsecuredDeviceAuthentication implements DeviceAuthentication {
  const _UnsecuredDeviceAuthentication();

  @override
  Future<DeviceSecurityStatus> status() async => DeviceSecurityStatus.unsecured;

  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) async =>
      throw StateError('An unsecured device must not show an auth prompt.');

  @override
  Future<void> cancel() async {}

  @override
  Future<void> setSensitive(bool sensitive) async {}

  @override
  Stream<bool> get captureChanges => const Stream<bool>.empty();

  @override
  bool get isCaptured => false;
}
