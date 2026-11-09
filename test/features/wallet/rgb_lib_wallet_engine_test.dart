import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aster/core/config/config.dart';
import 'package:aster/core/errors/errors.dart';
import 'package:aster/core/platform/local_network_access.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../support/dev_bridge_fixture.dart';
import '../../support/wallet_fakes.dart';

const _channel = MethodChannel('com.utexo.rgb_sdk_flutter/rgb_lib');
const _id = '0123456789abcdef0123456789abcdef';
const _binding =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _cohort = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _txid =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _assetId = 'rgb:approved-fixture';
const _address =
    'bcrt1pe8eqxh3f7nnvq87wmd2wfe2qyaer58czaxjvqkrakf5vsvyql5eqz55zcq';
const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _metadata = {
  'assetSchema': 'Bfa',
  'name': 'Bridged USDT',
  'ticker': 'BUSDT',
  'precision': 6,
  'timestamp': '1',
  'initialSupply': '0',
  'maxSupply': '18446744073709551615',
  'knownCirculatingSupply': '0',
};

final class _NetworkAccess implements LocalNetworkAccess {
  @override
  Future<void> ensureFor(WalletServiceConfiguration services) async {}
}

final class _ChainValidator implements EvmChainValidator {
  @override
  Future<void> verify(WalletServiceConfiguration services) async {}
}

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late FutureOr<Object?> Function(MethodCall) dispatch;
  late RgbLibKeys signingReader;
  late RgbLibWalletEngine engine;
  late Directory storage;
  var phase = 'absent';
  var dispatchedRevocation = false;
  var existingOnlyOpen = true;
  var lostCommitReply = false;
  var pendingNative = false;
  String? pendingCommandJson;
  var restoredSnapshot = false;
  var historyReceived = '999845';
  var historyConfirmed = false;
  var nativeReceipts = <Map<String, Object?>>[];
  var assetPresent = false;
  var orphanReceive = false;
  String? decodedAmount = '1000000';
  String? receivedTransferStatus;
  int? decodedExpiry = 4102444800;

  final publicBytes = utf8.encode('public contract fixture');
  final approved = RgbContractConfiguration(
    contractBase64: base64Encode(publicBytes),
    sha256Digest: sha256.convert(publicBytes).toString(),
    nativeName: 'Bridged USDT',
    nativeTicker: 'BUSDT',
  );
  final services = WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
    backend: WalletBackend.rgbL1,
    indexerUrl: 'http://127.0.0.1:29302',
    rgbTransportProxy: 'rpc://127.0.0.1:29300/json-rpc',
    ethRpcUrl: 'http://127.0.0.1:29545',
    ethChainId: '31337',
    bfaMintLockPolicy: BfaMintLockPolicy(minimumBlocks: 2, maximumBlocks: 512),
    usdtAsset: RgbAssetConfiguration(
      contractId: _assetId,
      precision: 6,
      canonicalContract: approved,
    ),
  );
  final asset = WalletAsset.rgbUsdt(assetId: _assetId, precision: 6);
  final btcRoute = PaymentRoute(
    asset: WalletAsset.bitcoin,
    rail: PaymentRail.onchain,
  );
  final rgbRoute = PaymentRoute(asset: asset, rail: PaymentRail.onchain);

  WalletSendCommand intent({bool rgb = false}) => WalletSendCommand(
    route: rgb ? rgbRoute : btcRoute,
    destination: rgb ? 'rgb:invoice-fixture' : _address,
    amount: WalletAmount.onchain(
      assetId: rgb ? asset.id : WalletAsset.bitcoin.id,
      units: rgb ? 1000000 : 1000,
    ),
    feeRate: WalletFeeRateEstimate(
      targetBlocks: 6,
      satsPerVbyte: 1,
      observedAt: DateTime.now().toUtc(),
      source: WalletFeeRateSource.localRegtestPolicy,
    ),
    rgbRecipientType: rgb ? RgbRecipientType.witness : null,
    witnessBitcoinAmountSats: rgb ? rgbWitnessRecipientSats : null,
  );

  Object? reply(MethodCall call) {
    final args = call.arguments as Map<Object?, Object?>?;
    switch (call.method) {
      case 'getRuntimeInfo':
        return {
          'version': RgbLibRuntimeInfo.expectedVersion,
          'sourceRevision': RgbLibRuntimeInfo.expectedSourceRevision,
          'integrationTree': RgbLibRuntimeInfo.expectedIntegrationTree,
          'overlayPatchSha256': RgbLibRuntimeInfo.expectedOverlayPatchSha256,
          'sourceLockSha256': RgbLibRuntimeInfo.expectedSourceLockSha256,
          'sourceManifestSha256':
              RgbLibRuntimeInfo.expectedSourceManifestSha256,
          'bridgeVersion': RgbLibRuntimeInfo.expectedBridgeVersion,
          'bfa': true,
          'burn': true,
          'consignment': true,
          'contractRegistration': true,
          'durableOnchainRecovery': true,
          'supportsDispatchedRgbRevocation': dispatchedRevocation,
          'supportsExistingOnlyOpen': existingOnlyOpen,
          'nativeOverlay': 'flutter-bfa7-durable-v1',
        };
      case 'openWallet':
        final directory = Directory(args!['dataDir']! as String);
        directory.createSync(recursive: true);
        final profile = File('${directory.path}/rgb-sdk-profile.json');
        if (!profile.existsSync()) {
          profile.writeAsStringSync(
            jsonEncode({
              'formatVersion': 2,
              'backend': 'rgb-lib',
              'id': _binding,
              'network': 'regtest',
              'recoveryCohort': _cohort,
            }),
          );
        }
        return 'handle';
      case 'getWalletIdentity':
        return {
          'id': _binding,
          'network': 'regtest',
          'masterFingerprint': 'a1b2c3d4',
          'recoveryCohort': _cohort,
        };
      case 'importContract':
        assetPresent = true;
        return {
          'assetId': _assetId,
          'alreadyImported': false,
          'metadata': _metadata,
        };
      case 'getAssetMetadata':
        if (!assetPresent) {
          throw PlatformException(code: 'RGB_LIB_AssetNotFound');
        }
        return _metadata;
      case 'goOnline':
        return () async {
          expect(await signingReader.readMnemonic!(), isNull);
          return null;
        }();
      case 'closeWallet':
      case 'assertNoPendingOnchainSend':
      case 'sync':
        return null;
      case 'getNetworkInfo':
        return {'network': 'regtest', 'blockHeight': null};
      case 'decodeInvoice':
        return {
          'recipientId': 'recipient-fixture',
          'recipientType': 'Witness',
          'assetSchema': 'Bfa',
          'assetId': _assetId,
          'network': 'regtest',
          'assignment': {
            'type': decodedAmount == null ? 'Any' : 'Fungible',
            'amount': decodedAmount,
          },
          'expirationTimestamp': decodedExpiry?.toString(),
          'transportEndpoints': ['rpc://127.0.0.1:29300/json-rpc'],
          'encryption': 'Optional',
          'publicKey': 'd' * 64,
          'unknownQueryParams': <Object?>[],
        };
      case 'receive':
        return {
          'invoice': 'rgb:invoice-fixture',
          'recipientId': 'recipient-fixture',
          'expirationTimestamp': decodedExpiry.toString(),
          'batchTransferIdx': 7,
          'publicKey': 'transport-public-key',
        };
      case 'listAssets':
        return [
          {
            ..._metadata,
            'assetId': _assetId,
            'schema': 'Bfa',
            'addedAt': '1',
            'balance': {'settled': '0', 'future': '0', 'spendable': '0'},
          },
        ];
      case 'listTransactions':
        return [
          {
            'txid': _txid,
            'transactionType': 'SendBtc',
            'received': historyReceived,
            'sent': '1000000',
            'fee': '155',
            'confirmationTime': historyConfirmed
                ? {'height': 100, 'timestamp': '1000'}
                : null,
          },
        ];
      case 'listOnchainSendReceipts':
        return jsonEncode({
          'version': 1,
          'walletBinding': _binding,
          'cohort': _cohort,
          'restoredSnapshot': restoredSnapshot,
          'revision': '1',
          'total': nativeReceipts.length,
          'receipts': nativeReceipts,
        });
      case 'listTransfers':
        return receivedTransferStatus == null
            ? <Object?>[]
            : [
                {
                  'idx': 1,
                  'batchTransferIdx': 7,
                  'createdAt': '1000',
                  'updatedAt': '1001',
                  'status': receivedTransferStatus,
                  'kind': 'ReceiveWitness',
                  'requestedAssignment': {
                    'type': 'Fungible',
                    'amount': '1000000',
                  },
                  'assignments': [
                    {'type': 'Fungible', 'amount': '1000000'},
                  ],
                  'txid': _txid,
                  'transportEndpoints': <Object?>[],
                  'changeUtxos': <Object?>[],
                },
              ];
      case 'listUnspents':
        return <Object?>[];
      case 'getAssetBalance':
        return receivedTransferStatus == null
            ? {'settled': '0', 'future': '0', 'spendable': '0'}
            : {
                'settled': receivedTransferStatus == 'Settled'
                    ? '1000000'
                    : '0',
                'future': '1000000',
                'spendable': receivedTransferStatus == 'Settled'
                    ? '1000000'
                    : '0',
              };
      case 'getBtcBalance':
        return {
          'vanilla': {
            'settled': '2000000',
            'future': '2000000',
            'spendable': '2000000',
          },
          'colored': {'settled': '0', 'future': '0', 'spendable': '0'},
        };
      case 'refresh':
        return orphanReceive
            ? [
                {'batchTransferIdx': 9, 'updatedStatus': null, 'failure': null},
              ]
            : <Object?>[];
      case 'failTransfers':
        orphanReceive = false;
        return true;
      case 'onchainRecoveryState':
        return jsonEncode({
          'version': 1,
          'walletBinding': _binding,
          'cohort': _cohort,
          'restoredSnapshot': restoredSnapshot,
          'pending': pendingNative
              ? [
                  {
                    'version': 1,
                    'operationId': _id,
                    'fingerprint': RecoverableOnchainSendCommand.fromJson(
                      pendingCommandJson!,
                    ).fingerprint,
                    'kind': RecoverableOnchainSendCommand.fromJson(
                      pendingCommandJson!,
                    ).kind.name,
                    'phase': phase,
                    'txid': _txid,
                    'batchTransferIndex': null,
                    'failureCode': null,
                    'endAuthorized': phase == 'committing',
                    'commandJson': pendingCommandJson,
                  },
                ]
              : <Object?>[],
        });
      case 'prepareOnchainSend':
        phase = 'prepared';
      case 'commitOnchainSend':
        phase = 'accepted';
        if (lostCommitReply) {
          throw PlatformException(code: 'IO', message: 'lost response');
        }
      case 'revokeOnchainSend':
      case 'cancelOnchainSend':
        phase = 'rejected';
      case 'onchainSendStatus':
        break;
      default:
        throw StateError('Unexpected native operation ${call.method}');
    }
    final command = RecoverableOnchainSendCommand.fromJson(
      args!['requestJson']! as String,
    );
    final hasIdentity = phase == 'prepared' || phase == 'accepted';
    return jsonEncode({
      'version': 1,
      'operationId': command.operationId,
      'fingerprint': phase == 'absent' ? null : command.fingerprint,
      'kind': phase == 'absent' ? null : command.kind.name,
      'phase': phase,
      'txid': hasIdentity ? _txid : null,
      'batchTransferIndex':
          hasIdentity && command.kind == RecoverableOnchainSendKind.rgb
          ? 7
          : null,
      'failureCode': phase == 'rejected'
          ? (call.method == 'revokeOnchainSend' ? 'cancelled' : 'Cancelled')
          : null,
      'endAuthorized': phase == 'accepted',
    });
  }

  setUp(() async {
    storage = await Directory.systemTemp.createTemp('aster_l1_adapter_');
    await File('${storage.path}/.aster-storage-owner').writeAsString(_id);
    calls.clear();
    phase = 'absent';
    dispatchedRevocation = false;
    existingOnlyOpen = true;
    lostCommitReply = false;
    pendingNative = false;
    pendingCommandJson = null;
    restoredSnapshot = false;
    historyReceived = '999845';
    historyConfirmed = false;
    nativeReceipts = [];
    assetPresent = false;
    orphanReceive = false;
    decodedAmount = '1000000';
    receivedTransferStatus = null;
    decodedExpiry = 4102444800;
    dispatch = reply;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return dispatch(call);
    });
    engine = RgbLibWalletEngine(
      services,
      storageDirectory: storage.path,
      localNetworkAccess: _NetworkAccess(),
      evmChainValidator: _ChainValidator(),
      walletFactory: (keys) {
        signingReader = keys;
        return RgbLibWallet(
          params: RgbLibWalletParams(
            network: 'regtest',
            storageDirPath: '${storage.path}/rgb-l1',
          ),
          keys: keys,
        );
      },
    );
  });
  tearDown(() async {
    await engine.destroy();
    messenger.setMockMethodCallHandler(_channel, null);
    await storage.delete(recursive: true);
  });

  Future<void> open() => engine.provision(
    databasePassword: 'database-password-fixture',
    mnemonic: _mnemonic,
  );

  test('Dev preview and fee fallback enforce the exact profile', () async {
    final dev = devBridgeServices();
    final contractId = dev.usdtAsset!.contractId;
    final route = PaymentRoute(
      asset: WalletAsset.rgbUsdt(assetId: contractId, precision: 6),
      rail: PaymentRail.onchain,
    );
    String? invoiceAssetId = contractId;
    var endpoints = [UtexoDevSignetPolicy.rgbTransportProxy];
    var feeResponse = 3.5;
    String? feeError;
    dispatch = (call) {
      switch (call.method) {
        case 'getRuntimeInfo':
          return {
            ...reply(call)! as Map<String, Object?>,
            'supportsHostedDevSignet': true,
          };
        case 'getWalletIdentity':
          return {...reply(call)! as Map<String, Object?>, 'network': 'utexo'};
        case 'importContract':
          return {
            ...reply(call)! as Map<String, Object?>,
            'assetId': contractId,
          };
        case 'decodeInvoice':
          return {
            ...reply(call)! as Map<String, Object?>,
            'network': 'signet',
            'assetId': invoiceAssetId,
            'transportEndpoints': endpoints,
          };
        case 'estimateFeeRate':
          if (feeError case final code?) throw PlatformException(code: code);
          return feeResponse;
        default:
          return reply(call);
      }
    };
    final devEngine = RgbLibWalletEngine(
      dev,
      storageDirectory: storage.path,
      localNetworkAccess: _NetworkAccess(),
      evmChainValidator: _ChainValidator(),
      walletFactory: (keys) {
        signingReader = keys;
        return RgbLibWallet(
          params: RgbLibWalletParams(
            network: 'utexo',
            storageDirPath: '${storage.path}/rgb-l1',
            allowUtexoDevSignet: true,
          ),
          keys: keys,
        );
      },
    );
    addTearDown(devEngine.destroy);
    await devEngine.provision(
      databasePassword: 'database-password-fixture',
      mnemonic: _mnemonic,
    );

    final accepted = await devEngine.decodeInvoice(route, 'rgb:dev-fixture');
    expect(accepted.route.asset.id.value, contractId);
    expect(accepted.amount?.units, 1000000);
    invoiceAssetId = null;
    await expectLater(
      devEngine.decodeInvoice(route, 'rgb:assetless-fixed-fixture'),
      throwsA(isA<WalletValidationException>()),
    );
    decodedAmount = null;
    final neutral = await devEngine.decodeInvoice(route, 'rgb:neutral-fixture');
    expect(neutral.route.asset.id.value, contractId);
    expect(neutral.amount, isNull);
    invoiceAssetId = contractId;
    endpoints = [
      UtexoDevSignetPolicy.rgbTransportProxy,
      'rpcs://proxy.example/json-rpc',
    ];
    await expectLater(
      devEngine.decodeInvoice(route, 'rgb:proxy-substitution-fixture'),
      throwsA(isA<WalletValidationException>()),
    );

    final live = await devEngine.estimateFeeRate(6);
    expect(live.satsPerVbyte, 4);
    expect(live.source, WalletFeeRateSource.networkEstimate);

    feeError = 'RGB_LIB_CannotEstimateFees';
    final fallback = await devEngine.estimateFeeRate(6);
    expect(fallback.satsPerVbyte, 1);
    expect(fallback.source, WalletFeeRateSource.devSignetPolicy);
    expect(fallback.source.appliesTo(services), isFalse);

    feeError = 'RGB_LIB_Indexer';
    await expectLater(
      devEngine.estimateFeeRate(6),
      throwsA(isA<RgbLibWalletException>()),
    );
    feeError = null;
    feeResponse = double.nan;
    await expectLater(devEngine.estimateFeeRate(6), throwsA(isA<Exception>()));
  });

  test('fresh creation rejects a wrapper unable to reopen existing-only before signing', () async {
    existingOnlyOpen = false;
    await expectLater(
      open(),
      throwsA(
        isA<AppFailureException>().having(
          (error) => error.failure.code,
          'code',
          'wallet_backend_capability_unavailable',
        ),
      ),
    );
    expect(calls.map((call) => call.method), ['getRuntimeInfo']);
    expect(await signingReader.readMnemonic!(), isNull);
    expect(await Directory('${storage.path}/rgb-l1').exists(), isFalse);
  });

  test(
    'fresh provisioning cannot adopt an existing nonempty native child',
    () async {
      final child = await Directory('${storage.path}/rgb-l1').create();
      final profile = File('${child.path}/rgb-sdk-profile.json');
      await profile.writeAsString('retained native state');
      await expectLater(open(), throwsA(isA<AppFailureException>()));
      expect(calls, isEmpty);
      expect(await profile.readAsString(), 'retained native state');
    },
  );

  test('default adapter isolates native data beneath its ownership marker and reopens the same cohort', () async {
    await engine.destroy();
    engine = RgbLibWalletEngine(
      services,
      storageDirectory: storage.path,
      localNetworkAccess: _NetworkAccess(),
      evmChainValidator: _ChainValidator(),
    );
    await open();
    await engine.shutdown();
    await engine.openPersistedWithMnemonic(
      databasePassword: 'database-password-fixture',
      mnemonic: _mnemonic,
    );
    final paths = calls
        .where((call) => call.method == 'openWallet')
        .map((call) => (call.arguments as Map)['dataDir']);
    expect(paths, ['${storage.path}/rgb-l1', '${storage.path}/rgb-l1']);
    final opened = calls.where((call) => call.method == 'openWallet').toList();
    expect((opened.first.arguments as Map)['requireExisting'], isNot(isTrue));
    expect((opened.last.arguments as Map)['requireExisting'], isTrue);
    expect(
      await File('${storage.path}/.aster-storage-owner').readAsString(),
      _id,
    );
    final profile = jsonDecode(
      await File('${storage.path}/rgb-l1/rgb-sdk-profile.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(profile['recoveryCohort'], _cohort);
  });

  test(
    'legacy root-level native state is preserved without creating a new child',
    () async {
      final legacy = File('${storage.path}/rgb-sdk-profile.json');
      await legacy.writeAsString('preserved old native profile');
      final failure = throwsA(
        isA<AppFailureException>().having(
          (error) => error.failure,
          'failure',
          const AppFailure(
            code: 'wallet_storage_layout_mismatch',
            kind: AppFailureKind.storage,
            userMessage: 'Wallet recovery is required.',
            retryable: false,
            requiresReconciliation: true,
          ),
        ),
      );
      await expectLater(open(), failure);
      await expectLater(
        engine.openPersistedWithMnemonic(
          databasePassword: 'database-password-fixture',
          mnemonic: _mnemonic,
        ),
        failure,
      );
      expect(await legacy.readAsString(), 'preserved old native profile');
      expect(await Directory('${storage.path}/rgb-l1').exists(), isFalse);
      expect(calls, isEmpty);
    },
  );

  test('missing, empty and symlinked ready-child profiles never access keys or create a cohort', () async {
    final child = Directory('${storage.path}/rgb-l1');
    for (final state in [
      'missing',
      'empty',
      'zero-profile',
      'oversized-profile',
      'symlink',
    ]) {
      if (await child.exists()) await child.delete(recursive: true);
      if (state != 'missing') await child.create();
      final marker = File('${child.path}/rgb-sdk-profile.json');
      if (state == 'zero-profile') await marker.writeAsString('');
      if (state == 'oversized-profile') await marker.writeAsString('x' * 65537);
      if (state == 'symlink') {
        await Link(marker.path).create('${storage.path}/.aster-storage-owner');
      }
      await expectLater(
        engine.openPersistedWithMnemonic(
          databasePassword: 'database-password-fixture',
          mnemonic: _mnemonic,
        ),
        throwsA(
          isA<AppFailureException>().having(
            (error) => error.failure.requiresReconciliation,
            'requiresReconciliation',
            isTrue,
          ),
        ),
      );
      expect(calls, isEmpty, reason: state);
      expect(
        await File('${storage.path}/.aster-storage-owner').readAsString(),
        _id,
      );
    }
  });

  test(
    'SDK profile/cohort rejection remains a preserved integrity failure',
    () async {
      await open();
      await engine.shutdown();
      final profile = File('${storage.path}/rgb-l1/rgb-sdk-profile.json');
      await profile.writeAsString('damaged native profile');
      dispatch = (call) {
        if (call.method == 'openWallet') {
          expect((call.arguments as Map)['requireExisting'], isTrue);
          throw PlatformException(code: 'WALLET_PROFILE_MISMATCH');
        }
        return reply(call);
      };
      calls.clear();
      await expectLater(
        engine.openPersistedWithMnemonic(
          databasePassword: 'database-password-fixture',
          mnemonic: _mnemonic,
        ),
        throwsA(
          isA<AppFailureException>().having(
            (error) => error.failure.requiresReconciliation,
            'requiresReconciliation',
            isTrue,
          ),
        ),
      );
      expect(calls.map((call) => call.method), isNot(contains('goOnline')));
      expect(await profile.readAsString(), 'damaged native profile');
    },
  );

  test(
    'owned recursive deletion removes the native child and retains siblings',
    () async {
      final nativeRoot = await Directory.systemTemp.createTemp(
        'aster_l1_owned_',
      );
      addTearDown(() => nativeRoot.delete(recursive: true));
      final directories = IoWalletDirectoryManager(
        nativeRoot.path,
        MemoryWalletStorageSecurity(),
      );
      final owned = await directories.create(_id, storageToken: _cohort);
      final siblingId = 'e' * 32;
      final sibling = await directories.create(
        siblingId,
        storageToken: 'f' * 32,
      );
      await Directory('$owned/rgb-l1').create();
      await File('$owned/rgb-l1/preserved-native-state')
          .writeAsString('native state');
      await directories.removeDeletedWallet(_id, storageToken: _cohort);
      expect(await Directory(owned).exists(), isFalse);
      expect(
        await File('$sibling/.aster-storage-owner').readAsString(),
        'f' * 32,
      );
    },
  );

  test(
    'sync awaits one complete transfer refresh after the chain sync',
    () async {
      await open();
      calls.clear();
      await engine.sync();
      expect(calls.map((call) => call.method), ['sync', 'refresh']);
    },
  );

  test('one historical witness failure prevents a successful sync despite newer successful batches', () async {
    await open();
    dispatch = (call) {
      if (call.method == 'refresh') {
        return [
          {'batchTransferIdx': 23, 'updatedStatus': 'Settled', 'failure': null},
          {
            'batchTransferIdx': 3,
            'updatedStatus': null,
            'failure': {
              'name': 'RGB_LIB_Proxy',
              'message': 'private witness endpoint and response payload',
            },
          },
        ];
      }
      return reply(call);
    };
    calls.clear();
    await expectLater(
      engine.sync(),
      throwsA(
        isA<AppFailureException>().having(
          (error) => error.failure,
          'failure',
          const AppFailure(
            code: 'wallet_sync_incomplete',
            kind: AppFailureKind.unavailable,
            userMessage: 'Wallet updates are unavailable. Try again.',
            retryable: true,
          ),
        ),
      ),
    );
    expect(calls.map((call) => call.method), ['sync', 'refresh']);

    // Recovery is a later read-only sync, never a payment or prepare replay.
    dispatch = reply;
    calls.clear();
    await engine.sync();
    expect(calls.map((call) => call.method), ['sync', 'refresh']);
  });

  test(
    'imports exact approved metadata before online and clears mnemonic reader',
    () async {
      await open();
      final methods = calls.map((call) => call.method).toList();
      expect(
        methods.indexOf('importContract'),
        lessThan(methods.indexOf('goOnline')),
      );
      expect(
        methods.indexOf('getAssetMetadata'),
        lessThan(methods.indexOf('goOnline')),
      );
      final imported = calls.singleWhere(
        (call) => call.method == 'importContract',
      );
      expect(
        (imported.arguments as Map<Object?, Object?>)['expectedAssetId'],
        _assetId,
      );
      expect(
        (imported.arguments as Map<Object?, Object?>)['contractBase64'],
        approved.contractBase64,
      );
      expect(await signingReader.readMnemonic!(), isNull);
      final online = calls.singleWhere((call) => call.method == 'goOnline');
      expect(
        (online.arguments as Map<Object?, Object?>)['evmMinMintLockBlocks'],
        ['2'],
      );
      expect(
        (online.arguments as Map<Object?, Object?>)['evmMaxMintLockBlocks'],
        ['512'],
      );
      expect((online.arguments as Map<Object?, Object?>)['evmChainIds'], [
        '31337',
      ]);
      expect((online.arguments as Map<Object?, Object?>)['evmRpcUrls'], [
        'http://127.0.0.1:29545',
      ]);
    },
  );

  test(
    'missing native recovery capability fails before reading signing material',
    () async {
      dispatch = (call) => call.method == 'getRuntimeInfo'
          ? {
              ...(reply(call)! as Map<String, Object?>),
              'durableOnchainRecovery': false,
            }
          : reply(call);
      await expectLater(open(), throwsA(isA<AppFailureException>()));
      expect(calls.where((call) => call.method == 'openWallet'), isEmpty);
      expect(await signingReader.readMnemonic!(), isNull);
    },
  );

  test(
    'old archive does not advertise or invoke explicit dispatched revocation',
    () async {
      await open();
      expect(await engine.supportsDispatchedRgbRevocation(), isFalse);
      final request = await engine.paymentOperationRequest(
        _id,
        intent(rgb: true),
      );
      await expectLater(
        engine.revokeDispatchedRgbOperation(request),
        throwsA(isA<RgbLibWalletException>()),
      );
      expect(
        calls.where((call) => call.method == 'revokeOnchainSend'),
        isEmpty,
      );
      expect(
        calls.where((call) => call.method == 'cancelOnchainSend'),
        isEmpty,
      );
    },
  );

  test(
    'explicit revocation forwards only the reviewed new native operation',
    () async {
      dispatchedRevocation = true;
      await open();
      expect(await engine.supportsDispatchedRgbRevocation(), isTrue);
      final request = await engine.paymentOperationRequest(
        _id,
        intent(rgb: true),
      );
      final status = await engine.revokeDispatchedRgbOperation(request);
      expect(status.phase, WalletPaymentRecoveryPhase.rejected);
      expect(status.endAuthorized, isFalse);
      expect(status.failureCode, 'cancelled');
      final sent = calls.singleWhere(
        (call) => call.method == 'revokeOnchainSend',
      );
      expect((sent.arguments as Map<Object?, Object?>)['requestJson'], request);
      expect(
        calls.where(
          (call) => {
            'cancelOnchainSend',
            'prepareOnchainSend',
            'commitOnchainSend',
          }.contains(call.method),
        ),
        isEmpty,
      );
    },
  );

  test('metadata mismatch prevents asset admission and connection', () async {
    dispatch = (call) => call.method == 'importContract'
        ? {
            'assetId': _assetId,
            'alreadyImported': true,
            'metadata': {..._metadata, 'ticker': 'WRONG'},
          }
        : reply(call);
    await expectLater(open(), throwsA(isA<NativeProtocolException>()));
    expect(calls.where((call) => call.method == 'goOnline'), isEmpty);
    expect(await signingReader.readMnemonic!(), isNull);
    await expectLater(
      engine.getBalance(asset),
      throwsA(isA<AppConfigurationException>()),
    );
  });

  test('first witness receive binds the canonical asset and exact requested amount', () async {
    await open();
    final request = await engine.createReceiveRequest(
      rgbRoute,
      amount: WalletAmount.onchain(assetId: asset.id, units: 1000000),
    );
    expect(request.amount?.units, 1000000);
    final native = calls.singleWhere((call) => call.method == 'receive');
    expect((native.arguments as Map<Object?, Object?>)['witness'], isTrue);
    expect((native.arguments as Map<Object?, Object?>)['assetId'], _assetId);
    expect((native.arguments as Map<Object?, Object?>)['amount'], '1000000');
    expect((native.arguments as Map<Object?, Object?>)['minConfirmations'], 1);
    expect(
      (native.arguments as Map<Object?, Object?>)['assignmentKind'],
      'Fungible',
    );
    expect(request.batchTransferIndex, 7);
  });

  test('amountless witness requests also require one confirmation', () async {
    await open();
    decodedAmount = null;
    final request = await engine.createReceiveRequest(rgbRoute);
    expect(request.amount, isNull);
    final arguments =
        calls.singleWhere((call) => call.method == 'receive').arguments
            as Map<Object?, Object?>;
    expect(arguments['witness'], isTrue);
    expect(arguments['amount'], isNull);
    expect(arguments['minConfirmations'], 1);
  });

  test(
    'unconfirmed RGB stays waiting and unspendable until native settlement',
    () async {
      await open();
      receivedTransferStatus = 'WaitingConfirmations';
      var balance = await engine.getBalance(asset);
      var history = await engine.listActivity(asset);
      expect(balance.onchainFuture.units, 1000000);
      expect(balance.onchainSettled.units, 0);
      expect(balance.onchainSpendable.units, 0);
      expect(history.single.status, WalletActivityStatus.waitingConfirmations);
      expect(history.single.amount!.units, 1000000);
      receivedTransferStatus = 'Settled';
      balance = await engine.getBalance(asset);
      history = await engine.listActivity(asset);
      expect(balance.onchainSettled.units, 1000000);
      expect(balance.onchainSpendable.units, 1000000);
      expect(history.single.status, WalletActivityStatus.succeeded);
      expect(history.single.amount!.units, 1000000);
    },
  );

  test(
    'receive rejects a native invoice that changed the requested amount',
    () async {
      await open();
      decodedAmount = '999999';
      await expectLater(
        engine.createReceiveRequest(
          rgbRoute,
          amount: WalletAmount.onchain(assetId: asset.id, units: 1000000),
        ),
        throwsA(isA<NativeProtocolException>()),
      );
    },
  );

  test('lost commit response resolves by exact read after reopen without another commit', () async {
    await open();
    final command = intent();
    final request = await engine.paymentOperationRequest(_id, command);
    expect(calls.where((call) => call.method == 'prepareOnchainSend'), isEmpty);
    expect(
      (await engine.preparePaymentOperation(request)).phase,
      WalletPaymentRecoveryPhase.prepared,
    );
    lostCommitReply = true;
    await expectLater(
      engine.commitPaymentOperation(request),
      throwsA(isA<RgbSdkException>()),
    );
    await engine.shutdown();
    await engine.openPersistedWithMnemonic(
      databasePassword: 'database-password-fixture',
      mnemonic: _mnemonic,
    );
    await engine.validatePaymentOperationRequest(request, _id, command);
    final recovered = await engine.inspectPaymentOperation(request);
    expect(recovered.phase, WalletPaymentRecoveryPhase.accepted);
    expect(recovered.referenceId, _txid);
    expect(
      calls.where((call) => call.method == 'commitOnchainSend'),
      hasLength(1),
    );
    expect(
      calls.where((call) => call.method == 'sendBtc' || call.method == 'send'),
      isEmpty,
    );
    expect(await signingReader.readMnemonic!(), isNull);
  });

  test(
    'an altered saved amount cannot reach native payment inspection',
    () async {
      await open();
      final original = intent();
      final request = await engine.paymentOperationRequest(_id, original);
      final altered = WalletSendCommand(
        route: original.route,
        destination: original.destination,
        amount: WalletAmount.onchain(
          assetId: WalletAsset.bitcoin.id,
          units: 1001,
        ),
        feeRate: original.feeRate,
      );
      final inspectedBefore = calls
          .where((call) => call.method == 'onchainSendStatus')
          .length;
      await expectLater(
        engine.validatePaymentOperationRequest(request, _id, altered),
        throwsA(isA<NativeProtocolException>()),
      );
      expect(
        calls.where((call) => call.method == 'onchainSendStatus'),
        hasLength(inspectedBefore),
      );
    },
  );

  test('expired RGB receipt revalidation remains read-only after restart', () async {
    await open();
    final command = intent(rgb: true);
    final futureRequest = await engine.paymentOperationRequest(_id, command);
    // A historical canonical command may already be expired. Restoration must
    // verify its exact approved inputs without authorizing another preparation.
    final saved = jsonDecode(futureRequest) as Map<String, Object?>;
    final request = saved['request']! as Map<String, Object?>;
    decodedExpiry =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 3600;
    request['expirationTimestamp'] = decodedExpiry.toString();
    request.remove('fingerprint');
    request['fingerprint'] = sha256
        .convert(utf8.encode(jsonEncode(saved)))
        .toString();
    final historical = RecoverableOnchainSendCommand.fromJson(jsonEncode(saved))
        .requestJson;
    phase = 'accepted';
    await engine.shutdown();
    await engine.openPersistedWithMnemonic(
      databasePassword: 'database-password-fixture',
      mnemonic: _mnemonic,
    );
    await engine.validatePaymentOperationRequest(historical, _id, command);
    expect(
      (await engine.inspectPaymentOperation(historical)).phase,
      WalletPaymentRecoveryPhase.accepted,
    );
    expect(
      calls.where(
        (call) =>
            call.method == 'prepareOnchainSend' ||
            call.method == 'commitOnchainSend',
      ),
      isEmpty,
    );
  });

  test(
    'native pending records independently protect wallet deletion',
    () async {
      await open();
      pendingCommandJson = await engine.paymentOperationRequest(_id, intent());
      phase = 'prepared';
      pendingNative = true;
      expect(await engine.hasProtectedRgbState(), isTrue);
      expect(
        calls.where(
          (call) => call.method == 'refresh' || call.method == 'listAssets',
        ),
        isEmpty,
      );
    },
  );

  test(
    'native discovery preserves exact approval without a new quote or send',
    () async {
      await open();
      pendingCommandJson = await engine.paymentOperationRequest(_id, intent());
      phase = 'committing';
      pendingNative = true;
      final operation =
          (await engine.discoverPendingPaymentOperations()).single;
      expect(operation.operationId, _id);
      expect(operation.request, pendingCommandJson);
      expect(operation.command.amount.units, 1000);
      expect(operation.command.destination, _address);
      expect(
        operation.command.feeRate!.source,
        WalletFeeRateSource.nativeRecovery,
      );
      expect(operation.command.feeRate!.targetBlocks, isNull);
      expect(operation.command.feeRate!.isStaleAt(DateTime.now()), isTrue);
      await engine.validateDiscoveredPaymentOperation(
        operation.request,
        operation.operationId,
        operation.command,
      );
      await expectLater(
        engine.validateDiscoveredPaymentOperation(
          operation.request,
          '1' * 32,
          operation.command,
        ),
        throwsA(isA<NativeProtocolException>()),
      );
      expect(
        calls.where(
          (call) =>
              call.method == 'commitOnchainSend' ||
              call.method == 'prepareOnchainSend' ||
              call.method == 'estimateFeeRate',
        ),
        isEmpty,
      );
    },
  );

  test('restored native snapshot cannot imply no pending payment', () async {
    await open();
    restoredSnapshot = true;
    await expectLater(
      engine.discoverPendingPaymentOperations(),
      throwsA(
        isA<RgbLibWalletException>().having(
          (error) => error.code,
          'code',
          'RECOVERY_RESTORE_UNCERTAIN',
        ),
      ),
    );
    await expectLater(
      engine.hasProtectedRgbState(),
      throwsA(isA<RgbLibWalletException>()),
    );
  });

  test('native accepted receipt restores gross self-send amount without app receipt', () async {
    await open();
    nativeReceipts = [
      {
        'version': 1,
        'operationId': _id,
        'fingerprint': 'd' * 64,
        'kind': 'bitcoin',
        'phase': 'accepted',
        'endAuthorized': true,
        'txid': _txid,
        'batchTransferIndex': null,
        'failureCode': null,
        'amount': '1000',
        'feeRate': '1',
        'assetId': null,
        'address': _address,
        'recipientId': null,
      },
    ];
    var activity = (await engine.listActivity(WalletAsset.bitcoin)).single;
    expect(activity.amount!.units, 1000);
    expect(activity.operation, WalletActivityOperation.bitcoinSelfTransfer);
    expect(activity.direction, WalletActivityDirection.internal);
    expect(activity.fee!.units, 155);
    expect(activity.status, WalletActivityStatus.pending);
    expect(activity.confirmedAt, isNull);
    historyConfirmed = true;
    activity = (await engine.listActivity(WalletAsset.bitcoin)).single;
    expect(activity.status, WalletActivityStatus.succeeded);
    expect(activity.confirmationHeight, 100);
    expect(
      calls.where(
        (call) =>
            call.method == 'commitOnchainSend' ||
            call.method == 'prepareOnchainSend',
      ),
      isEmpty,
    );
    // Submission history can be read from a restored snapshot, but that still
    // cannot authorize new spending or resolve a missing pending marker.
    restoredSnapshot = true;
    expect(
      (await engine.listActivity(WalletAsset.bitcoin)).single.amount!.units,
      1000,
    );
    await expectLater(
      engine.discoverPendingPaymentOperations(),
      throwsA(isA<RgbLibWalletException>()),
    );
  });

  test(
    'conflicting accepted gross amount never overrides native chain movement',
    () async {
      await open();
      historyReceived = '998845'; // 1000 sat external movement plus the fee.
      nativeReceipts = [
        {
          'version': 1,
          'operationId': _id,
          'fingerprint': 'd' * 64,
          'kind': 'bitcoin',
          'phase': 'accepted',
          'endAuthorized': true,
          'txid': _txid,
          'batchTransferIndex': null,
          'failureCode': null,
          'amount': '2000',
          'feeRate': '1',
          'assetId': null,
          'address': _address,
          'recipientId': null,
        },
      ];
      await expectLater(
        engine.listActivity(WalletAsset.bitcoin),
        throwsA(isA<NativeProtocolException>()),
      );
      nativeReceipts[0]['txid'] = 'e' * 64;
      expect(
        (await engine.listActivity(WalletAsset.bitcoin)).single.amount!.units,
        1000,
      );
    },
  );

  test(
    'receipt pages restart reads once when native revision changes',
    () async {
      await open();
      var generation = 0;
      var reads = 0;
      dispatch = (call) {
        if (call.method != 'listOnchainSendReceipts') return reply(call);
        reads++;
        final arguments = call.arguments as Map<Object?, Object?>;
        final offset = arguments['offset']! as int;
        if (offset > 0) generation = 1;
        final rows = <Map<String, Object?>>[];
        for (var index = offset; index < (offset == 0 ? 500 : 501); index++) {
          rows.add({
            'version': 1,
            'operationId': (index + 1).toRadixString(16).padLeft(32, '0'),
            'fingerprint': 'd' * 64,
            'kind': 'bitcoin',
            'phase': 'accepted',
            'endAuthorized': true,
            'txid': (index + 1).toRadixString(16).padLeft(64, '0'),
            'batchTransferIndex': null,
            'failureCode': null,
            'amount': '1000',
            'feeRate': '1',
            'assetId': null,
            'address': _address,
            'recipientId': null,
          });
        }
        return jsonEncode({
          'version': 1,
          'walletBinding': _binding,
          'cohort': _cohort,
          'restoredSnapshot': false,
          'revision': '$generation',
          'total': 501,
          'receipts': rows,
        });
      };
      expect(
        (await engine.listActivity(WalletAsset.bitcoin)).single.amount,
        isNull,
      );
      expect(reads, 4);
      expect(
        calls.where(
          (call) =>
              call.method == 'commitOnchainSend' ||
              call.method == 'prepareOnchainSend',
        ),
        isEmpty,
      );
    },
  );

  test(
    'expired orphan receives are reconciled only by native guarded selection',
    () async {
      await open();
      orphanReceive = true;
      expect(await engine.hasProtectedRgbState(), isFalse);
      final fail = calls.singleWhere((call) => call.method == 'failTransfers');
      final arguments = fail.arguments as Map<Object?, Object?>;
      expect(arguments['noAssetOnly'], isTrue);
      expect(arguments['batchTransferIdx'], isNull);
      expect(calls.where((call) => call.method == 'refresh'), hasLength(2));
      expect(
        calls.where(
          (call) =>
              call.method == 'commitOnchainSend' ||
              call.method == 'send' ||
              call.method == 'sendBtc',
        ),
        isEmpty,
      );
    },
  );

  for (final kind in ['MintRight', 'InflationRight', 'Fungible']) {
    for (final settled in [false, true]) {
      test(
        'deletion protects $kind allocation with zero balance settled=$settled',
        () async {
          await open();
          dispatch = (call) => call.method == 'listUnspents'
              ? [
                  {
                    'utxo': {
                      'outpoint': {'txid': _txid, 'vout': 1},
                      'btcAmount': '1000',
                      'colorable': true,
                      'exists': true,
                    },
                    'pendingBlinded': 0,
                    'rgbAllocations': [
                      {
                        'assetId': 'rgb:foreign-asset',
                        'settled': settled,
                        'assignment': {
                          'type': kind,
                          if (kind != 'MintRight') 'amount': '0',
                        },
                      },
                    ],
                  },
                ]
              : reply(call);
          expect(await engine.hasProtectedRgbState(), isTrue);
          expect(
            calls.where((call) => call.method == 'failTransfers'),
            isEmpty,
          );
        },
      );
    }
  }

  test(
    'missing or malformed allocation inventory cannot authorize deletion',
    () async {
      await open();
      for (final value in [
        null,
        [
          {'utxo': <String, Object?>{}},
        ],
      ]) {
        dispatch = (call) =>
            call.method == 'listUnspents' ? value : reply(call);
        await expectLater(
          engine.hasProtectedRgbState(),
          throwsA(isA<NativeProtocolException>()),
        );
      }
      dispatch = (call) {
        if (call.method == 'listUnspents') {
          throw PlatformException(code: 'RGB_LIB_FailedSync');
        }
        return reply(call);
      };
      await expectLater(
        engine.hasProtectedRgbState(),
        throwsA(isA<RgbLibWalletException>()),
      );
    },
  );

  test('incomplete native transfer audit cannot authorize deletion', () async {
    await open();
    dispatch = (call) => call.method == 'refresh'
        ? [
            {
              'batchTransferIdx': 9,
              'updatedStatus': null,
              'failure': {'name': 'RGB_LIB_FailedSync'},
            },
          ]
        : reply(call);
    await expectLater(
      engine.hasProtectedRgbState(),
      throwsA(isA<NativeProtocolException>()),
    );
    expect(calls.where((call) => call.method == 'failTransfers'), isEmpty);
  });

  test(
    'expired unfunded blind reservation is checked again after guarded cleanup',
    () async {
      await open();
      orphanReceive = true;
      dispatch = (call) => call.method == 'listUnspents'
          ? [
              {
                'utxo': {
                  'outpoint': {'txid': _txid, 'vout': 1},
                  'btcAmount': '1000',
                  'colorable': true,
                  'exists': true,
                },
                'pendingBlinded': orphanReceive ? 1 : 0,
                'rgbAllocations': <Object?>[],
              },
            ]
          : reply(call);
      expect(await engine.hasProtectedRgbState(), isFalse);
      expect(
        calls.where((call) => call.method == 'failTransfers'),
        hasLength(1),
      );
      expect(
        calls.where((call) => call.method == 'listUnspents'),
        hasLength(2),
      );
    },
  );

  test(
    'output preparation review cannot move to another storage cohort',
    () async {
      await open();
      final original = await engine.rgbSetupInventory();
      await engine.destroy();
      final secondStorage = await Directory.systemTemp.createTemp(
        'aster_l1_other_cohort_',
      );
      addTearDown(() async {
        await engine.destroy();
        await secondStorage.delete(recursive: true);
      });
      dispatch = (call) => call.method == 'getWalletIdentity'
          ? {
              ...(reply(call) as Map<String, Object?>),
              'recoveryCohort': 'c' * 32,
            }
          : reply(call);
      engine = RgbLibWalletEngine(
        services,
        storageDirectory: secondStorage.path,
        localNetworkAccess: _NetworkAccess(),
        evmChainValidator: _ChainValidator(),
        walletFactory: (keys) => RgbLibWallet(
          params: RgbLibWalletParams(
            network: 'regtest',
            storageDirPath: '${secondStorage.path}/rgb-l1',
          ),
          keys: keys,
        ),
      );
      await open();
      final replacement = await engine.rgbSetupInventory();
      expect(replacement.nodePublicKey, original.nodePublicKey);
      expect(
        replacement.runtimeFingerprint,
        isNot(original.runtimeFingerprint),
      );
    },
  );

  test(
    'on-chain network status does not invent a tip or Lightning node',
    () async {
      await open();
      final status = await engine.getNetworkStatus();
      expect(status.walletIdentity, _binding);
      expect(status.nodePublicKey, isNull);
      expect(status.blockHeight, isNull);
      expect(status.channelCount, isNull);
      expect(status.peerCount, isNull);
    },
  );
}
