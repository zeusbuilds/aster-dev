import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter_advanced.dart'
    show RlnClient, createAdvancedUtexoWallet;

final class _Wallet extends Mock implements UtexoWallet {}

final class _Client extends Mock implements RlnClient {}

// This is an adapter fixture, not a native-status decoder substitute. SDK tests
// separately enforce JSON, fingerprint and phase invariants at the bridge.
final class _NativeStatus extends Mock
    implements RecoverableOnchainSendStatus {}

const _id = '0123456789abcdef0123456789abcdef';
const _address =
    'bcrt1pe8eqxh3f7nnvq87wmd2wfe2qyaer58czaxjvqkrakf5vsvyql5eqz55zcq';
const _assetId = 'rgb:adapter-fixture';
const _txid =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _vanillaKey = 'tpub-readonly-fixture-full-vanilla-account-key';
const _coloredKey = 'tpub-readonly-fixture-full-colored-account-key';
const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
  usdtAsset: RgbAssetConfiguration(
    contractId: _assetId,
    precision: 6,
    requiresEvmValidation: false,
  ),
);
final _now = DateTime.utc(2026, 10, 24, 10);
final _asset = WalletAsset.rgbUsdt(assetId: _assetId, precision: 6);

// A canonical SDK document represents the value returned by the command factory.
// The hash here builds fixture data; these tests do not re-test its algorithm.
String _walletBinding({
  String network = 'regtest',
  String vanilla = _vanillaKey,
  String colored = _coloredKey,
}) => sha256
    .convert(
      utf8.encode(
        jsonEncode(<Object?>[
          'rgb_sdk_flutter/recoverable-wallet/v2',
          network,
          vanilla,
          colored,
        ]),
      ),
    )
    .toString();

RecoverableOnchainSendCommand _document({
  bool rgb = false,
  String operationId = _id,
  int amount = 1000,
  String address = _address,
  int feeRate = 3,
  int version = 2,
  String? walletBinding,
  String storageDirPath = '/adapter-wallet',
  String network = 'regtest',
  int? expiry,
  int? witnessAmount,
}) {
  final request = <String, Object?>{
    'version': 1,
    'operationId': operationId,
    'kind': rgb ? 'rgb' : 'bitcoin',
    'amount': amount,
    'feeRate': feeRate,
    'address': rgb ? null : address,
    'assetId': rgb ? _assetId : null,
    'recipientId': rgb ? 'recipient-fixture' : null,
    'transportEndpoints': rgb ? ['rpc://127.0.0.1:29300/json-rpc'] : <String>[],
    'witnessAmountSat': witnessAmount,
    'witnessBlinding': null,
    'minConfirmations': 1,
    'donation': false,
    'expirationTimestamp': rgb ? (expiry ?? 4102444800) : null,
  };
  final envelope = <String, Object?>{
    'version': version,
    'network': network,
    if (version == 1)
      'storageDirPath': storageDirPath
    else
      'walletBinding': walletBinding ?? _walletBinding(network: network),
    'request': request,
  };
  request['fingerprint'] = sha256
      .convert(utf8.encode(jsonEncode(envelope)))
      .toString();
  return RecoverableOnchainSendCommand.fromJson(jsonEncode(envelope));
}

WalletSendCommand _intent({
  bool rgb = false,
  int amount = 1000,
  DateTime? reviewedAt,
  RgbRecipientType recipientType = RgbRecipientType.blind,
}) => WalletSendCommand(
  route: PaymentRoute(
    asset: rgb ? _asset : WalletAsset.bitcoin,
    rail: PaymentRail.onchain,
  ),
  destination: rgb ? 'rgb:fixture-invoice' : _address,
  amount: WalletAmount.onchain(
    assetId: rgb ? _asset.id : WalletAsset.bitcoin.id,
    units: amount,
  ),
  feeRate: WalletFeeRateEstimate(
    targetBlocks: 6,
    satsPerVbyte: 3,
    observedAt: reviewedAt ?? _now,
  ),
  rgbRecipientType: rgb ? recipientType : null,
  witnessBitcoinAmountSats: rgb && recipientType == RgbRecipientType.witness
      ? rgbWitnessRecipientSats
      : null,
);

RgbWalletEngine _engine(UtexoWallet wallet) =>
    RgbWalletEngine(wallet, _services, UtexoUnlockConfig(), clock: () => _now);

_NativeStatus _status(
  RecoverableOnchainSendPhase phase, {
  bool endAuthorized = false,
  String? txid,
  int? batch,
  String? failureCode,
}) {
  final status = _NativeStatus();
  when(() => status.phase).thenReturn(phase);
  when(() => status.endAuthorized).thenReturn(endAuthorized);
  when(() => status.txid).thenReturn(txid);
  when(() => status.batchTransferIndex).thenReturn(batch);
  when(() => status.failureCode).thenReturn(failureCode);
  return status;
}

void _bitcoinFactory(_Wallet wallet, RecoverableOnchainSendCommand document) {
  when(
    () => wallet.createRecoverableBtcSendCommand(
      operationId: any(named: 'operationId'),
      amount: any(named: 'amount'),
      address: any(named: 'address'),
      feeRate: any(named: 'feeRate'),
    ),
  ).thenAnswer((_) async => document);
}

void _rgbFactory(_Wallet wallet, RecoverableOnchainSendCommand document) {
  when(
    () => wallet.createRecoverableRgbSendCommand(
      operationId: any(named: 'operationId'),
      request: any(named: 'request'),
    ),
  ).thenAnswer((_) async => document);
}

void _invoice(
  _Wallet wallet, {
  int? expiry = 4102444800,
  String kind = 'Blind',
}) {
  when(() => wallet.decodeRgbInvoice('rgb:fixture-invoice')).thenAnswer(
    (_) async => CoreInvoiceData(
      invoice: 'rgb:fixture-invoice',
      recipientId: 'recipient-fixture',
      recipientType: kind,
      assetId: _assetId,
      network: 'regtest',
      assignment: Assignment(type: 'Fungible', amount: BigInt.from(1000)),
      expirationTimestamp: expiry,
      transportEndpoints: const ['rpc://127.0.0.1:29300/json-rpc'],
    ),
  );
}

void _noMutation(_Wallet wallet) {
  verifyNever(() => wallet.prepareOnchainSend(any()));
  verifyNever(() => wallet.commitOnchainSend(any()));
  verifyNever(() => wallet.cancelOnchainSend(any()));
  verifyNever(
    () => wallet.sendBtc(
      amount: any(named: 'amount'),
      address: any(named: 'address'),
      feeRate: any(named: 'feeRate'),
    ),
  );
  verifyNever(() => wallet.onchainSend(any()));
}

// Exercise the real SDK factory and node-info decoder; only native lifecycle
// and readonly account metadata are mocked. No native wallet is made.
Future<UtexoWallet> _realWallet(
  _Client client,
  Directory directory, {
  String colored = _coloredKey,
  RlnOperationTimeoutPolicy operationTimeouts =
      const RlnOperationTimeoutPolicy(),
}) async {
  await directory.create(recursive: true);
  await Directory('${directory.path}/durable-onchain-v1').create();
  when(
    () => client.createNode(
      storageDirPath: any(named: 'storageDirPath'),
      daemonListeningPort: any(named: 'daemonListeningPort'),
      ldkPeerListeningPort: any(named: 'ldkPeerListeningPort'),
      network: any(named: 'network'),
      maxMediaUploadSizeMb: any(named: 'maxMediaUploadSizeMb'),
      enableVirtualChannelsV0: any(named: 'enableVirtualChannelsV0'),
      virtualPeerPubkeys: any(named: 'virtualPeerPubkeys'),
      vssUrl: any(named: 'vssUrl'),
      vssAllowHttp: any(named: 'vssAllowHttp'),
      vssAllowEmptyRestore: any(named: 'vssAllowEmptyRestore'),
      lspBaseUrl: any(named: 'lspBaseUrl'),
      lspBearerToken: any(named: 'lspBearerToken'),
      reuseAddresses: any(named: 'reuseAddresses'),
    ),
  ).thenAnswer((_) async => 1);
  when(
    () => client.initNode(
      nodeId: any(named: 'nodeId'),
      password: any(named: 'password'),
      mnemonic: any(named: 'mnemonic'),
    ),
  ).thenAnswer((_) async => 'unused-fixture-mnemonic');
  when(
    () => client.unlockNode(
      nodeId: any(named: 'nodeId'),
      password: any(named: 'password'),
      bitcoindRpcUsername: any(named: 'bitcoindRpcUsername'),
      bitcoindRpcPassword: any(named: 'bitcoindRpcPassword'),
      bitcoindRpcHost: any(named: 'bitcoindRpcHost'),
      bitcoindRpcPort: any(named: 'bitcoindRpcPort'),
      indexerUrl: any(named: 'indexerUrl'),
      proxyEndpoint: any(named: 'proxyEndpoint'),
      announceAddresses: any(named: 'announceAddresses'),
      announceAlias: any(named: 'announceAlias'),
      gossipRgsServerUrl: any(named: 'gossipRgsServerUrl'),
      ethRpcUrl: any(named: 'ethRpcUrl'),
    ),
  ).thenAnswer((_) async {});
  when(() => client.nodeInfo(any())).thenAnswer(
    (_) async => <Object?, Object?>{
      'pubkey': 'unchanged-node-public-key',
      'numChannels': 0,
      'numUsableChannels': 0,
      'localBalanceSat': 0,
      'numPeers': 0,
      'accountXpubVanilla': _vanillaKey,
      'accountXpubColored': colored,
    },
  );
  when(() => client.shutdown(any())).thenAnswer((_) async {});
  when(() => client.destroyNode(any())).thenAnswer((_) async {});
  final wallet = createAdvancedUtexoWallet(
    config: UtexoWalletConfig(storageDirPath: directory.path),
    client: client,
    operationTimeouts: operationTimeouts,
  );
  await wallet.init(password: 'test-fixture-password');
  await wallet.unlock(
    password: 'test-fixture-password',
    config: UtexoUnlockConfig(),
  );
  addTearDown(wallet.dispose);
  return wallet;
}

void _noOutboxOrSend(_Client client) {
  verifyNever(
    () => client.prepareOnchainSend(
      nodeId: any(named: 'nodeId'),
      requestJson: any(named: 'requestJson'),
    ),
  );
  verifyNever(
    () => client.commitOnchainSend(
      nodeId: any(named: 'nodeId'),
      requestJson: any(named: 'requestJson'),
    ),
  );
  verifyNever(
    () => client.onchainSendStatus(
      nodeId: any(named: 'nodeId'),
      requestJson: any(named: 'requestJson'),
    ),
  );
  verifyNever(
    () => client.cancelOnchainSend(
      nodeId: any(named: 'nodeId'),
      requestJson: any(named: 'requestJson'),
    ),
  );
  verifyNever(
    () => client.sendBtc(
      nodeId: any(named: 'nodeId'),
      amount: any(named: 'amount'),
      address: any(named: 'address'),
      feeRate: any(named: 'feeRate'),
      skipSync: any(named: 'skipSync'),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_document());
    registerFallbackValue(UtexoUnlockConfig());
    registerFallbackValue(const RgbSendRequest(invoice: 'fallback', amount: 1));
  });

  for (final phase in ['prepare', 'commit']) {
    test(
      '$phase deadline requires owner reopen even after exact accepted inspection',
      () async {
        final wallet = _Wallet();
        final engine = _engine(wallet);
        const timeout = RlnOperationTimeoutException(
          operation: 'fixture',
          timeout: Duration(milliseconds: 1),
        );
        if (phase == 'prepare') {
          when(() => wallet.prepareOnchainSend(any())).thenThrow(timeout);
        } else {
          when(() => wallet.commitOnchainSend(any())).thenThrow(timeout);
        }
        final action = phase == 'prepare'
            ? engine.preparePaymentOperation
            : engine.commitPaymentOperation;
        await expectLater(
          action(_document().requestJson),
          throwsA(same(timeout)),
        );
        expect(engine.requiresPaymentReopen, isTrue);
        when(() => wallet.onchainSendStatus(any())).thenAnswer(
          (_) async => _status(
            RecoverableOnchainSendPhase.accepted,
            endAuthorized: true,
            txid: _txid,
          ),
        );
        expect(
          (await engine.inspectPaymentOperation(_document().requestJson)).phase,
          WalletPaymentRecoveryPhase.accepted,
        );
        expect(engine.requiresPaymentReopen, isTrue);
        when(
          () => wallet.reinit(
            password: any(named: 'password'),
            unlockConfig: any(named: 'unlockConfig'),
          ),
        ).thenThrow(StateError('Reopen unavailable'));
        await expectLater(
          engine.openPersisted(databasePassword: 'fixture-password'),
          throwsStateError,
        );
        expect(engine.requiresPaymentReopen, isTrue);
        when(
          () => wallet.reinit(
            password: any(named: 'password'),
            unlockConfig: any(named: 'unlockConfig'),
          ),
        ).thenAnswer((_) async {});
        await engine.openPersisted(databasePassword: 'fixture-password');
        expect(engine.requiresPaymentReopen, isFalse);
        verify(() => wallet.onchainSendStatus(any())).called(1);
        verifyNever(
          () => wallet.sendBtc(
            amount: any(named: 'amount'),
            address: any(named: 'address'),
            feeRate: any(named: 'feeRate'),
          ),
        );
      },
    );
  }

  test(
    'fresh Bitcoin request verifies protocol before returning journal bytes',
    () async {
      final wallet = _Wallet();
      final command = _document();
      _bitcoinFactory(wallet, command);
      when(() => wallet.onchainSendStatus(any()))
          .thenAnswer((_) async => _status(RecoverableOnchainSendPhase.absent));

      expect(
        await _engine(wallet).paymentOperationRequest(_id, _intent()),
        command.requestJson,
      );
      verifyInOrder([
        () => wallet.createRecoverableBtcSendCommand(
          operationId: _id,
          amount: 1000,
          address: _address,
          feeRate: 3,
        ),
        () => wallet.onchainSendStatus(command),
      ]);
      _noMutation(wallet);
    },
  );

  test('old native unsupported fails preflight without prepare or one-shot fallback', () async {
    final wallet = _Wallet();
    _bitcoinFactory(wallet, _document());
    const unsupported = UnsupportedWalletFeatureException(
      'Unavailable native protocol.',
      feature: 'recoverableOnchainSend',
    );
    when(() => wallet.onchainSendStatus(any())).thenThrow(unsupported);
    await expectLater(
      _engine(wallet).paymentOperationRequest(_id, _intent()),
      throwsA(same(unsupported)),
    );
    _noMutation(wallet);
  });

  for (final phase in RecoverableOnchainSendPhase.values.where(
    (value) => value != RecoverableOnchainSendPhase.absent,
  )) {
    test(
      'existing native ${phase.name} identity cannot be reused for a fresh intent',
      () async {
        final wallet = _Wallet();
        _bitcoinFactory(wallet, _document());
        when(() => wallet.onchainSendStatus(any()))
            .thenAnswer((_) async => _status(phase));
        await expectLater(
          _engine(wallet).paymentOperationRequest(_id, _intent()),
          throwsA(isA<WalletValidationException>()),
        );
        _noMutation(wallet);
      },
    );
  }

  test(
    'stale fee and disabled rail fail before SDK command or status preflight',
    () async {
      final wallet = _Wallet();
      final engine = _engine(wallet);
      await expectLater(
        engine.paymentOperationRequest(
          _id,
          _intent(reviewedAt: _now.subtract(const Duration(minutes: 3))),
        ),
        throwsA(isA<AppFailureException>()),
      );
      await expectLater(
        engine.paymentOperationRequest(
          _id,
          WalletSendCommand(
            route: const PaymentRoute(
              asset: WalletAsset.bitcoin,
              rail: PaymentRail.lightning,
            ),
            destination: 'ln-fixture',
            amount: WalletAmount.lightning(
              assetId: WalletAsset.bitcoin.id,
              units: 1000,
            ),
          ),
        ),
        throwsA(isA<UnsupportedWalletFeatureException>()),
      );
      verifyZeroInteractions(wallet);
    },
  );

  test(
    'past Bitcoin fee review does not prevent exact saved-intent validation',
    () async {
      final wallet = _Wallet();
      final document = _document();
      _bitcoinFactory(wallet, document);
      await _engine(wallet).validatePaymentOperationRequest(
        document.requestJson,
        _id,
        _intent(reviewedAt: _now.subtract(const Duration(days: 1))),
      );
      verifyNever(() => wallet.onchainSendStatus(any()));
      _noMutation(wallet);
    },
  );

  test(
    'unpublished SDK envelope v1 is never silently migrated to v2',
    () async {
      final wallet = _Wallet();
      final legacy = _document(version: 1);
      _bitcoinFactory(wallet, _document());
      await expectLater(
        _engine(
          wallet,
        ).validatePaymentOperationRequest(legacy.requestJson, _id, _intent()),
        throwsA(isA<NativeProtocolException>()),
      );
      verifyNever(() => wallet.onchainSendStatus(any()));
      _noMutation(wallet);
    },
  );

  test(
    'same account keys retain exact intent after coherent directory relocation',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aster-wallet-relocation-',
      );
      addTearDown(() => root.delete(recursive: true));
      final originalDirectory = Directory('${root.path}/original');
      final firstClient = _Client();
      final first = await _realWallet(firstClient, originalDirectory);
      final saved = await first.createRecoverableBtcSendCommand(
        operationId: _id,
        amount: 1000,
        address: _address,
        feeRate: 3,
      );
      expect(saved.version, 2);
      expect(saved.storageDirPath, isNull);
      expect(saved.requestJson, isNot(contains(originalDirectory.path)));
      await first.dispose();
      final relocatedDirectory = await originalDirectory.rename(
        '${root.path}/relocated',
      );
      final reopenedClient = _Client();
      final reopened = await _realWallet(reopenedClient, relocatedDirectory);

      await _engine(reopened)
          .validatePaymentOperationRequest(saved.requestJson, _id, _intent());
      final expected = await reopened.createRecoverableBtcSendCommand(
        operationId: _id,
        amount: 1000,
        address: _address,
        feeRate: 3,
      );
      expect(expected.requestJson, saved.requestJson);
      expect(expected.fingerprint, saved.fingerprint);
      verify(() => firstClient.nodeInfo(any())).called(1);
      verify(() => reopenedClient.nodeInfo(any())).called(2);
      _noOutboxOrSend(firstClient);
      _noOutboxOrSend(reopenedClient);
    },
  );

  test('one different full account key refuses restored intent before outbox access', () async {
    final root = await Directory.systemTemp.createTemp(
      'aster-wallet-identity-',
    );
    addTearDown(() => root.delete(recursive: true));
    final firstClient = _Client();
    final first = await _realWallet(
      firstClient,
      Directory('${root.path}/first'),
    );
    final saved = await first.createRecoverableBtcSendCommand(
      operationId: _id,
      amount: 1000,
      address: _address,
      feeRate: 3,
    );
    final otherClient = _Client();
    final other = await _realWallet(
      otherClient,
      Directory('${root.path}/other'),
      colored: '$_coloredKey-different',
    );
    await expectLater(
      _engine(other)
          .validatePaymentOperationRequest(saved.requestJson, _id, _intent()),
      throwsA(isA<NativeProtocolException>()),
    );
    verify(() => otherClient.nodeInfo(any())).called(1);
    _noOutboxOrSend(firstClient);
    _noOutboxOrSend(otherClient);
  });

  for (final replacement in [
    _document(amount: 1001),
    _document(operationId: '1123456789abcdef0123456789abcdef'),
    _document(walletBinding: _walletBinding(colored: 'different-colored-key')),
    _document(network: 'signet'),
  ]) {
    test(
      'restored command cannot silently change its exact SDK wallet-bound inputs ${replacement.fingerprint}',
      () async {
        final wallet = _Wallet();
        _bitcoinFactory(wallet, _document());
        await expectLater(
          _engine(wallet).validatePaymentOperationRequest(
            replacement.requestJson,
            _id,
            _intent(),
          ),
          throwsA(isA<NativeProtocolException>()),
        );
        _noMutation(wallet);
      },
    );
  }

  test('real SDK RGB deadline permits exact invoice revalidation and status without lifting quarantine', () async {
    final root = await Directory.systemTemp.createTemp(
      'aster-rgb-timeout-validation-',
    );
    addTearDown(() => root.delete(recursive: true));
    final client = _Client();
    when(
      () => client.decodeRgbInvoice(
        nodeId: any(named: 'nodeId'),
        invoice: any(named: 'invoice'),
      ),
    ).thenAnswer((invocation) async {
      final invoice = invocation.namedArguments[#invoice] as String;
      return <Object?, Object?>{
        'recipientId': invoice == 'rgb:fixture-invoice'
            ? 'recipient-fixture'
            : 'different-recipient',
        'proxyRecipientId': 'proxy-fixture',
        'recipientType': 'Blind',
        'assetId': _assetId,
        'assignment': '1000',
        'network': 'regtest',
        'expirationTimestamp': 4102444800,
        'transportEndpoints': <String>['rpc://127.0.0.1:29300/json-rpc'],
      };
    });
    final wallet = await _realWallet(
      client,
      Directory('${root.path}/wallet'),
      operationTimeouts: const RlnOperationTimeoutPolicy(
        sendTimeout: Duration(milliseconds: 30),
      ),
    );
    final intent = _intent(rgb: true);
    final saved = await wallet.createRecoverableRgbSendCommand(
      operationId: _id,
      request: const RgbSendRequest(
        invoice: 'rgb:fixture-invoice',
        assetId: _assetId,
        amount: 1000,
        feeRate: 3,
      ),
    );
    final accepted = jsonEncode(<String, Object?>{
      'version': 1,
      'operationId': saved.operationId,
      'fingerprint': saved.fingerprint,
      'kind': 'rgb',
      'phase': 'accepted',
      'txid': _txid,
      'batchTransferIndex': 12,
      'failureCode': null,
      'endAuthorized': true,
    });
    final gate = Completer<void>();
    when(
      () => client.commitOnchainSend(
        nodeId: any(named: 'nodeId'),
        requestJson: any(named: 'requestJson'),
      ),
    ).thenAnswer((_) async {
      await gate.future;
      return accepted;
    });
    when(
      () => client.onchainSendStatus(
        nodeId: any(named: 'nodeId'),
        requestJson: any(named: 'requestJson'),
      ),
    ).thenAnswer((_) async => accepted);
    final engine = _engine(wallet);
    await expectLater(
      engine.commitPaymentOperation(saved.requestJson),
      throwsA(isA<RlnOperationTimeoutException>()),
    );
    expect(engine.requiresPaymentReopen, isTrue);
    gate.complete();
    await engine.validatePaymentOperationRequest(
      saved.requestJson,
      _id,
      intent,
    );
    expect(
      (await engine.inspectPaymentOperation(saved.requestJson)).phase,
      WalletPaymentRecoveryPhase.accepted,
    );
    // A different complete invoice cannot be accepted as the original intent,
    // even while pure decoding is allowed behind the timed-out native call.
    final different = WalletSendCommand(
      route: intent.route,
      destination: 'rgb:different-invoice',
      amount: intent.amount,
      feeRate: intent.feeRate,
      rgbRecipientType: RgbRecipientType.blind,
    );
    await expectLater(
      engine.validatePaymentOperationRequest(saved.requestJson, _id, different),
      throwsA(isA<NativeProtocolException>()),
    );
    await expectLater(wallet.syncWallet(), throwsA(isA<WalletError>()));
    expect(engine.requiresPaymentReopen, isTrue);
    verify(
      () => client.commitOnchainSend(
        nodeId: any(named: 'nodeId'),
        requestJson: any(named: 'requestJson'),
      ),
    ).called(1);
    verifyNever(
      () => client.prepareOnchainSend(
        nodeId: any(named: 'nodeId'),
        requestJson: any(named: 'requestJson'),
      ),
    );
    verifyNever(
      () => client.cancelOnchainSend(
        nodeId: any(named: 'nodeId'),
        requestJson: any(named: 'requestJson'),
      ),
    );
  });

  test('timeless RGB restore retains saved deadline and inspection forwards original bytes', () async {
    final wallet = _Wallet();
    final saved = _document(rgb: true, expiry: 1);
    final newlyDerived = _document(rgb: true, expiry: 4102444800);
    _invoice(wallet, expiry: null);
    _rgbFactory(wallet, newlyDerived);
    when(() => wallet.onchainSendStatus(any())).thenAnswer(
      (_) async =>
          _status(RecoverableOnchainSendPhase.prepared, txid: _txid, batch: 12),
    );
    final engine = _engine(wallet);
    await engine.validatePaymentOperationRequest(
      saved.requestJson,
      _id,
      _intent(rgb: true, reviewedAt: _now.subtract(const Duration(days: 1))),
    );
    final status = await engine.inspectPaymentOperation(saved.requestJson);
    expect(status.phase, WalletPaymentRecoveryPhase.prepared);
    final inspected =
        verify(() => wallet.onchainSendStatus(captureAny())).captured.single
            as RecoverableOnchainSendCommand;
    expect(inspected.requestJson, saved.requestJson);
    _noMutation(wallet);
  });

  test(
    'explicit RGB invoice expiry cannot be ignored during restore',
    () async {
      final wallet = _Wallet();
      _invoice(wallet);
      _rgbFactory(wallet, _document(rgb: true));
      await expectLater(
        _engine(wallet).validatePaymentOperationRequest(
          _document(rgb: true, expiry: 1).requestJson,
          _id,
          _intent(rgb: true),
        ),
        throwsA(isA<NativeProtocolException>()),
      );
      _noMutation(wallet);
    },
  );

  test(
    'changed RGB recipient kind is rejected before SDK native preparation',
    () async {
      final wallet = _Wallet();
      _invoice(wallet, kind: 'Witness');
      await expectLater(
        _engine(wallet).paymentOperationRequest(_id, _intent(rgb: true)),
        throwsA(isA<WalletValidationException>()),
      );
      verifyNever(
        () => wallet.createRecoverableRgbSendCommand(
          operationId: any(named: 'operationId'),
          request: any(named: 'request'),
        ),
      );
      verifyNever(() => wallet.onchainSendStatus(any()));
      _noMutation(wallet);
    },
  );

  test('all recovery actions preserve original document and native phase semantics', () async {
    final wallet = _Wallet();
    final document = _document(rgb: true, expiry: 1);
    when(() => wallet.prepareOnchainSend(any())).thenAnswer(
      (_) async =>
          _status(RecoverableOnchainSendPhase.prepared, txid: _txid, batch: 12),
    );
    when(() => wallet.commitOnchainSend(any())).thenAnswer(
      (_) async => _status(
        RecoverableOnchainSendPhase.accepted,
        endAuthorized: true,
        txid: _txid,
        batch: 99,
      ),
    );
    when(() => wallet.onchainSendStatus(any())).thenAnswer(
      (_) async => _status(
        RecoverableOnchainSendPhase.committing,
        endAuthorized: true,
        txid: _txid,
        batch: 12,
      ),
    );
    when(() => wallet.cancelOnchainSend(any()))
        .thenAnswer((_) async => _status(RecoverableOnchainSendPhase.rejected));
    final engine = _engine(wallet);
    final prepared = await engine.preparePaymentOperation(document.requestJson);
    expect(prepared.phase, WalletPaymentRecoveryPhase.prepared);
    expect(prepared.endAuthorized, isFalse);
    final accepted = await engine.commitPaymentOperation(document.requestJson);
    expect(accepted.phase, WalletPaymentRecoveryPhase.accepted);
    expect(accepted.batchTransferIndex, 99);
    final committing = await engine.inspectPaymentOperation(
      document.requestJson,
    );
    expect(committing.phase, WalletPaymentRecoveryPhase.committing);
    expect(committing.endAuthorized, isTrue);
    final rejected = await engine.cancelPaymentOperation(document.requestJson);
    expect(rejected.phase, WalletPaymentRecoveryPhase.rejected);
    expect(rejected.endAuthorized, isFalse);
    final calls = [
      verify(() => wallet.prepareOnchainSend(captureAny())).captured.single,
      verify(() => wallet.commitOnchainSend(captureAny())).captured.single,
      verify(() => wallet.onchainSendStatus(captureAny())).captured.single,
      verify(() => wallet.cancelOnchainSend(captureAny())).captured.single,
    ];
    for (final call in calls.cast<RecoverableOnchainSendCommand>()) {
      expect(call.requestJson, document.requestJson);
    }
    verifyNever(() => wallet.onchainSend(any()));
  });

  test(
    'expired prepared native response remains held and carries its typed code',
    () async {
      final wallet = _Wallet();
      final document = _document(rgb: true, expiry: 1);
      when(() => wallet.commitOnchainSend(any())).thenAnswer(
        (_) async => _status(
          RecoverableOnchainSendPhase.prepared,
          txid: _txid,
          batch: 12,
          failureCode: 'invoice_expired',
        ),
      );

      final status = await _engine(wallet)
          .commitPaymentOperation(document.requestJson);

      expect(status.phase, WalletPaymentRecoveryPhase.prepared);
      expect(status.endAuthorized, isFalse);
      expect(status.referenceId, _txid);
      expect(status.batchTransferIndex, 12);
      expect(status.failureCode, 'invoice_expired');
      verifyNever(() => wallet.cancelOnchainSend(any()));
      verifyNever(() => wallet.prepareOnchainSend(any()));
      verifyNever(() => wallet.onchainSend(any()));
    },
  );

  test('malformed saved command cannot invoke any SDK operation', () async {
    final wallet = _Wallet();
    final engine = _engine(wallet);
    for (final action in [
      engine.preparePaymentOperation,
      engine.commitPaymentOperation,
      engine.inspectPaymentOperation,
      engine.cancelPaymentOperation,
    ]) {
      await expectLater(
        action('{broken'),
        throwsA(isA<WalletValidationException>()),
      );
    }
    verifyZeroInteractions(wallet);
  });

  test('native validation-shaped failure remains an error rather than a rejection certificate', () async {
    final wallet = _Wallet();
    const uncertain = WalletValidationException(
      'Native outcome remains unresolved.',
      field: 'operation',
    );
    when(() => wallet.prepareOnchainSend(any())).thenThrow(uncertain);
    await expectLater(
      _engine(wallet).preparePaymentOperation(_document().requestJson),
      throwsA(same(uncertain)),
    );
    verifyNever(() => wallet.commitOnchainSend(any()));
    verifyNever(() => wallet.cancelOnchainSend(any()));
  });
}
