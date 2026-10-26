import 'dart:convert';

import 'package:aster/core/config/app_environment.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter_advanced.dart';
import 'package:rgb_sdk_flutter/src/pigeon/rln_api.g.dart';

/// Native wire contract, deliberately rejecting the RLN 0.17 unsupported query
/// that a `Mock<UtexoWallet>` used to accept during the original source audit.
final class _Host extends RlnHostApi {
  final scopes = <String>[];
  bool imported = false;
  bool unassigned = false;
  bool expireUnassigned = false;
  int unfilteredCalls = 0;
  int expirySweeps = 0;

  @override
  Future<int> rlnCreateNode(
    String path,
    int daemon,
    int peer,
    String network,
    int media,
    bool? virtual,
    List<String>? pubkeys,
    String? vss,
    bool http,
    bool emptyRestore,
    String? lsp,
    String? token,
    bool reuse,
  ) async => 1;

  @override
  Future<RlnRefreshTransfersData> rlnRefreshTransfers(
    int nodeId,
    bool skipSync,
  ) async => RlnRefreshTransfersData(
    transfers: [if (unassigned) RlnRefreshedTransferData(index: 7)],
  );

  @override
  Future<RlnWireResponse> rlnListAssets(
    int nodeId,
    List<String> schemas,
  ) async => RlnWireResponse(
    json: jsonEncode({
      'nia': [
        if (imported)
          {
            'assetId': 'rgb:fixture',
            'ticker': 'USDT',
            'name': 'Fixture',
            'precision': 6,
            'timestamp': 1,
            'addedAt': 1,
            'issuedSupply': 100,
            'balance': _zero,
          },
      ],
      'bfa': <Object?>[],
      'cfa': <Object?>[],
      'ifa': <Object?>[],
      'uda': <Object?>[],
    }),
  );

  static const _zero = {
    'settled': 0,
    'future': 0,
    'spendable': 0,
    'offchainOutbound': 0,
    'offchainInbound': 0,
  };

  @override
  Future<RlnWireResponse> rlnAssetBalance(int nodeId, String assetId) async =>
      RlnWireResponse(json: jsonEncode(_zero));

  @override
  Future<List<RlnWireResponse>> rlnListTransfers(
    int nodeId,
    String assetId,
  ) async {
    if (assetId.isEmpty) {
      unfilteredCalls++;
      throw PlatformException(
        code: 'InvalidRequest',
        message: 'either asset_id or txid must be provided',
      );
    }
    scopes.add(assetId);
    return [];
  }

  @override
  Future<RlnWireResponse> rlnFailTransfers(
    int nodeId,
    int? batch,
    bool noAssetOnly,
    bool skipSync,
  ) async {
    expect(batch, isNull);
    expect(noAssetOnly, isTrue);
    expect(skipSync, isFalse);
    expirySweeps++;
    if (expireUnassigned) unassigned = false;
    return RlnWireResponse(
      json: jsonEncode({'transfersChanged': expireUnassigned}),
    );
  }
}

/// Wallet initialization stays within the fixture. The real SDK still owns
/// lifecycle, node queue, native error mapping and model conversion.
final class _Signer extends RlnSigner {
  @override
  Future<void> initNode({
    required RlnSignerHost host,
    required int nodeId,
    required String storageDirPath,
  }) async {}
  @override
  Future<void> unlockNode({
    required RlnSignerHost host,
    required int nodeId,
    required UtexoUnlockConfig config,
    required String storageDirPath,
  }) async {}
}

void main() {
  const services = WalletServiceConfiguration(
    environment: BlockchainEnvironment.regtest,
    sdkNetwork: 'regtest',
  );
  Future<(UtexoWallet, RgbWalletEngine)> fixture(_Host host) async {
    final wallet = createAdvancedUtexoWallet(
      config: UtexoWalletConfig(storageDirPath: '/public-wire-fixture'),
      client: RlnClient(hostApi: host),
      signer: _Signer(),
    );
    await wallet.init();
    await wallet.unlock(config: UtexoUnlockConfig());
    return (wallet, RgbWalletEngine(wallet, services, UtexoUnlockConfig()));
  }

  test('real SDK preserves native unfiltered rejection while fixed audit avoids it', () async {
    final host = _Host()..imported = true;
    final (wallet, engine) = await fixture(host);
    await expectLater(wallet.listTransfers(), throwsA(isA<BadRequestError>()));
    expect(host.unfilteredCalls, 1);
    expect(await engine.hasProtectedRgbState(), isFalse);
    expect(host.unfilteredCalls, 1);
    expect(host.scopes, ['rgb:fixture', 'rgb:fixture']);
  });

  test(
    'real SDK empty wallet audit never dispatches unsupported transfer scope',
    () async {
      final host = _Host();
      final (_, engine) = await fixture(host);
      expect(await engine.hasProtectedRgbState(), isFalse);
      expect(host.unfilteredCalls, 0);
      expect(host.scopes, isEmpty);
    },
  );

  test(
    'real SDK null waiting status retains unassigned receive protection',
    () async {
      final host = _Host()..unassigned = true;
      final (_, engine) = await fixture(host);
      expect(await engine.hasProtectedRgbState(), isTrue);
      expect(host.expirySweeps, 1);
      expect(host.unfilteredCalls, 0);
    },
  );

  test(
    'real SDK natively expired unassigned receive requires fresh empty map',
    () async {
      final host = _Host()
        ..unassigned = true
        ..expireUnassigned = true;
      final (_, engine) = await fixture(host);
      expect(await engine.hasProtectedRgbState(), isFalse);
      expect(host.expirySweeps, 1);
      expect(host.unfilteredCalls, 0);
    },
  );
}
