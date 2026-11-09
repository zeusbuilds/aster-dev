import 'dart:convert';
import 'dart:io';

import 'package:aster/core/config/config.dart';

Map<String, String> readDevBridgeFixture() => Map<String, String>.from(
  jsonDecode(File('config/dev-signet.debug.json').readAsStringSync()) as Map,
);

WalletServiceConfiguration devBridgeServices([
  Map<String, String?> overrides = const {},
]) {
  final values = {...readDevBridgeFixture(), ...overrides};
  final environment = BlockchainEnvironment.parse(values['ASTER_NETWORK']!);
  final backend = WalletBackend.parse(values['ASTER_WALLET_BACKEND']!);
  final deployment = SignetDeployment.parse(values['ASTER_SIGNET_DEPLOYMENT']!);
  return WalletServiceConfiguration(
    environment: environment,
    sdkNetwork: backend.sdkNetwork(environment, signetDeployment: deployment),
    backend: backend,
    signetDeployment: deployment,
    devBridgeEnabled: values[UtexoDevSignetPolicy.buildFlag] == 'true',
    indexerUrl: values['ASTER_INDEXER_URL'],
    rgbTransportProxy: values['ASTER_RGB_PROXY_URL'],
    ethChainId: values['ASTER_ETH_CHAIN_ID'],
    ethRpcUrl: values['ASTER_ETH_RPC_URL'],
    explorerBaseUrl: values['ASTER_EXPLORER_URL'],
    bfaMintLockPolicy: BfaMintLockPolicy.parse(
      values['ASTER_BFA_MIN_MINT_LOCK_BLOCKS'] ?? '',
      values['ASTER_BFA_MAX_MINT_LOCK_BLOCKS'] ?? '',
    ),
    usdtAsset: RgbAssetConfiguration(
      contractId: values['ASTER_USDT_ASSET_ID']!,
      precision: int.parse(values['ASTER_USDT_PRECISION']!),
      canonicalContract: RgbContractConfiguration(
        contractBase64: values['ASTER_USDT_CONTRACT_BASE64']!,
        sha256Digest: values['ASTER_USDT_CONTRACT_SHA256']!,
        nativeName: values['ASTER_USDT_NATIVE_NAME']!,
        nativeTicker: values['ASTER_USDT_NATIVE_TICKER']!,
      ),
    ),
  );
}
