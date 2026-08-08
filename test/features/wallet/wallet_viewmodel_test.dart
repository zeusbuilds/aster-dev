import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_viewmodel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/wallet_fakes.dart';

void main() {
  test('ignores reload while the initial wallet read is active', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
    );
    final documents = MemoryWalletRegistryDocumentStore();
    final profiles = WalletProfileStore(documents, preferences);
    final runtime = WalletRuntime(
      FakeWalletEngineFactory(const []),
      FakeWalletDirectoryManager(),
      WalletSecretStore(MemorySecureStore()),
      _services,
    );
    final repository = WalletRepository(
      profiles,
      runtime,
      FakeWalletKeyGenerator(),
      FakeWalletIdentityGenerator(walletId: '11111111111111111111111111111111'),
      _services,
      const SuccessfulLegacyWalletSeedPreflight(),
    );
    final container = ProviderContainer(
      overrides: [
        walletRepositoryProvider.overrideWith((ref) async {
          await Future<void>.delayed(Duration.zero);
          return repository;
        }),
      ],
    );
    final subscription = container.listen(
      walletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await repository.dispose();
    });

    await container.read(walletViewModelProvider.notifier).reload();
    await container.read(walletViewModelProvider.future);

    expect(documents.readCount, 1);
  });
}

const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
);
