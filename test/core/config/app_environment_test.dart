import 'package:aster/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native listener ports are bounded, distinct configuration identity',
    () {
      WalletServiceConfiguration configuration(int daemon, int peer) =>
          WalletServiceConfiguration(
            environment: BlockchainEnvironment.regtest,
            sdkNetwork: 'regtest',
            daemonListeningPort: daemon,
            ldkPeerListeningPort: peer,
          );
      final local = configuration(19735, 19736);
      expect(local.validate, returnsNormally);
      expect(local, configuration(19735, 19736));
      expect(local.hashCode, configuration(19735, 19736).hashCode);
      expect(local, isNot(configuration(9735, 9736)));
      expect(configuration(1, 65535).validate, returnsNormally);
      for (final ports in [
        (0, 9736),
        (-1, 9736),
        (65536, 9736),
        (9735, 0),
        (9735, -1),
        (9735, 65536),
        (9735, 9735),
      ]) {
        expect(
          configuration(ports.$1, ports.$2).validate,
          throwsA(isA<AppConfigurationException>()),
        );
      }
    },
  );

  test('accepts only canonical app-owned blockchain environments', () {
    expect(
      BlockchainEnvironment.parse('mainnet'),
      BlockchainEnvironment.mainnet,
    );
    expect(BlockchainEnvironment.parse('signet'), BlockchainEnvironment.signet);
    expect(
      BlockchainEnvironment.parse('regtest'),
      BlockchainEnvironment.regtest,
    );
    for (final alias in ['bitcoin', 'utexo', 'production-ish']) {
      expect(
        () => BlockchainEnvironment.parse(alias),
        throwsA(isA<AppConfigurationException>()),
        reason: alias,
      );
    }
  });

  test('market data is keyless only outside release builds', () {
    final development = MarketDataConfiguration.resolve(
      configuredBase: '',
      releaseMode: false,
    );
    final release = MarketDataConfiguration.resolve(
      configuredBase: '',
      releaseMode: true,
    );

    expect(development.access, MarketDataAccess.developmentKeyless);
    expect(
      development.endpoint('simple/price').toString(),
      'https://api.coingecko.com/api/v3/simple/price',
    );
    expect(release.access, MarketDataAccess.unavailable);
    expect(release.baseUri, isNull);
    expect(
      () => release.endpoint('simple/price'),
      throwsA(isA<AppConfigurationException>()),
    );
  });

  test('market release configuration accepts only an owned public proxy', () {
    final configuration = MarketDataConfiguration.resolve(
      configuredBase: 'https://market.aster.com/coingecko/v3',
      releaseMode: true,
    );

    expect(configuration.access, MarketDataAccess.deploymentProxy);
    expect(
      configuration.endpoint('simple/price').toString(),
      'https://market.aster.com/coingecko/v3/simple/price',
    );
    expect(
      () => configuration.endpoint('../secret'),
      throwsA(isA<AppConfigurationException>()),
    );
  });

  test('market release configuration rejects unsafe and direct API bases', () {
    for (final base in [
      'http://market.aster.com/api/v3',
      'https://token@market.aster.com/api/v3',
      'https://market.aster.com/api/v3?token=secret',
      'https://127.0.0.1/api/v3',
      'https://127.1/api/v3',
      'https://127.0.1/api/v3',
      'https://0x7f.0.0.1/api/v3',
      'https://0177.0.0.1/api/v3',
      'https://2130706433/api/v3',
      'https://0x7f000001/api/v3',
      'https://market.internal/api/v3',
      'https://market..aster.com/api/v3',
      'https://-market.aster.com/api/v3',
      'https://market.aster.com/%2e%2e/private',
      'https://market.aster.com/api//v3',
      'https://api.coingecko.com/api/v3',
      'https://pro-api.coingecko.com/api/v3',
    ]) {
      expect(
        () => MarketDataConfiguration.resolve(
          configuredBase: base,
          releaseMode: true,
        ),
        throwsA(isA<AppConfigurationException>()),
        reason: base,
      );
    }
  });

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
    expect(
      () => configuration.validate(allowInsecureDevelopmentEndpoints: false),
      throwsA(isA<AppConfigurationException>()),
    );
  });

  test('release policy rejects every insecure regtest transport', () {
    for (final configuration in [
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        indexerUrl: '127.0.0.1:50002',
      ),
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        indexerUrl: 'tcp://127.0.0.1:50002',
      ),
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        rgbTransportProxy: 'rpc://127.0.0.1:3001/json-rpc',
      ),
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        lspBaseUrl: 'http://10.0.2.2:3100',
      ),
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        vssUrl: 'http://localhost:3200',
      ),
    ]) {
      expect(
        () => configuration.validate(allowInsecureDevelopmentEndpoints: false),
        throwsA(isA<AppConfigurationException>()),
        reason:
            configuration.indexerUrl ??
            configuration.rgbTransportProxy ??
            configuration.lspBaseUrl ??
            configuration.vssUrl,
      );
    }

    const secure = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      indexerUrl: 'ssl://127.0.0.1:50002',
      rgbTransportProxy: 'rpcs://127.0.0.1:3001/json-rpc',
      lspBaseUrl: 'https://127.0.0.1:3100',
      vssUrl: 'https://127.0.0.1:3200',
    );
    expect(
      () => secure.validate(allowInsecureDevelopmentEndpoints: false),
      returnsNormally,
    );
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
      'ssl://127.1:50001',
      'https://127.0.1:3000',
      'https://0x7f.0.0.1:18443',
      'ssl://2130706433:50001',
      'https://0x7f000001:3000',
      'ssl://[0:0:0:0:0:0:0:1]:50001',
      'https://[::ffff:127.0.0.1]:3000',
      'https://[::127.0.0.1]:18443',
      'https://[::ffff:7f00:1]:3000',
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

  test('bounds and canonicalizes every wallet service endpoint', () {
    const prefix = 'https://vss.example.com/';
    final boundary = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      vssUrl:
          prefix +
          ('a' *
              (WalletServiceConfiguration.maximumEndpointCharacters -
                  prefix.length)),
    );
    expect(boundary.validate, returnsNormally);

    final invalidEndpoints = <String>[
      '${boundary.vssUrl}a',
      'https://-vss.example.com',
      'https://vss-.example.com',
      'https://vss..example.com',
      'https://vss_example.com',
      'https://vss.example.123',
      'https://vss.example.com/hidden\u202evalue',
      'https://vss.example.com/hidden%0Avalue',
      'https://vss.example.com/hidden%E2%80%AEvalue',
      'https://127.01.0.1',
      'https://127.0.0.1.',
      'https://localhost.',
    ];
    for (final endpoint in invalidEndpoints) {
      expect(
        () => WalletServiceConfiguration(
          environment: BlockchainEnvironment.mainnet,
          sdkNetwork: 'mainnet',
          vssUrl: endpoint,
        ).validate(),
        throwsA(isA<AppConfigurationException>()),
        reason: endpoint,
      );
    }
  });

  test('accepts canonical DNS, IPv4, and IPv6 service hosts', () {
    const dns = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      vssUrl: 'https://vss.example.com/path',
    );
    const ipv4 = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      vssUrl: 'https://192.0.2.1/path',
    );
    const ipv6 = WalletServiceConfiguration(
      environment: BlockchainEnvironment.mainnet,
      sdkNetwork: 'mainnet',
      vssUrl: 'https://[2001:db8::1]/path',
    );

    expect(dns.validate, returnsNormally);
    expect(ipv4.validate, returnsNormally);
    expect(ipv6.validate, returnsNormally);
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
    const deceptiveId = WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      usdtAsset: RgbAssetConfiguration(
        contractId: 'rgb:usdt\u202econtract',
        precision: 6,
      ),
    );

    expect(malformedId.validate, throwsA(isA<AppConfigurationException>()));
    expect(deceptiveId.validate, throwsA(isA<AppConfigurationException>()));
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

  test('public links are optional and preserve destination identity', () {
    final support = Uri.parse('https://support.example.com/help');
    final terms = Uri.parse('https://wallet.example.com/legal/terms');
    final configuration = PublicLinkConfiguration(
      contactSupport: support,
      termsOfService: terms,
    );

    expect(configuration.validate, returnsNormally);
    expect(configuration.uriFor(PublicLinkDestination.contactSupport), support);
    expect(configuration.uriFor(PublicLinkDestination.termsOfService), terms);
    expect(configuration.uriFor(PublicLinkDestination.privacyPolicy), isNull);
  });

  test('public links reject insecure or credential-bearing destinations', () {
    final configurations = [
      PublicLinkConfiguration(
        contactSupport: Uri.parse('http://support.example.com'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://token@support.example.com'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://support.example.com?token=value'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://support.example.com#private'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://support.example.com/${'a' * 2048}'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://localhost/help'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://127.0.0.1/help'),
      ),
      PublicLinkConfiguration(contactSupport: Uri.parse('https://127.1/help')),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://127.0.1/help'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://0x7f.0.0.1/help'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://0177.0.0.1/help'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://2130706433/help'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://0x7f000001/help'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://support.internal/help'),
      ),
      PublicLinkConfiguration(
        contactSupport: Uri.parse('https://support.example/help'),
      ),
    ];

    for (final configuration in configurations) {
      expect(
        configuration.validate,
        throwsA(isA<AppConfigurationException>()),
        reason: configuration.contactSupport.toString(),
      );
    }
  });
}
