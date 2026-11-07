import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wallet_fakes.dart';

void main() {
  const services = WalletServiceConfiguration(
    backend: WalletBackend.rgbL1,
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
    indexerUrl: 'http://127.0.0.1:49794',
    rgbTransportProxy: 'rpc://127.0.0.1:49790/json-rpc',
  );
  const id = 'aabbccddaabbccddaabbccddaabbccdd';
  final profile = WalletProfile(
    id: id,
    name: 'Qualification',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    backend: WalletBackend.rgbL1,
    environment: BlockchainEnvironment.regtest,
    state: WalletProfileState.provisioning,
    storageToken: '00112233001122330011223300112233',
  );

  test('normal runtime stays closed before resources even with a real factory seam', () async {
    final directories = FakeWalletDirectoryManager();
    final secrets = MemorySecureStore();
    final factory = FakeWalletEngineFactory([]);
    final runtime = WalletRuntime(
      factory,
      directories,
      WalletSecretStore(secrets),
      services,
    );
    addTearDown(runtime.dispose);
    final result = await runtime.provision(
      profile: profile,
      mnemonic: 'private test phrase',
      databasePassword: 'private test password',
    );
    expect(
      (result as AppFailureResult<void>).failure.code,
      'wallet_backend_unqualified',
    );
    expect(directories.created, isEmpty);
    expect(factory.configurations, isEmpty);
    expect(secrets.values, isEmpty);
    expect(WalletBackend.rgbL1.activationAllowed, isFalse);
  });

  test(
    'Debug qualification retains ordinary ownership and lifecycle rules',
    () async {
      final parent = Directory.systemTemp.createTempSync('aster_l1_runtime_');
      addTearDown(() => parent.deleteSync(recursive: true));
      final root = '${parent.path}/aster_full_wallet_qa/run_001/native';
      final security = MemoryWalletStorageSecurity();
      final directories = IoWalletDirectoryManager(root, security);
      final engine = FakeWalletEngine();
      final factory = FakeWalletEngineFactory([engine]);
      final runtime = WalletRuntime.forQualification(
        factory,
        directories,
        WalletSecretStore(MemorySecureStore()),
        services,
      );
      addTearDown(runtime.dispose);
      expect(
        await runtime.provision(
          profile: profile,
          mnemonic: 'private test phrase',
          databasePassword: 'private test password',
        ),
        isA<AppSuccess<void>>(),
      );
      expect(factory.configurations.single.storageDirectory, '$root/$id');
      expect(
        factory.configurations.single.services.backend,
        WalletBackend.rgbL1,
      );
      expect(await runtime.suspend(), isA<AppSuccess<void>>());
      expect(await runtime.resume(), isA<AppSuccess<void>>());
      expect(engine.calls.where((call) => call == 'provision'), hasLength(1));
      expect(WalletBackend.rgbL1.activationAllowed, isFalse);
    },
  );

  test('qualification rejects public chains, Dev, legacy backend and ordinary storage', () {
    WalletRuntime build(WalletServiceConfiguration config, String root) =>
        WalletRuntime.forQualification(
          FakeWalletEngineFactory([]),
          IoWalletDirectoryManager(root, MemoryWalletStorageSecurity()),
          WalletSecretStore(MemorySecureStore()),
          config,
        );
    const validRoot = '/private/aster_full_wallet_qa/run_001/native';
    for (final config in [
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
      ),
      const WalletServiceConfiguration(
        backend: WalletBackend.rgbL1,
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        indexerUrl: 'https://unrelated-public-indexer.example.com',
        rgbTransportProxy: 'rpc://127.0.0.1:49790/json-rpc',
      ),
      const WalletServiceConfiguration(
        backend: WalletBackend.rgbL1,
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        indexerUrl: 'http://10.0.2.2:49794',
        rgbTransportProxy: 'rpc://127.0.0.1:49790/json-rpc',
      ),
      const WalletServiceConfiguration(
        backend: WalletBackend.rgbL1,
        environment: BlockchainEnvironment.mainnet,
        sdkNetwork: 'mainnet',
      ),
      const WalletServiceConfiguration(
        backend: WalletBackend.rgbL1,
        environment: BlockchainEnvironment.signet,
        sdkNetwork: 'signet',
      ),
      const WalletServiceConfiguration(
        backend: WalletBackend.rgbL1,
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        signetDeployment: SignetDeployment.utexoDev,
      ),
    ]) {
      expect(() => build(config, validRoot), throwsArgumentError);
    }
    for (final root in [
      '/private/ordinary-wallets',
      '/private/aster_full_wallet_qa/../native',
      '/private/../aster_full_wallet_qa/run_001/native',
      '/private/aster_full_wallet_qa/run_001/native/extra',
      'relative/aster_full_wallet_qa/run_001/native',
    ]) {
      expect(() => build(services, root), throwsArgumentError);
    }
  });
}
