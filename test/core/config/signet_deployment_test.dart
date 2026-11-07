import 'dart:convert';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('USDT validation defaults fail closed for BFA and public preset is BTC only', () {
    const asset = RgbAssetConfiguration(
      contractId: 'rgb:approved',
      precision: 6,
    );
    expect(asset.requiresEvmValidation, isTrue);
    final values = jsonDecode(
      File('config/signet-public.debug.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(values['ASTER_NETWORK'], 'signet');
    expect(values['ASTER_SIGNET_DEPLOYMENT'], 'public');
    expect(values['ASTER_WALLET_BACKEND'], 'rln');
    expect(values['ASTER_DAEMON_PORT'], '19775');
    expect(values['ASTER_LDK_PEER_PORT'], '19776');
    expect(
      values.keys.where(
        (key) =>
            key.startsWith('ASTER_USDT') ||
            key.startsWith('ASTER_ETH') ||
            key == 'ASTER_VSS_URL',
      ),
      isEmpty,
    );
  });
  test('Signet deployment values are explicit and canonical', () {
    expect(SignetDeployment.parse('public'), SignetDeployment.publicBitcoin);
    expect(SignetDeployment.parse('dev-signet'), SignetDeployment.utexoDev);
    for (final invalid in ['', 'utexo', 'dev', 'signet', 'Public', ' public']) {
      expect(() => SignetDeployment.parse(invalid), throwsFormatException);
    }
  });

  test('public Signet Bitcoin-only remains usable', () {
    const public = WalletServiceConfiguration(
      environment: BlockchainEnvironment.signet,
      sdkNetwork: 'utexo',
      indexerUrl: 'https://mempool.space/signet/api',
      rgbTransportProxy: 'rpcs://proxy.iriswallet.com/0.2/json-rpc',
      explorerBaseUrl: 'https://mempool.space/signet',
    );
    expect(public.validate, returnsNormally);
    expect(public.usdtAsset, isNull);
    expect(public.signetDeployment, SignetDeployment.publicBitcoin);
  });

  test('Dev remains blocked for every network and backend combination', () {
    for (final network in BlockchainEnvironment.values) {
      for (final backend in WalletBackend.values) {
        final configuration = WalletServiceConfiguration(
          environment: network,
          sdkNetwork: backend.sdkNetwork(network),
          backend: backend,
          signetDeployment: SignetDeployment.utexoDev,
        );
        expect(
          configuration.validate,
          throwsA(isA<AppConfigurationException>()),
          reason: '${network.name}/${backend.wireName}',
        );
      }
    }
  });

  test('known current and historical Dev assets cannot bypass the profile', () {
    for (final id in UtexoDevSignetPolicy.quarantinedAssetIds) {
      for (final network in BlockchainEnvironment.values) {
        final configuration = WalletServiceConfiguration(
          environment: network,
          sdkNetwork: WalletBackend.rln.sdkNetwork(network),
          ethRpcUrl: 'https://arb1.arbitrum.io/rpc',
          ethChainId: '42161',
          usdtAsset: RgbAssetConfiguration(contractId: id, precision: 6),
        );
        expect(
          configuration.validate,
          throwsA(isA<AppConfigurationException>()),
        );
      }
    }
  });

  test('known Dev services cannot be mixed into public service slots', () {
    for (final host in UtexoDevSignetPolicy.quarantinedHosts) {
      for (final configuration in [
        WalletServiceConfiguration(
          environment: BlockchainEnvironment.signet,
          sdkNetwork: 'utexo',
          indexerUrl: 'https://${host.toUpperCase()}/other-path',
        ),
        WalletServiceConfiguration(
          environment: BlockchainEnvironment.signet,
          sdkNetwork: 'utexo',
          rgbTransportProxy: 'rpcs://$host:443/json-rpc',
        ),
        WalletServiceConfiguration(
          environment: BlockchainEnvironment.mainnet,
          sdkNetwork: 'mainnet',
          vssUrl: 'https://$host',
        ),
        WalletServiceConfiguration(
          environment: BlockchainEnvironment.regtest,
          sdkNetwork: 'regtest',
          ethRpcUrl: 'https://$host',
        ),
      ]) {
        expect(
          configuration.validate,
          throwsA(isA<AppConfigurationException>()),
        );
      }
    }
    expect(
      UtexoDevSignetPolicy.isQuarantinedEndpoint(
        'https://dev.rgb-proxy.utexo.com.evil.example/json-rpc',
      ),
      isFalse,
    );
  });

  test(
    'BFA requires EVM identity on every network; generic regtest does not',
    () {
      for (final network in BlockchainEnvironment.values) {
        WalletServiceConfiguration configuration({
          String? rpc,
          String? chain,
        }) => WalletServiceConfiguration(
          environment: network,
          sdkNetwork: WalletBackend.rln.sdkNetwork(network),
          usdtAsset: const RgbAssetConfiguration(
            contractId: 'rgb:approved-fixture',
            precision: 6,
            requiresEvmValidation: true,
          ),
          ethRpcUrl: rpc,
          ethChainId: chain,
        );
        for (final invalid in [
          configuration(),
          configuration(rpc: 'https://rpc.example.com'),
          configuration(chain: '42161'),
        ]) {
          expect(invalid.validate, throwsA(isA<AppConfigurationException>()));
        }
        expect(
          configuration(
            rpc: 'https://rpc.example.com',
            chain: '42161',
          ).validate,
          returnsNormally,
        );
      }
      const generic = WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        usdtAsset: RgbAssetConfiguration(
          contractId: 'rgb:generic',
          precision: 6,
          requiresEvmValidation: false,
        ),
      );
      expect(generic.validate, returnsNormally);
      expect(
        generic.usdtAsset,
        isNot(
          const RgbAssetConfiguration(
            contractId: 'rgb:generic',
            precision: 6,
            requiresEvmValidation: true,
          ),
        ),
      );
    },
  );

  test(
    'Dev evidence cannot silently admit old exports or invent precision',
    () {
      final evidence = jsonDecode(
        File('config/dev-signet.evidence.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(evidence['walletAccessEnabled'], isFalse);
      final current = evidence['currentAsset'] as Map<String, dynamic>;
      expect(current['assetId'], UtexoDevSignetPolicy.currentAssetId);
      expect(current['admitted'], isFalse);
      expect(current['precision'], isNull);
      expect(current['precisionVerified'], isFalse);
      expect(current['contractArtifact'], isNull);
      expect(current['contractSha256'], isNull);
      final historical = evidence['historicalAsset'] as Map<String, dynamic>;
      expect(historical['assetId'], UtexoDevSignetPolicy.historicalBfa5AssetId);
      expect(historical['admitted'], isFalse);
      expect(historical['compatibility'], 'historical-bfa5');
      expect(evidence['deployedRgbLib'], {
        'version': 'v0.3.0-beta.7-upstream-dev-bfa.6',
        'revision': '5010eefa355beb9c42a4c1b69883f7651241a111',
      });
      expect(evidence['irisCandidateRgbLib'], {
        'version': 'v0.3.0-beta.7-upstream-dev-bfa.7',
        'revision': '9ec49c08be2e68f08521281e3efbd760ec989cb9',
      });
    },
  );
}
