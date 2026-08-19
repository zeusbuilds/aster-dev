import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_configuration_manifest.dart';
import '../../tool/verify_release_configuration.dart';

void main() {
  group('ReleaseConfigurationManifest', () {
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

    test('public distribution requires release-owned public surfaces', () {
      expect(
        () => ReleaseConfigurationManifest.parse(
          _manifest(),
          audience: ReleaseAudience.publicDistribution,
        ),
        throwsA(isA<FormatException>()),
      );

      final values = <String, String>{
        ..._baseValues,
        ReleaseConfigurationKey.marketApiBaseUrl:
            'https://market.aster-wallet.com/api/v3/',
        ReleaseConfigurationKey.privacyUrl: 'https://aster-wallet.com/privacy',
        ReleaseConfigurationKey.supportUrl: 'https://aster-wallet.com/support',
        ReleaseConfigurationKey.termsUrl: 'https://aster-wallet.com/terms',
      };
      expect(
        ReleaseConfigurationManifest.parse(
          _manifest(values),
          audience: ReleaseAudience.publicDistribution,
        ).values,
        hasLength(values.length),
      );
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
  ReleaseConfigurationKey.explorerUrl: 'https://explorer.aster-wallet.com',
  ReleaseConfigurationKey.indexerUrl: 'ssl://indexer.aster-wallet.com:50002',
  ReleaseConfigurationKey.lspUrl: 'https://lsp.aster-wallet.com',
  ReleaseConfigurationKey.network: 'signet',
  ReleaseConfigurationKey.rgbProxyUrl: 'rpcs://rgb.aster-wallet.com:443',
  ReleaseConfigurationKey.usdtAssetId: 'rgb:2cV8xYz123',
  ReleaseConfigurationKey.usdtPrecision: '8',
  ReleaseConfigurationKey.vssUrl: 'https://vss.aster-wallet.com',
};
