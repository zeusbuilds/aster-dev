import 'dart:convert';
import 'dart:io';

import 'package:aster/core/config/signet_deployment.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_configuration_manifest.dart';
import '../../tool/verify_release_configuration.dart';

void main() {
  group('ReleaseConfigurationManifest', () {
    test('the hosted Dev preset is rejected by every release audience', () {
      final preset = File('config/dev-signet.debug.json').readAsStringSync();
      for (final audience in ReleaseAudience.values) {
        expect(
          () => ReleaseConfigurationManifest.parse(preset, audience: audience),
          throwsFormatException,
        );
      }
    });

    test('approved public contract fields are atomic and digest checked', () {
      final bytes = List<int>.generate(3072, (index) => index % 256);
      final contract = <String, String>{
        ReleaseConfigurationKey.usdtContractBase64: base64Encode(bytes),
        ReleaseConfigurationKey.usdtContractSha256: sha256
            .convert(bytes)
            .toString(),
        ReleaseConfigurationKey.usdtNativeName: 'Bridged USDT',
        ReleaseConfigurationKey.usdtNativeTicker: 'BUSDT',
      };
      ReleaseConfigurationManifest parse(Map<String, String> extra) =>
          ReleaseConfigurationManifest.parse(
            _manifest({..._baseValues, ...extra}),
            audience: ReleaseAudience.internalBeta,
          );
      expect(
        parse(contract).values,
        containsPair(ReleaseConfigurationKey.usdtNativeName, 'Bridged USDT'),
      );
      for (final key in contract.keys) {
        final partial = {...contract}..remove(key);
        expect(() => parse(partial), throwsFormatException);
      }
      expect(
        () => parse({
          ...contract,
          ReleaseConfigurationKey.usdtContractSha256: '0' * 64,
        }),
        throwsFormatException,
      );
      expect(
        () => parse({
          ...contract,
          ReleaseConfigurationKey.walletBackend: 'rgb-l1',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('RGB_L1'),
          ),
        ),
      );
    });

    test('Dev profile and mixed Dev evidence fail before a release build', () {
      ReleaseConfigurationManifest parse(Map<String, String> overrides) =>
          ReleaseConfigurationManifest.parse(
            _manifest({..._baseValues, ...overrides}),
            audience: ReleaseAudience.internalBeta,
          );
      expect(
        parse({ReleaseConfigurationKey.signetDeployment: 'public'}).values,
        containsPair(ReleaseConfigurationKey.signetDeployment, 'public'),
      );
      for (final profile in ['dev-signet', 'utexo', 'dev', 'Public']) {
        expect(
          () => parse({ReleaseConfigurationKey.signetDeployment: profile}),
          throwsFormatException,
        );
      }
      for (final id in UtexoDevSignetPolicy.quarantinedAssetIds) {
        expect(
          () => parse({ReleaseConfigurationKey.usdtAssetId: id}),
          throwsFormatException,
        );
      }
      for (final host in UtexoDevSignetPolicy.quarantinedHosts) {
        for (final key in [
          ReleaseConfigurationKey.indexerUrl,
          ReleaseConfigurationKey.rgbProxyUrl,
          ReleaseConfigurationKey.vssUrl,
          ReleaseConfigurationKey.lspUrl,
          ReleaseConfigurationKey.explorerUrl,
          ReleaseConfigurationKey.ethRpcUrl,
        ]) {
          expect(
            () => parse({key: 'https://${host.toUpperCase()}:443/other'}),
            throwsFormatException,
          );
        }
      }
    });

    test('RGB_L1 deployment is blocked until durable sends are qualified', () {
      ReleaseConfigurationManifest parse(String backend) =>
          ReleaseConfigurationManifest.parse(
            _manifest({
              ...(backend == 'rgb-l1' ? _rgbL1BaseValues : _baseValues),
              ReleaseConfigurationKey.walletBackend: backend,
            }),
            audience: ReleaseAudience.internalBeta,
          );
      expect(parse('rln').values[ReleaseConfigurationKey.walletBackend], 'rln');
      expect(
        () => parse('rgb-l1'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('durable payment recovery'),
          ),
        ),
      );
      expect(() => parse('RGB_L1'), throwsFormatException);
    });

    test(
      'RGB_L1 internal BTC configuration has no contradictory VSS requirement',
      () {
        expect(
          () => ReleaseConfigurationManifest.parse(
            _manifest(_rgbL1BaseValues),
            audience: ReleaseAudience.internalBeta,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'closed admission',
              contains('verified durable payment recovery'),
            ),
          ),
        );
        for (final key in [
          ReleaseConfigurationKey.vssUrl,
          ReleaseConfigurationKey.lspUrl,
        ]) {
          expect(
            () => ReleaseConfigurationManifest.parse(
              _manifest({
                ..._rgbL1BaseValues,
                key: 'https://unused.aster-wallet.com',
              }),
              audience: ReleaseAudience.internalBeta,
            ),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'unsupported service',
                contains('does not support LSP or VSS'),
              ),
            ),
          );
        }
      },
    );

    test('RGB_L1 BFA candidate requires exact contract and complete EVM policy before admission', () {
      final contract = base64Encode(List<int>.generate(64, (index) => index));
      final asset = <String, String>{
        ReleaseConfigurationKey.usdtAssetId: 'rgb:2cV8xYz123',
        ReleaseConfigurationKey.usdtPrecision: '6',
        ReleaseConfigurationKey.usdtContractBase64: contract,
        ReleaseConfigurationKey.usdtContractSha256: sha256
            .convert(base64Decode(contract))
            .toString(),
        ReleaseConfigurationKey.usdtNativeName: 'Fixture BFA',
        ReleaseConfigurationKey.usdtNativeTicker: 'QBFA',
      };
      final evm = <String, String>{
        ReleaseConfigurationKey.ethRpcUrl: 'https://rpc.aster-wallet.com',
        ReleaseConfigurationKey.ethChainId: '42161',
        ReleaseConfigurationKey.bfaMinMintLockBlocks: '2',
        ReleaseConfigurationKey.bfaMaxMintLockBlocks: '512',
      };
      ReleaseConfigurationManifest parse(Map<String, String> fields) =>
          ReleaseConfigurationManifest.parse(
            _manifest({..._rgbL1BaseValues, ...fields}),
            audience: ReleaseAudience.internalBeta,
          );
      expect(
        () => parse({...asset, ...evm}),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'closed admission',
            contains('verified durable payment recovery'),
          ),
        ),
      );
      for (final key in {...asset.keys, ...evm.keys}) {
        final fields = {...asset, ...evm}..remove(key);
        expect(() => parse(fields), throwsFormatException, reason: key);
      }
      expect(
        () => parse({
          ...asset,
          ...evm,
          ReleaseConfigurationKey.ethChainId: (BigInt.one << 64).toString(),
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'native EVM bound',
            contains('uint64'),
          ),
        ),
      );
    });

    test('RGB_L1 public product still requires approved USDT deployment', () {
      expect(
        () => ReleaseConfigurationManifest.parse(
          _manifest({
            ..._rgbL1BaseValues,
            ReleaseConfigurationKey.marketApiBaseUrl:
                'https://market.aster-wallet.com',
            ReleaseConfigurationKey.privacyUrl:
                'https://aster-wallet.com/privacy',
            ReleaseConfigurationKey.supportUrl:
                'https://aster-wallet.com/support',
            ReleaseConfigurationKey.termsUrl: 'https://aster-wallet.com/terms',
          }),
          audience: ReleaseAudience.publicDistribution,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'mandatory public USDT',
            contains('missing required keys'),
          ),
        ),
      );
    });

    test('BFA release fails without RPC or an explicit canonical chain ID', () {
      for (final key in [
        ReleaseConfigurationKey.ethRpcUrl,
        ReleaseConfigurationKey.ethChainId,
      ]) {
        final values = Map<String, String>.of(_baseValues)..remove(key);
        expect(
          () => ReleaseConfigurationManifest.parse(
            _manifest(values),
            audience: ReleaseAudience.internalBeta,
          ),
          throwsFormatException,
        );
      }
      for (final chain in [
        '0',
        '-1',
        '+1',
        '01',
        '0xa4b1',
        '1.0',
        (BigInt.one << 256).toString(),
      ]) {
        expect(
          () => ReleaseConfigurationManifest.parse(
            _manifest({
              ..._baseValues,
              ReleaseConfigurationKey.ethChainId: chain,
            }),
            audience: ReleaseAudience.internalBeta,
          ),
          throwsFormatException,
          reason: chain,
        );
      }
    });
    test(
      'onchain release needs no LSP and validates required Ethereum RPC',
      () {
        final values = Map<String, String>.of(_baseValues)
          ..remove(ReleaseConfigurationKey.lspUrl);
        expect(
          ReleaseConfigurationManifest.parse(
            _manifest(values),
            audience: ReleaseAudience.internalBeta,
          ).values,
          isNot(contains(ReleaseConfigurationKey.lspUrl)),
        );
        for (final key in [
          ReleaseConfigurationKey.ethRpcUrl,
          ReleaseConfigurationKey.lspUrl,
        ]) {
          for (final value in [
            'http://rpc.aster-wallet.com',
            'https://token@rpc.aster-wallet.com',
            'https://rpc.aster-wallet.com?key=secret',
          ]) {
            expect(
              () => ReleaseConfigurationManifest.parse(
                _manifest({...values, key: value}),
                audience: ReleaseAudience.internalBeta,
              ),
              throwsFormatException,
            );
          }
        }
        final configured = ReleaseConfigurationManifest.parse(
          _manifest({
            ...values,
            ReleaseConfigurationKey.ethRpcUrl: 'https://rpc.aster-wallet.com',
          }),
          audience: ReleaseAudience.internalBeta,
        );
        expect(
          configured.values[ReleaseConfigurationKey.ethRpcUrl],
          'https://rpc.aster-wallet.com',
        );
      },
    );

    test(
      'optional native listener ports reject malformed and colliding values',
      () {
        ReleaseConfigurationManifest parse(Map<String, String> ports) =>
            ReleaseConfigurationManifest.parse(
              _manifest({..._baseValues, ...ports}),
              audience: ReleaseAudience.internalBeta,
            );
        expect(
          parse({'ASTER_DAEMON_PORT': '19735', 'ASTER_LDK_PEER_PORT': '19736'})
              .values['ASTER_LDK_PEER_PORT'],
          '19736',
        );
        for (final key in [
          ReleaseConfigurationKey.daemonPort,
          ReleaseConfigurationKey.ldkPeerPort,
        ]) {
          for (final value in [
            '0',
            '-1',
            '65536',
            '019735',
            '+19735',
            '1.5',
            'abc',
            ' 19735',
          ]) {
            expect(() => parse({key: value}), throwsFormatException);
          }
        }
        for (final ports in [
          {'ASTER_DAEMON_PORT': '9736'},
          {'ASTER_LDK_PEER_PORT': '9735'},
          {'ASTER_DAEMON_PORT': '19735', 'ASTER_LDK_PEER_PORT': '19735'},
        ]) {
          expect(() => parse(ports), throwsFormatException);
        }
      },
    );

    test('accepts a complete sorted internal-beta manifest', () {
      final manifest = ReleaseConfigurationManifest.parse(
        _manifest(),
        audience: ReleaseAudience.internalBeta,
      );

      expect(manifest.audience, ReleaseAudience.internalBeta);
      expect(manifest.values.keys, orderedEquals(_baseValues.keys));
      expect(
        () => manifest.values[ReleaseConfigurationKey.network] = 'mainnet',
        throwsUnsupportedError,
      );
    });

    test('public distribution checks its services before the backup gate', () {
      expect(
        () => ReleaseConfigurationManifest.parse(
          _manifest(),
          audience: ReleaseAudience.publicDistribution,
        ),
        throwsA(isA<FormatException>()),
      );

      final values = <String, String>{
        ..._baseValues,
        ReleaseConfigurationKey.network: 'mainnet',
        ReleaseConfigurationKey.marketApiBaseUrl:
            'https://market.aster-wallet.com/api/v3/',
        ReleaseConfigurationKey.privacyUrl: 'https://aster-wallet.com/privacy',
        ReleaseConfigurationKey.supportUrl: 'https://aster-wallet.com/support',
        ReleaseConfigurationKey.termsUrl: 'https://aster-wallet.com/terms',
      };
      expect(
        () => ReleaseConfigurationManifest.parse(
          _manifest(values),
          audience: ReleaseAudience.publicDistribution,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('backup and restore that preserve durable'),
          ),
        ),
      );
      for (final network in ['signet', 'regtest']) {
        expect(
          () => ReleaseConfigurationManifest.parse(
            _manifest({...values, ReleaseConfigurationKey.network: network}),
            audience: ReleaseAudience.publicDistribution,
          ),
          throwsFormatException,
        );
      }
    });

    test('rejects unknown keys, non-string values, and unstable ordering', () {
      expect(
        () => ReleaseConfigurationManifest.parse(
          jsonEncode({..._baseValues, 'ASTER_API_TOKEN': 'secret'}),
          audience: ReleaseAudience.internalBeta,
        ),
        throwsA(isA<FormatException>()),
      );
      final dynamicValues = <String, Object?>{..._baseValues};
      dynamicValues[ReleaseConfigurationKey.usdtPrecision] = 8;
      expect(
        () => ReleaseConfigurationManifest.parse(
          _manifest(dynamicValues),
          audience: ReleaseAudience.internalBeta,
        ),
        throwsA(isA<FormatException>()),
      );
      final reversedValues = Map<String, String>.fromEntries(
        _baseValues.entries.toList().reversed,
      );
      expect(
        () => ReleaseConfigurationManifest.parse(
          jsonEncode(reversedValues),
          audience: ReleaseAudience.internalBeta,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects duplicate keys even when one key uses a JSON escape', () {
      final source = _manifest().replaceFirst(
        '"ASTER_NETWORK": "signet",',
        '"ASTER_NETWORK": "signet",\n'
            '  "ASTER_\\u004eETWORK": "mainnet",',
      );

      expect(
        () => ReleaseConfigurationManifest.parse(
          source,
          audience: ReleaseAudience.internalBeta,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects trailing content, trailing commas, and nested values', () {
      for (final source in <String>[
        '${_manifest()} true',
        _manifest().replaceFirst(RegExp(r'\n}$'), ',\n}'),
        _manifest().replaceFirst('"signet"', '{"value":"signet"}'),
      ]) {
        expect(
          () => ReleaseConfigurationManifest.parse(
            source,
            audience: ReleaseAudience.internalBeta,
          ),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('rejects placeholders and non-release transport', () {
      for (final replacement in <String, String>{
        ReleaseConfigurationKey.indexerUrl:
            'tcp://indexer.aster-wallet.com:50001',
        ReleaseConfigurationKey.lspUrl: 'http://lsp.aster-wallet.com',
        ReleaseConfigurationKey.vssUrl: 'https://vss.example',
        ReleaseConfigurationKey.explorerUrl:
            'https://user:password@explorer.aster-wallet.com',
      }.entries) {
        expect(
          () => ReleaseConfigurationManifest.parse(
            _manifest({..._baseValues, replacement.key: replacement.value}),
            audience: ReleaseAudience.internalBeta,
          ),
          throwsA(isA<FormatException>()),
          reason: replacement.key,
        );
      }
    });

    test('rejects malformed asset identity and precision', () {
      for (final replacement in <String, String>{
        ReleaseConfigurationKey.usdtAssetId: 'REPLACE_ME',
        '${ReleaseConfigurationKey.usdtPrecision}#negative': '-1',
        ReleaseConfigurationKey.usdtPrecision: '01',
        '${ReleaseConfigurationKey.usdtPrecision}#high': '19',
      }.entries) {
        final key = replacement.key.split('#').first;
        expect(
          () => ReleaseConfigurationManifest.parse(
            _manifest({..._baseValues, key: replacement.value}),
            audience: ReleaseAudience.internalBeta,
          ),
          throwsA(isA<FormatException>()),
          reason: replacement.key,
        );
      }
    });

    test('rejects direct provider hosts and unsafe public links', () {
      for (final replacement in <String, String>{
        ReleaseConfigurationKey.marketApiBaseUrl:
            'https://api.coingecko.com/api/v3/',
        ReleaseConfigurationKey.supportUrl:
            'https://aster-wallet.com/support?wallet=1',
      }.entries) {
        expect(
          () => ReleaseConfigurationManifest.parse(
            _manifest({..._baseValues, replacement.key: replacement.value}),
            audience: ReleaseAudience.internalBeta,
          ),
          throwsA(isA<FormatException>()),
          reason: replacement.key,
        );
      }
    });

    test('rejects oversized source before parsing', () {
      final source = 'A' * (maximumReleaseConfigurationBytes + 1);

      expect(
        () => ReleaseConfigurationManifest.parse(
          source,
          audience: ReleaseAudience.internalBeta,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('bounded file reader never loads beyond the manifest limit', () async {
      final directory = await Directory.systemTemp.createTemp(
        'aster-release-manifest-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/oversized.json');
      await file.writeAsBytes(
        List<int>.filled(maximumReleaseConfigurationBytes + 1, 0x41),
      );

      await expectLater(
        readBoundedReleaseConfiguration(file),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

String _manifest([Map<String, Object?> values = _baseValues]) {
  final sorted = values.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    for (final entry in sorted) entry.key: entry.value,
  });
}

const _baseValues = <String, String>{
  ReleaseConfigurationKey.ethChainId: '42161',
  ReleaseConfigurationKey.ethRpcUrl: 'https://rpc.aster-wallet.com',
  ReleaseConfigurationKey.explorerUrl: 'https://explorer.aster-wallet.com',
  ReleaseConfigurationKey.indexerUrl: 'ssl://indexer.aster-wallet.com:50002',
  ReleaseConfigurationKey.lspUrl: 'https://lsp.aster-wallet.com',
  ReleaseConfigurationKey.network: 'signet',
  ReleaseConfigurationKey.rgbProxyUrl: 'rpcs://rgb.aster-wallet.com:443',
  ReleaseConfigurationKey.usdtAssetId: 'rgb:2cV8xYz123',
  ReleaseConfigurationKey.usdtPrecision: '8',
  ReleaseConfigurationKey.vssUrl: 'https://vss.aster-wallet.com',
};

const _rgbL1BaseValues = <String, String>{
  ReleaseConfigurationKey.walletBackend: 'rgb-l1',
  ReleaseConfigurationKey.network: 'mainnet',
  ReleaseConfigurationKey.explorerUrl: 'https://explorer.aster-wallet.com',
  ReleaseConfigurationKey.indexerUrl: 'ssl://indexer.aster-wallet.com:50002',
  ReleaseConfigurationKey.rgbProxyUrl: 'rpcs://rgb.aster-wallet.com:443',
};
