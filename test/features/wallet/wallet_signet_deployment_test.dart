import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wallet_fakes.dart';

const _id = '11111111111111111111111111111111';
const _otherId = '22222222222222222222222222222222';
const _token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _otherToken = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _public = WalletServiceConfiguration(
  environment: BlockchainEnvironment.signet,
  sdkNetwork: 'utexo',
  indexerUrl: 'https://mempool.space/signet/api',
  rgbTransportProxy: 'rpcs://proxy.iriswallet.com/0.2/json-rpc',
);

WalletProfile _profile({
  String id = _id,
  String token = _token,
  SignetDeployment? deployment,
  WalletProfileState state = WalletProfileState.provisioning,
}) => WalletProfile(
  id: id,
  name: 'Wallet',
  createdAt: DateTime.utc(2026, 11, 7),
  updatedAt: DateTime.utc(2026, 11, 7),
  environment: BlockchainEnvironment.signet,
  signetDeployment: deployment,
  state: state,
  storageToken: token,
);

void main() {
  test(
    'old Signet records remain readable and are never assigned public',
    () async {
      final documents = MemoryWalletRegistryDocumentStore();
      final store = WalletProfileStore(documents);
      final old = _profile();
      await store.stageProvision(old);
      await store.commitProvision(_id);
      final oldDocument = documents.document!;
      expect((jsonDecode(oldDocument) as Map<String, dynamic>)['version'], 1);
      final read = (await store.read() as AppSuccess<WalletRegistry>).value;
      expect(read.activeProfile!.signetDeployment, isNull);
      expect(documents.document, oldDocument);

      final public = _profile(
        id: _otherId,
        token: _otherToken,
        deployment: SignetDeployment.publicBitcoin,
      );
      await store.stageProvision(public);
      await store.commitProvision(_otherId);
      final encoded = jsonDecode(documents.document!) as Map<String, dynamic>;
      expect(encoded['version'], 3);
      expect(encoded['profiles'], [
        containsPair('signetDeployment', null),
        containsPair('signetDeployment', 'public'),
      ]);
      final reopened = (await store.read() as AppSuccess<WalletRegistry>).value;
      expect(reopened.profiles.first.signetDeployment, isNull);
      expect(
        reopened.activeProfile!.signetDeployment,
        SignetDeployment.publicBitcoin,
      );
      expect(
        reopened.activeProfile!.copyWith(name: 'Renamed').signetDeployment,
        SignetDeployment.publicBitcoin,
      );
      expect(public, isNot(_profile(id: _otherId, token: _otherToken)));
    },
  );

  test(
    'Signet schema cannot be downgraded or accept invented deployment names',
    () async {
      final documents = MemoryWalletRegistryDocumentStore();
      final store = WalletProfileStore(documents);
      await store.stageProvision(
        _profile(deployment: SignetDeployment.publicBitcoin),
      );
      final encoded = documents.document!;
      for (final malformed in [
        encoded.replaceFirst('"version":3', '"version":1'),
        encoded.replaceFirst('"version":3', '"version":2'),
        encoded.replaceFirst(
          '"signetDeployment":"public"',
          '"signetDeployment":"utexo"',
        ),
        encoded.replaceFirst(
          '"signetDeployment":"public"',
          '"signetDeployment":true',
        ),
      ]) {
        documents.document = malformed;
        expect(await store.read(), isA<AppFailureResult<WalletRegistry>>());
        expect(documents.document, malformed);
      }
    },
  );

  for (final deployment in [null, SignetDeployment.utexoDev]) {
    test(
      'unknown/other Signet deployment $deployment never touches wallet resources',
      () async {
        final secrets = MemorySecureStore()
          ..readError = StateError('must not read');
        final directories = FakeWalletDirectoryManager();
        final factory = FakeWalletEngineFactory([]);
        final runtime = WalletRuntime(
          factory,
          directories,
          WalletSecretStore(secrets),
          _public,
        );
        addTearDown(runtime.dispose);
        final staged = _profile(deployment: deployment);
        for (final result in [
          await runtime.provision(
            profile: staged,
            mnemonic: 'test phrase',
            databasePassword: 'test',
          ),
          await runtime.restore(
            staged.copyWith(state: WalletProfileState.ready),
          ),
          await runtime.switchTo(
            staged.copyWith(state: WalletProfileState.ready),
          ),
        ]) {
          final failure = (result as AppFailureResult<void>).failure;
          expect(
            failure.code,
            deployment == null
                ? 'wallet_signet_deployment_unverified'
                : 'wallet_signet_deployment_mismatch',
          );
          expect(failure.retryable, isFalse);
        }
        expect(factory.configurations, isEmpty);
        expect(directories.created, isEmpty);
        expect(directories.opened, isEmpty);
        expect(directories.removed, isEmpty);
        expect(secrets.values, isEmpty);
      },
    );
  }

  test(
    'create/import repository path persists explicit public identity',
    () async {
      final documents = MemoryWalletRegistryDocumentStore();
      final profiles = WalletProfileStore(documents);
      final runtime = WalletRuntime(
        FakeWalletEngineFactory([FakeWalletEngine()]),
        FakeWalletDirectoryManager(),
        WalletSecretStore(MemorySecureStore()),
        _public,
      );
      addTearDown(runtime.dispose);
      final keys = FakeWalletKeyGenerator();
      final repository = WalletRepository(
        profiles,
        runtime,
        keys,
        FakeWalletIdentityGenerator(walletId: _id),
        _public,
      );
      final result = await repository.createFromMnemonic(
        name: 'Public Signet',
        mnemonic: keys.generatedMnemonic,
      );
      expect(result, isA<AppSuccess<WalletRegistry>>());
      final reread =
          (await profiles.read() as AppSuccess<WalletRegistry>).value;
      expect(
        reread.activeProfile!.signetDeployment,
        SignetDeployment.publicBitcoin,
      );
      expect(
        runtime.activeProfile!.signetDeployment,
        SignetDeployment.publicBitcoin,
      );
      expect(
        (jsonDecode(documents.document!) as Map<String, dynamic>)['version'],
        3,
      );
    },
  );
}
