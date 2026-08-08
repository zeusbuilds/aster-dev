import 'package:aster/core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/wallet_fakes.dart';

void main() {
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
}
