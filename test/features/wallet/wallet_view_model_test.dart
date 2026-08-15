import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/wallet_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/wallet_fakes.dart';

void main() {
  test('ignores reload while the initial wallet read is active', () async {
    final harness = await _createHarness(delayRepository: true);
    final subscription = harness.container.listen(
      walletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      await harness.dispose();
    });

    await harness.container.read(walletViewModelProvider.notifier).reload();
    await harness.container.read(walletViewModelProvider.future);

    expect(harness.documents.readCount, 1);
  });

  test('retryable initial wallet failure can recover explicitly', () async {
    final harness = await _createHarness(
      readError: TimeoutException('temporary registry timeout'),
    );
    final subscription = harness.container.listen(
      walletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      await harness.dispose();
    });

    await expectLater(
      harness.container.read(walletViewModelProvider.future),
      throwsA(isA<AppFailureException>()),
    );
    harness.documents.readError = null;

    await harness.container.read(walletViewModelProvider.notifier).reload();

    expect(
      harness.container.read(walletViewModelProvider),
      isA<AsyncData<WalletState>>(),
    );
    expect(harness.documents.readCount, 2);
  });

  test('terminal initial wallet failure cannot be reloaded', () async {
    final harness = await _createHarness(
      readError: StateError('terminal registry state'),
    );
    final subscription = harness.container.listen(
      walletViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      await harness.dispose();
    });

    await expectLater(
      harness.container.read(walletViewModelProvider.future),
      throwsA(isA<AppFailureException>()),
    );
    harness.documents.readError = null;

    await harness.container.read(walletViewModelProvider.notifier).reload();

    expect(
      harness.container.read(walletViewModelProvider),
      isA<AsyncError<WalletState>>(),
    );
    expect(harness.documents.readCount, 1);
  });
}

Future<_WalletViewModelHarness> _createHarness({
  Object? readError,
  bool delayRepository = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = PreferencesService(await SharedPreferences.getInstance());
  final documents = MemoryWalletRegistryDocumentStore()..readError = readError;
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
    retry: (retryCount, error) => null,
    overrides: [
      walletRepositoryProvider.overrideWith((ref) async {
        if (delayRepository) await Future<void>.delayed(Duration.zero);
        return repository;
      }),
    ],
  );
  return _WalletViewModelHarness(
    container: container,
    repository: repository,
    documents: documents,
  );
}

final class _WalletViewModelHarness {
  const _WalletViewModelHarness({
    required this.container,
    required this.repository,
    required this.documents,
  });

  final ProviderContainer container;
  final WalletRepository repository;
  final MemoryWalletRegistryDocumentStore documents;

  Future<void> dispose() async {
    container.dispose();
    await repository.dispose();
  }
}

const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
);
