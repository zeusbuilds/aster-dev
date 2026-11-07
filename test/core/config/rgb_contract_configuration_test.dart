import 'dart:convert';

import 'package:aster/core/config/config.dart';
import 'package:aster/core/errors/app_failure.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = utf8.encode('public genesis fixture, not a valid RGB contract');
  final encoded = base64Encode(bytes);
  final digest = sha256.convert(bytes).toString();

  RgbContractConfiguration contract({
    String? base64,
    String? sha,
    String name = 'Bridged USDT',
    String ticker = 'BUSDT',
  }) => RgbContractConfiguration(
    contractBase64: base64 ?? encoded,
    sha256Digest: sha ?? digest,
    nativeName: name,
    nativeTicker: ticker,
  );

  test('public contract bytes require an exact reviewed digest', () {
    expect(contract().validate, returnsNormally);
    expect(
      contract(sha: '0' * 64).validate,
      throwsA(isA<AppConfigurationException>()),
    );
    expect(contract(), contract());
    expect(contract().hashCode, contract().hashCode);
    expect(contract(name: 'Other'), isNot(contract()));
  });

  test('noncanonical encodings and malformed native metadata fail closed', () {
    for (final value in [
      contract(base64: ''),
      contract(base64: '$encoded\n'),
      contract(base64: '***='),
      contract(base64: 'Zh=='), // Decodes to f, but canonical encoding is Zg==.
      contract(sha: digest.toUpperCase()),
      contract(name: ' Bridged USDT'),
      contract(name: 'Bridged\nUSDT'),
      contract(ticker: 'BUS DT'),
      contract(ticker: ''),
    ]) {
      expect(value.validate, throwsA(isA<AppConfigurationException>()));
    }
    expect(
      contract(
        base64: 'A' * (RgbContractConfiguration.maximumEncodedCharacters + 4),
      ).validate,
      throwsA(isA<AppConfigurationException>()),
    );
  });

  test('RGB_L1 configured USDT cannot open without its approved genesis', () {
    WalletServiceConfiguration services(
      RgbContractConfiguration? canonical, {
      bool validatesEvm = true,
    }) => WalletServiceConfiguration(
      environment: BlockchainEnvironment.regtest,
      sdkNetwork: 'regtest',
      backend: WalletBackend.rgbL1,
      indexerUrl: 'http://127.0.0.1:29302',
      rgbTransportProxy: 'rpc://127.0.0.1:29300/json-rpc',
      ethRpcUrl: 'http://127.0.0.1:29545',
      ethChainId: '31337',
      bfaMintLockPolicy: const BfaMintLockPolicy(
        minimumBlocks: 2,
        maximumBlocks: 512,
      ),
      usdtAsset: RgbAssetConfiguration(
        contractId: 'rgb:independent-fixture',
        precision: 6,
        canonicalContract: canonical,
        requiresEvmValidation: validatesEvm,
      ),
    );
    expect(services(null).validate, throwsA(isA<AppConfigurationException>()));
    expect(services(contract()).validate, returnsNormally);
    expect(
      services(contract(), validatesEvm: false).validate,
      throwsA(isA<AppConfigurationException>()),
    );
    expect(
      services(contract(sha: '0' * 64)).validate,
      throwsA(isA<AppConfigurationException>()),
    );
  });

  test('asset equality binds exact genesis and expected native metadata', () {
    RgbAssetConfiguration asset(RgbContractConfiguration? approved) =>
        RgbAssetConfiguration(
          contractId: 'rgb:fixture',
          precision: 6,
          canonicalContract: approved,
        );
    expect(asset(contract()), asset(contract()));
    expect(asset(contract()), isNot(asset(null)));
    expect(asset(contract(name: 'Other')), isNot(asset(contract())));
  });

  test('BFA mint lock bounds are explicit, canonical and deployment owned', () {
    expect(BfaMintLockPolicy.parse('', ''), isNull);
    expect(
      BfaMintLockPolicy.parse('2', '7200'),
      const BfaMintLockPolicy(minimumBlocks: 2, maximumBlocks: 7200),
    );
    for (final (minimum, maximum) in [
      ('', '7200'),
      ('2', ''),
      ('1', '7200'),
      ('3', '2'),
      ('02', '7200'),
      ('+2', '7200'),
      ('2', '7200 '),
      ('2', '18446744073709551616'),
    ]) {
      expect(
        () => BfaMintLockPolicy.parse(minimum, maximum),
        throwsFormatException,
      );
    }
  });

  test(
    'RGB_L1 EVM access requires bounds and RLN cannot silently ignore them',
    () {
      WalletServiceConfiguration services({
        BfaMintLockPolicy? policy,
        WalletBackend backend = WalletBackend.rgbL1,
      }) => WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        backend: backend,
        ethRpcUrl: 'http://127.0.0.1:29545',
        ethChainId: '31337',
        bfaMintLockPolicy: policy,
      );
      const policy = BfaMintLockPolicy(minimumBlocks: 2, maximumBlocks: 512);
      expect(services().validate, throwsA(isA<AppConfigurationException>()));
      expect(services(policy: policy).validate, returnsNormally);
      expect(
        services(policy: policy, backend: WalletBackend.rln).validate,
        throwsA(isA<AppConfigurationException>()),
      );
      expect(
        services(
          policy: const BfaMintLockPolicy(minimumBlocks: 1, maximumBlocks: 512),
        ).validate,
        throwsA(isA<AppConfigurationException>()),
      );
    },
  );
}
