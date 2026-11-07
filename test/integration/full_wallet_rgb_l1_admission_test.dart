import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/full_wallet_qa.dart';
import '../../integration_test/support/full_wallet_rgb_l1.dart';

void main() {
  WalletServiceConfiguration candidate({
    WalletBackend backend = WalletBackend.rgbL1,
    BlockchainEnvironment environment = BlockchainEnvironment.regtest,
    SignetDeployment deployment = SignetDeployment.publicBitcoin,
    String? indexer = 'http://127.0.0.1:49794',
    String? proxy = 'rpc://127.0.0.1:49790/json-rpc',
    String? evm,
    String? lsp,
    String? vss,
    RgbAssetConfiguration? asset,
  }) => WalletServiceConfiguration(
    backend: backend,
    environment: environment,
    sdkNetwork: environment == BlockchainEnvironment.signet
        ? 'signet'
        : environment.name,
    signetDeployment: deployment,
    indexerUrl: indexer,
    rgbTransportProxy: proxy,
    ethRpcUrl: evm,
    ethChainId: evm == null ? null : '31337',
    bfaMintLockPolicy: evm == null
        ? null
        : BfaMintLockPolicy(minimumBlocks: 2, maximumBlocks: 512),
    lspBaseUrl: lsp,
    vssUrl: vss,
    usdtAsset: asset,
  );

  final bytes = utf8.encode('public contract admission fixture');
  final asset = RgbAssetConfiguration(
    contractId: 'rgb:qualification-asset',
    precision: 6,
    canonicalContract: RgbContractConfiguration(
      contractBase64: base64Encode(bytes),
      sha256Digest: sha256.convert(bytes).toString(),
      nativeName: 'Qualification Asset',
      nativeTicker: 'QBFA',
    ),
  );

  test(
    'internal lifecycle admits BTC-only loopback without enabling product',
    () {
      final services = candidate();
      expect(requireLocalRgbL1Services(services), same(services));
      expect(WalletBackend.rgbL1.activationAllowed, isFalse);
    },
  );

  test('funded RGB campaign requires a canonical contract and EVM policy', () {
    expect(
      () => requireLocalRgbL1Services(candidate(), requireUsdt: true),
      throwsA(isA<FullWalletQaFailure>()),
    );
    expect(
      () =>
          requireLocalRgbL1Services(candidate(asset: asset), requireUsdt: true),
      throwsA(isA<AppConfigurationException>()),
    );
    final services = candidate(asset: asset, evm: 'http://localhost:49745');
    expect(
      requireLocalRgbL1Services(services, requireUsdt: true),
      same(services),
    );
  });

  test('entrypoint rejects public, Dev, legacy and incompatible VSS/LSP', () {
    for (final services in [
      candidate(environment: BlockchainEnvironment.mainnet),
      candidate(environment: BlockchainEnvironment.signet),
      candidate(deployment: SignetDeployment.utexoDev),
      candidate(backend: WalletBackend.rln),
      candidate(indexer: null),
      candidate(proxy: null),
      candidate(lsp: 'http://localhost:49780'),
      candidate(vss: 'http://localhost:49781'),
    ]) {
      expect(
        () => requireLocalRgbL1Services(services),
        throwsA(isA<FullWalletQaFailure>()),
      );
    }
  });

  test('every native service must use explicit loopback, including EVM', () {
    for (final services in [
      candidate(indexer: 'http://10.0.2.2:49794'),
      candidate(proxy: 'rpc://10.0.2.2:49790/json-rpc'),
      candidate(evm: 'http://10.0.2.2:49745'),
      candidate(indexer: 'https://public-indexer.example.com'),
      candidate(proxy: 'rpcs://public-proxy.example.com/json-rpc'),
      candidate(evm: 'https://public-evm.example.com'),
    ]) {
      expect(
        () => requireLocalRgbL1Services(services),
        throwsA(
          isA<FullWalletQaFailure>().having(
            (value) => value.code,
            'code',
            'qa_local_l1_loopback_required',
          ),
        ),
      );
    }
  });
}
