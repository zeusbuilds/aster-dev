import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_android_release_identity.dart';

void main() {
  const expected = AndroidReleaseIdentity(
    applicationId: 'com.example.utexo',
    versionName: '1.2.3',
    versionCode: 47,
  );

  test('parses authoritative source identity', () {
    final identity = parseExpectedAndroidReleaseIdentity(
      pubspec: 'name: utexo\nversion: 1.2.3+47\n',
      gradleProperties:
          'android.useAndroidX=true\n'
          'utexo.applicationId=com.example.utexo\n',
    );

    expect(identity.applicationId, expected.applicationId);
    expect(identity.versionName, expected.versionName);
    expect(identity.versionCode, expected.versionCode);
  });

  test('rejects ambiguous or non-release source identity', () {
    expect(
      () => parseExpectedAndroidReleaseIdentity(
        pubspec: 'version: 1.2.3\n',
        gradleProperties: 'utexo.applicationId=com.example.utexo\n',
      ),
      throwsFormatException,
    );
    expect(
      () => parseExpectedAndroidReleaseIdentity(
        pubspec: 'version: 1.2.3+47\n',
        gradleProperties:
            'utexo.applicationId=com.example.utexo\n'
            'utexo.applicationId=com.example.other\n',
      ),
      throwsFormatException,
    );
    expect(
      () => parseExpectedAndroidReleaseIdentity(
        pubspec: 'version: 1.2.3+47\n',
        gradleProperties: 'utexo.applicationId=not-a-package\n',
      ),
      throwsFormatException,
    );
  });

  test('parses exact aapt2 package metadata', () {
    final identity = parseAapt2Badging(
      "package: name='com.example.utexo' versionCode='2047' "
      "versionName='1.2.3' compileSdkVersion='36'\n"
      "sdkVersion:'24'\n"
      "native-code: 'arm64-v8a'\n",
    );

    expect(identity.applicationId, expected.applicationId);
    expect(identity.versionName, expected.versionName);
    expect(identity.versionCode, 2047);
    expect(identity.splitAbi, 'arm64-v8a');
  });

  test('rejects malformed, duplicate, or incomplete aapt2 metadata', () {
    expect(() => parseAapt2Badging('sdkVersion:\'24\''), throwsFormatException);
    expect(
      () => parseAapt2Badging(
        "package: name='com.example.utexo' name='com.example.other' "
        "versionCode='2047' versionName='1.2.3'\n"
        "native-code: 'arm64-v8a'",
      ),
      throwsFormatException,
    );
    expect(
      () => parseAapt2Badging(
        "package: name='com.example.utexo' versionName='1.2.3'\n"
        "native-code: 'arm64-v8a'",
      ),
      throwsFormatException,
    );
    expect(
      () => parseAapt2Badging(
        "package: name='com.example.utexo' versionCode='2047' "
        "versionName='1.2.3'\n"
        "native-code: 'arm64-v8a' 'x86_64'",
      ),
      throwsFormatException,
    );
  });

  test('parses exact bundle manifest inspector output', () {
    final identity = parseBundleManifestIdentity(
      'UTEXO_APPLICATION_ID=com.example.utexo\n'
      'UTEXO_VERSION_CODE=47\n'
      'UTEXO_VERSION_NAME=1.2.3\n',
    );

    expect(identity.applicationId, expected.applicationId);
    expect(identity.versionName, expected.versionName);
    expect(identity.versionCode, expected.versionCode);
  });

  test('rejects unknown, duplicate, or incomplete bundle output', () {
    expect(
      () => parseBundleManifestIdentity(
        'UTEXO_APPLICATION_ID=com.example.utexo\n'
        'UTEXO_VERSION_CODE=47\n',
      ),
      throwsFormatException,
    );
    expect(
      () => parseBundleManifestIdentity(
        'UTEXO_APPLICATION_ID=com.example.utexo\n'
        'UTEXO_VERSION_CODE=47\n'
        'UTEXO_VERSION_NAME=1.2.3\n'
        'UNKNOWN=value\n',
      ),
      throwsFormatException,
    );
    expect(
      () => parseBundleManifestIdentity(
        'UTEXO_APPLICATION_ID=com.example.utexo\n'
        'UTEXO_VERSION_CODE=47\n'
        'UTEXO_VERSION_CODE=48\n'
        'UTEXO_VERSION_NAME=1.2.3\n',
      ),
      throwsFormatException,
    );
  });

  test('reports every source-to-artifact identity mismatch', () {
    final failures = compareAndroidReleaseIdentity(
      expected: expected,
      actual: const AndroidReleaseIdentity(
        applicationId: 'com.example.other',
        versionName: '2.0.0',
        versionCode: 48,
      ),
    );

    expect(failures, hasLength(3));
    expect(failures, contains(contains('application ID')));
    expect(failures, contains(contains('version name')));
    expect(failures, contains(contains('version code')));
  });

  test('accepts Flutter split-ABI version-code encoding', () {
    for (final entry in const {
      'armeabi-v7a': 1047,
      'arm64-v8a': 2047,
      'x86_64': 4047,
    }.entries) {
      final failures = compareAndroidReleaseIdentity(
        expected: expected,
        actual: AndroidReleaseIdentity(
          applicationId: expected.applicationId,
          versionName: expected.versionName,
          versionCode: entry.value,
          splitAbi: entry.key,
        ),
      );

      expect(failures, isEmpty, reason: entry.key);
    }
  });
}
