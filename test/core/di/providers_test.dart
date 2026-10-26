import 'dart:async';
import 'dart:io';

import 'package:aster/core/bootstrap/app_bootstrap.dart';
import 'package:aster/core/core.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/scan_fakes.dart';
import '../../support/wallet_fakes.dart';

void main() {
  for (final metadataDirectoryExists in [false, true]) {
    testWidgets(
      'pre-auth metadata composition survives a delayed native path '
      'with ${metadataDirectoryExists ? 'an empty metadata directory' : 'fresh-install storage'}',
      (tester) async {
        final support = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('aster-pre-auth-providers-'),
        ))!;
        addTearDown(() => support.delete(recursive: true));
        final metadataPath =
            '${support.path}${Platform.pathSeparator}aster_wallet_metadata';
        if (metadataDirectoryExists) {
          await tester.runAsync(() => Directory(metadataPath).create());
        }
        const paths = MethodChannel('plugins.flutter.io/path_provider');
        final nativePath = Completer<String>();
        var pathRequests = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, (
          call,
        ) async {
          expectSync(call.method, 'getApplicationSupportDirectory');
          pathRequests += 1;
          return nativePath.future;
        });
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            paths,
            null,
          ),
        );

        final policy = MemoryWalletStorageSecurity();
        var policyBuilds = 0;
        var credentialAccesses = 0;
        var runtimeAccesses = 0;
        final security = SecurityController(const _UnsecuredDevice());
        addTearDown(security.dispose);
        final container = ProviderContainer(
          retry: applicationProviderRetryPolicy,
          overrides: [
            securityControllerProvider.overrideWithValue(security),
            walletStorageSecurityProvider.overrideWith((ref) {
              policyBuilds += 1;
              return policy;
            }),
            secureStorageServiceProvider.overrideWith((ref) {
              credentialAccesses += 1;
              throw StateError(
                'Public pre-auth metadata must not read credentials.',
              );
            }),
            walletRuntimeProvider.overrideWith((ref) async {
              runtimeAccesses += 1;
              throw StateError(
                'Public pre-auth metadata must not construct a wallet runtime.',
              );
            }),
          ],
        );
        addTearDown(container.dispose);
        final compositionErrors = <(Object, StackTrace)>[];
        var resolved = false;
        // Match main.dart's listener-free pre-auth read. Neither the profile nor
        // document-store provider is replaced by a test fixture.
        final pending = container
            .read(walletProfileStoreProvider.future)
            .then<WalletProfilePersistence?>(
              (profiles) {
                resolved = true;
                return profiles;
              },
              onError: (Object error, StackTrace stackTrace) {
                resolved = true;
                compositionErrors.add((error, stackTrace));
                return null;
              },
            );
        // Cross several frame/event boundaries while the first native plugin
        // response is pending, reproducing a fresh install's slow path lookup.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => pumpEventQueue());
        expect(pathRequests, 1);
        expect(resolved, isFalse);
        expect(security.canAccessWallet, isFalse);
        expect(credentialAccesses, 0);
        expect(runtimeAccesses, 0);

        nativePath.complete(support.path);
      await tester.pump();
        final profiles = await tester.runAsync(() => pending);
        expect(
          compositionErrors,
          isEmpty,
          reason:
              'Delayed metadata composition must not access a disposed Ref: '
              '$compositionErrors',
        );
        expect(profiles, isNotNull);
        final registry = await tester.runAsync(profiles!.read);
        expect(registry, isA<AppSuccess<WalletRegistry>>());
        final value = (registry! as AppSuccess<WalletRegistry>).value;
        expect(value.profiles, isEmpty);
        expect(value.activeWalletId, isNull);
        expect(policyBuilds, 1);
        expect(
          policy.verifiedDirectories,
          metadataDirectoryExists ? [metadataPath] : isEmpty,
        );
        expect(policy.preparedRoots, isEmpty);
        expect(policy.replacedFiles, isEmpty);
        expect(credentialAccesses, 0);
        expect(runtimeAccesses, 0);
        expect(
          security.canAccessWallet,
          isFalse,
          reason:
              'Reading public metadata must not bypass the later auth gate.',
        );
      },
    );
  }

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
    final security = SecurityController(const _UnsecuredDevice());
    await security.initialize(hasWallet: false);
    addTearDown(security.dispose);
    final container = ProviderContainer(
      overrides: [
        securityControllerProvider.overrideWithValue(security),
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
      expect(reported.single.library, 'Aster scan lifecycle');
    },
  );
}

final class _UnsecuredDevice implements DeviceAuthentication {
  const _UnsecuredDevice();
  @override
  Future<DeviceSecurityStatus> status() async => DeviceSecurityStatus.unsecured;
  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) async =>
      throw StateError('Unsecured devices do not prompt');
  @override
  Future<void> cancel() async {}
  @override
  Future<void> setSensitive(bool sensitive) async {}
  @override
  Stream<bool> get captureChanges => const Stream<bool>.empty();
  @override
  bool get isCaptured => false;
}
