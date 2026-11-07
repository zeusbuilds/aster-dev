import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wallet_fakes.dart';

final class _MnemonicEngine extends FakeWalletEngine
    implements WalletMnemonicOpenEngine {
  final openedMnemonics = <String>[];

  @override
  Future<void> openPersistedWithMnemonic({
    required String databasePassword,
    required String mnemonic,
  }) async {
    openedMnemonics.add(mnemonic);
    await super.openPersisted(databasePassword: databasePassword);
  }
}

void main() {
  const id = '11111111111111111111111111111111';
  const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const services = WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
  );
  final profile = WalletProfile(
    id: id,
    name: 'Fixture',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    environment: BlockchainEnvironment.regtest,
    state: WalletProfileState.ready,
    storageToken: token,
  );

  Future<({WalletRuntime runtime, MemorySecureStore storage})> fixture(
    _MnemonicEngine engine,
  ) async {
    final storage = MemorySecureStore();
    final secrets = WalletSecretStore(storage);
    await secrets.write(
      id,
      const WalletSecret(
        databasePassword: 'password-fixture',
        mnemonic: 'secure-record-mnemonic-fixture',
        storageToken: token,
      ),
    );
    final directories = FakeWalletDirectoryManager()..storageTokens[id] = token;
    final runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      directories,
      secrets,
      services,
    );
    addTearDown(runtime.dispose);
    expect(await runtime.restore(profile), isA<AppSuccess<void>>());
    return (runtime: runtime, storage: storage);
  }

  test(
    'RGB_L1 activation stays gated before directories, secrets or factory',
    () async {
      final storage = MemorySecureStore();
      final directories = FakeWalletDirectoryManager();
      final factory = FakeWalletEngineFactory([_MnemonicEngine()]);
      final runtime = WalletRuntime(
        factory,
        directories,
        WalletSecretStore(storage),
        const WalletServiceConfiguration(
          environment: BlockchainEnvironment.regtest,
          sdkNetwork: 'regtest',
          backend: WalletBackend.rgbL1,
        ),
      );
      addTearDown(runtime.dispose);
      final result = await runtime.provision(
        profile: WalletProfile(
          id: id,
          name: 'Fixture',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          environment: BlockchainEnvironment.regtest,
          backend: WalletBackend.rgbL1,
          state: WalletProfileState.provisioning,
          storageToken: token,
        ),
        mnemonic: 'must-not-be-persisted',
        databasePassword: 'password-fixture',
      );
      expect(
        result,
        isA<AppFailureResult<void>>().having(
          (failure) => failure.failure.code,
          'code',
          'wallet_backend_unqualified',
        ),
      );
      expect(storage.values, isEmpty);
      expect(directories.created, isEmpty);
      expect(factory.configurations, isEmpty);
    },
  );

  test('restore, lifecycle resume and drained-owner recovery each use secure material', () async {
    final engine = _MnemonicEngine();
    final (:runtime, :storage) = await fixture(engine);
    expect(engine.openedMnemonics, ['secure-record-mnemonic-fixture']);
    expect(engine.openedPassword, 'password-fixture');
    expect(engine.provisionedMnemonic, isNull);
    expect(await runtime.suspend(), isA<AppSuccess<void>>());
    expect(await runtime.resume(), isA<AppSuccess<void>>());
    engine.requiresPaymentReopen = true;
    expect(await runtime.run((_) async => 7), isA<AppSuccess<int>>());
    expect(
      engine.openedMnemonics,
      List.filled(3, 'secure-record-mnemonic-fixture'),
    );
    expect(engine.calls.where((call) => call == 'provision'), isEmpty);
    expect(storage.values, hasLength(1));
  });

  test(
    'quarantined native reader resume also receives the wallet-owned mnemonic',
    () async {
      final engine = _MnemonicEngine();
      final (:runtime, :storage) = await fixture(engine);
      await runtime.retainUnresolvedPayment();
      expect(await runtime.suspend(), isA<AppSuccess<void>>());
      expect(await runtime.resume(), isA<AppSuccess<void>>());
      expect(
        engine.openedMnemonics,
        List.filled(2, 'secure-record-mnemonic-fixture'),
      );
      expect(engine.paymentOperations.dispatchCount, 0);
      expect(storage.values, hasLength(1));
    },
  );

  test(
    'secure record failure stops reopen without reusing old signing material',
    () async {
      final engine = _MnemonicEngine();
      final (:runtime, :storage) = await fixture(engine);
      expect(await runtime.suspend(), isA<AppSuccess<void>>());
      storage.readError = StateError('secure record unavailable');
      expect(await runtime.resume(), isA<AppFailureResult<void>>());
      expect(engine.openedMnemonics, ['secure-record-mnemonic-fixture']);
      expect(
        engine.calls.where((call) => call == 'openPersisted'),
        hasLength(1),
      );
    },
  );
}
