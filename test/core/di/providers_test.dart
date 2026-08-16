import 'package:aster/core/core.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/scan_fakes.dart';
import '../../support/wallet_fakes.dart';

void main() {
  test('composition exposes one resolved and validated service object', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final configuration = container.read(walletServiceConfigurationProvider);

    expect(configuration.environment, BlockchainEnvironment.regtest);
    expect(configuration.sdkNetwork, 'regtest');
    expect(configuration.indexerUrl, 'http://127.0.0.1:3002');
    expect(
      configuration.rgbTransportProxy,
      'rpcs://proxy.iriswallet.com/0.2/json-rpc',
    );
  });

  test('wallet repository remains mounted across async composition', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async {
          await Future<void>.delayed(Duration.zero);
          return preferences;
        }),
        secureStorageServiceProvider.overrideWithValue(MemorySecureStore()),
        walletDirectoryManagerProvider.overrideWith((ref) async {
          await Future<void>.delayed(Duration.zero);
          return FakeWalletDirectoryManager();
        }),
        walletRegistryDocumentStoreProvider.overrideWith((ref) async {
          await Future<void>.delayed(Duration.zero);
          return MemoryWalletRegistryDocumentStore();
        }),
        walletEngineFactoryProvider.overrideWithValue(
          FakeWalletEngineFactory(const []),
        ),
        walletKeyGeneratorProvider.overrideWithValue(FakeWalletKeyGenerator()),
        walletIdentityGeneratorProvider.overrideWithValue(
          FakeWalletIdentityGenerator(
            walletId: '11111111111111111111111111111111',
          ),
        ),
        walletServiceConfigurationProvider.overrideWithValue(
          const WalletServiceConfiguration(
            environment: BlockchainEnvironment.regtest,
            sdkNetwork: 'regtest',
          ),
        ),
        legacyWalletSeedSourceProvider.overrideWithValue(
          MemoryLegacyWalletSeedSource(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final repository = await container.read(walletRepositoryProvider.future);
    final bootstrap = await repository.bootstrap();

    expect(bootstrap, isA<AppSuccess<Object?>>());
    expect(container.read(walletRepositoryProvider), isNotNull);
  });

  test(
    'scan-session disposal reports a redacted typed close failure',
    () async {
      final failure = AppFailure(
        code: 'scan_cleanup_failed',
        kind: AppFailureKind.unavailable,
        userMessage: 'The scanner could not be released cleanly.',
        retryable: false,
        stackTrace: StackTrace.current,
      );
      final session = FakeScanSession()
        ..closeResult = AppResult<void>.failure(failure);
      final reported = <FlutterErrorDetails>[];
      final previousHandler = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousHandler);
      final container = ProviderContainer(
        overrides: [
          scanSessionFactoryProvider.overrideWithValue(
            QueueScanSessionFactory([session]),
          ),
        ],
      );
      final subscription = container.listen(
        scanSessionProvider(ScanPurpose.destinationPicker),
        (_, _) {},
        fireImmediately: true,
      );

      expect(
        container.read(scanSessionProvider(ScanPurpose.destinationPicker)),
        same(session),
      );
      subscription.close();
      container.dispose();
      await pumpEventQueue();

      expect(session.closeCalls, 1);
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<AppFailureException>());
      expect(
        (reported.single.exception as AppFailureException).failure,
        same(failure),
      );
      expect(
        reported.single.exceptionAsString(),
        'AppFailureException(scan_cleanup_failed)',
      );
      expect(reported.single.library, 'UTEXO scan lifecycle');
    },
  );
}
