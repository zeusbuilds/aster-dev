import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_configuration_manifest.dart';
import '../../tool/verify_ios_export_options.dart';

void main() {
  const bundleIdentifier = 'com.example.asterdev';

  test('accepts explicit App Store Connect export ownership', () {
    expect(
      () => validateIosExportOptions(
        _options(),
        audience: ReleaseAudience.publicDistribution,
        expectedBundleIdentifier: bundleIdentifier,
      ),
      returnsNormally,
    );
  });

  test('rejects non-store methods for public distribution', () {
    expect(
      () => validateIosExportOptions(
        _options(method: 'development'),
        audience: ReleaseAudience.publicDistribution,
        expectedBundleIdentifier: bundleIdentifier,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('requires source identity and immutable version metadata', () {
    for (final options in <Map<String, Object?>>[
      _options()..remove('distributionBundleIdentifier'),
      _options()..['distributionBundleIdentifier'] = 'com.example.other',
      _options()..['manageAppVersionAndBuildNumber'] = true,
      _options()..['destination'] = 'upload',
      _options()..['teamID'] = 'short',
    ]) {
      expect(
        () => validateIosExportOptions(
          options,
          audience: ReleaseAudience.internalBeta,
          expectedBundleIdentifier: bundleIdentifier,
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('manual signing requires the application profile', () {
    final missing = _options()..['signingStyle'] = 'manual';
    final valid = _options()
      ..['signingStyle'] = 'manual'
      ..['provisioningProfiles'] = const {
        bundleIdentifier: 'Aster Distribution',
      };

    expect(
      () => validateIosExportOptions(
        missing,
        audience: ReleaseAudience.internalBeta,
        expectedBundleIdentifier: bundleIdentifier,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validateIosExportOptions(
        valid,
        audience: ReleaseAudience.internalBeta,
        expectedBundleIdentifier: bundleIdentifier,
      ),
      returnsNormally,
    );

    final ambiguous = Map<String, Object?>.from(valid)
      ..['provisioningProfiles'] = const {
        bundleIdentifier: 'Aster Distribution',
        'com.example.unowned': 'Unexpected Profile',
      };
    final automaticWithProfile = _options()
      ..['provisioningProfiles'] = const {
        bundleIdentifier: 'Aster Distribution',
      };
    for (final options in [ambiguous, automaticWithProfile]) {
      expect(
        () => validateIosExportOptions(
          options,
          audience: ReleaseAudience.internalBeta,
          expectedBundleIdentifier: bundleIdentifier,
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('rejects unreviewed keys and malformed nested values', () {
    expect(
      () => validateIosExportOptions(
        _options()..['password'] = 'not-allowed',
        audience: ReleaseAudience.internalBeta,
        expectedBundleIdentifier: bundleIdentifier,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validateIosExportOptions(
        _options()..['manifest'] = <String, Object?>{'url': ''},
        audience: ReleaseAudience.internalBeta,
        expectedBundleIdentifier: bundleIdentifier,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

Map<String, Object?> _options({String method = 'app-store-connect'}) => {
  'destination': 'export',
  'distributionBundleIdentifier': 'com.example.asterdev',
  'manageAppVersionAndBuildNumber': false,
  'method': method,
  'signingStyle': 'automatic',
  'teamID': 'ABCDE12345',
};
