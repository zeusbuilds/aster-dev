import 'package:aster/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rejects unknown blockchain environments with typed configuration error',
    () {
      expect(
        () => BlockchainEnvironment.parse('production-ish'),
        throwsA(isA<AppConfigurationException>()),
      );
    },
  );

  test('rejects insecure non-loopback service endpoints', () {
    const configuration = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      indexerUrl: 'http://example.com',
    );

    expect(configuration.validate, throwsA(isA<AppConfigurationException>()));
  });

  test('allows plain HTTP only for explicit loopback development services', () {
    const configuration = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      indexerUrl: 'http://127.0.0.1:50002',
      rgbTransportProxy: 'http://localhost:3001',
    );

    expect(configuration.validate, returnsNormally);
  });

  test('rejects insecure loopback endpoints outside regtest', () {
    const mainnet = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      lspBaseUrl: 'http://localhost:3100',
    );
    const signet = WalletServiceConfiguration(
      environment: BlockchainEnvironment.signet,
      sdkNetwork: 'utexo',
      indexerUrl: 'tcp://127.0.0.1:50001',
    );

    expect(mainnet.validate, throwsA(isA<AppConfigurationException>()));
    expect(signet.validate, throwsA(isA<AppConfigurationException>()));
  });

  test('enables SDK HTTP VSS only for validated regtest hosts', () {
    const local = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      vssUrl: 'http://127.0.0.1:3200',
    );
    const secure = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      vssUrl: 'https://vss.example.com',
    );

    expect(local.validate, returnsNormally);
    expect(local.allowsInsecureLocalVss, isTrue);
    expect(secure.validate, returnsNormally);
    expect(secure.allowsInsecureLocalVss, isFalse);
  });

  test('allows the Android emulator host gateway only on regtest', () {
    const regtest = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      lspBaseUrl: 'http://10.0.2.2:3100',
    );
    const mainnet = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      lspBaseUrl: 'http://10.0.2.2:3100',
    );

    expect(regtest.validate, returnsNormally);
    expect(mainnet.validate, throwsA(isA<AppConfigurationException>()));
  });

  test('rejects every host port reserved by the protected regtest stack', () {
    for (final endpoint in [
      'tcp://127.0.0.1:50001',
      'http://localhost:3000',
      'http://10.0.2.2:18443',
    ]) {
      expect(
        () => WalletServiceConfiguration(
          environment: BlockchainEnvironment.regtest,
          sdkNetwork: 'regtest',
          indexerUrl: endpoint,
        ).validate(),
        throwsA(isA<AppConfigurationException>()),
        reason: endpoint,
      );
    }
  });

  test('accepts the SDK local and secure Electrum endpoint forms', () {
    const local = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      indexerUrl: '127.0.0.1:50002',
      rgbTransportProxy: 'rpc://127.0.0.1:3001/json-rpc',
    );
    const secure = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      indexerUrl: 'ssl://electrum.example.com:50002',
      rgbTransportProxy: 'rpcs://proxy.example.com/json-rpc',
      lspBaseUrl: 'https://lsp.example.com',
    );

    expect(local.validate, returnsNormally);
    expect(secure.validate, returnsNormally);
  });

  test('rejects credentials and unsupported endpoint transports', () {
    const credentials = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      lspBaseUrl: 'https://token@example.com',
    );
    const unsupported = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      vssUrl: 'ftp://127.0.0.1:8080',
    );
    const queryCredential = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      lspBaseUrl: 'https://lsp.example.com?token=secret',
    );
    const padded = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      vssUrl: ' https://vss.example.com',
    );
    const embeddedWhitespace = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      vssUrl: 'https://vss.example.com/a path',
    );
    const invalidPort = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      vssUrl: 'https://vss.example.com:65536',
    );

    expect(credentials.validate, throwsA(isA<AppConfigurationException>()));
    expect(unsupported.validate, throwsA(isA<AppConfigurationException>()));
    expect(queryCredential.validate, throwsA(isA<AppConfigurationException>()));
    expect(padded.validate, throwsA(isA<AppConfigurationException>()));
    expect(
      embeddedWhitespace.validate,
      throwsA(isA<AppConfigurationException>()),
    );
    expect(invalidPort.validate, throwsA(isA<AppConfigurationException>()));
  });

  test('rejects an SDK network that disagrees with the app environment', () {
    const configuration = WalletServiceConfiguration(
      environment: BlockchainEnvironment.signet,
      sdkNetwork: 'signet',
    );

    expect(configuration.validate, throwsA(isA<AppConfigurationException>()));
  });

  test('accepts a complete deployment-owned RGB asset identity', () {
    const configuration = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      usdtAsset: RgbAssetConfiguration(
        contractId: 'rgb:usdt-contract',
        precision: 6,
      ),
    );

    expect(configuration.validate, returnsNormally);
  });

  test('rejects malformed RGB asset identity and precision', () {
    const malformedId = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      usdtAsset: RgbAssetConfiguration(
        contractId: 'rgb:usdt contract',
        precision: 6,
      ),
    );
    const malformedPrecision = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      usdtAsset: RgbAssetConfiguration(
        contractId: 'rgb:usdt-contract',
        precision: 19,
      ),
    );

    expect(malformedId.validate, throwsA(isA<AppConfigurationException>()));
    expect(
      malformedPrecision.validate,
      throwsA(isA<AppConfigurationException>()),
    );
  });

  test('builds only validated public transaction explorer links', () {
    const mainnet = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      explorerBaseUrl: 'https://mempool.space',
    );
    const signet = WalletServiceConfiguration(
      environment: BlockchainEnvironment.signet,
      sdkNetwork: 'utexo',
      explorerBaseUrl: 'https://mempool.space/signet',
    );
    const regtest = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
    );
    final txid = 'A' * 64;

    expect(mainnet.validate, returnsNormally);
    expect(signet.validate, returnsNormally);
    expect(
      mainnet.transactionExplorerUri(txid).toString(),
      'https://mempool.space/tx/${'a' * 64}',
    );
    expect(
      signet.transactionExplorerUri(txid).toString(),
      'https://mempool.space/signet/tx/${'a' * 64}',
    );
    expect(regtest.transactionExplorerUri(txid), isNull);
    expect(mainnet.transactionExplorerUri('not-a-txid'), isNull);
  });

  test('rejects insecure or credential-bearing explorer bases', () {
    const insecure = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      explorerBaseUrl: 'http://127.0.0.1:4000',
    );
    const credential = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      explorerBaseUrl: 'https://token@mempool.example',
    );

    expect(insecure.validate, throwsA(isA<AppConfigurationException>()));
    expect(credential.validate, throwsA(isA<AppConfigurationException>()));
  });
}
