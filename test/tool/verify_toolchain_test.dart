import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_toolchain.dart';

void main() {
  late Directory repository;
  late File flutterExtension;
  late File flutterGradleUtils;

  setUp(() {
    repository = Directory.systemTemp.createTempSync('utexo_toolchain_');
    flutterExtension = _write(
      repository,
      'flutter/packages/flutter_tools/gradle/src/main/kotlin/'
          'FlutterExtension.kt',
      'val ndkVersion: String = "28.2.13676358"',
    );
    flutterGradleUtils = _write(
      repository,
      'flutter/packages/flutter_tools/lib/src/android/gradle_utils.dart',
      "const templateDefaultGradleVersion = '9.3.1';\n"
          "const templateAndroidGradlePluginVersion = '9.1.0';\n"
          "const templateKotlinGradlePluginVersion = '2.4.0';",
    );
    _write(
      repository,
      'android/app/build.gradle.kts',
      'android { ndkVersion = flutter.ndkVersion }',
    );
    _write(
      repository,
      'android/settings.gradle.kts',
      'plugins {\n'
          '  id("com.android.application") version "9.1.0" apply false\n'
          '  id("org.jetbrains.kotlin.android") version "2.4.0" apply false\n'
          '}',
    );
    _write(
      repository,
      'android/gradle/wrapper/gradle-wrapper.properties',
      'distributionUrl=https\\://services.gradle.org/distributions/'
          'gradle-9.3.1-all.zip',
    );
    _write(
      repository,
      'flake.nix',
      'includeNDK = true;\nndkVersions = [ "28.2.13676358" ];',
    );
    _write(
      repository,
      'docs/DEVELOPMENT.md',
      '- Android NDK 28.2.13676358, matching Flutter\n'
          '- Gradle 9.3.1, Android Gradle Plugin 9.1.0, and Kotlin 2.4.0',
    );
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
  });

  test('accepts one exact Flutter-owned NDK contract', () {
    final result = verifyToolchain(
      repositoryRoot: repository,
      flutterExtension: flutterExtension,
      flutterGradleUtils: flutterGradleUtils,
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.flutterNdkVersion, '28.2.13676358');
    expect(result.flutterGradleVersion, '9.3.1');
    expect(result.flutterAgpVersion, '9.1.0');
    expect(result.flutterKotlinVersion, '2.4.0');
  });

  test('rejects an omitted NDK and a divergent Nix revision', () {
    _write(
      repository,
      'flake.nix',
      'includeNDK = false;\nndkVersions = [ "27.0.0" ];',
    );

    final result = verifyToolchain(
      repositoryRoot: repository,
      flutterExtension: flutterExtension,
      flutterGradleUtils: flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must include the Android NDK'),
        contains('exactly Flutter NDK 28.2.13676358'),
      ]),
    );
  });

  test('rejects Android build-chain drift', () {
    _write(
      repository,
      'android/app/build.gradle.kts',
      'android { ndkVersion = "27.0.0" }',
    );
    _write(
      repository,
      'android/settings.gradle.kts',
      'plugins {\n'
          '  id("com.android.application") version "9.0.1" apply false\n'
          '  id("org.jetbrains.kotlin.android") version "2.3.20" apply false\n'
          '}',
    );
    _write(
      repository,
      'android/gradle/wrapper/gradle-wrapper.properties',
      'distributionUrl=https\\://services.gradle.org/distributions/'
          'gradle-9.1.0-all.zip',
    );

    final result = verifyToolchain(
      repositoryRoot: repository,
      flutterExtension: flutterExtension,
      flutterGradleUtils: flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must delegate ndkVersion to Flutter'),
        contains('exactly Android Gradle Plugin 9.1.0'),
        contains('exactly Kotlin Gradle Plugin 2.4.0'),
        contains('wrapper must use Flutter Gradle 9.3.1'),
      ]),
    );
  });

  test('rejects documentation drift', () {
    _write(repository, 'docs/DEVELOPMENT.md', '- Android SDK 36');

    final result = verifyToolchain(
      repositoryRoot: repository,
      flutterExtension: flutterExtension,
      flutterGradleUtils: flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must document Android NDK 28.2.13676358'),
        contains('must document Flutter\'s Android build chain'),
      ]),
    );
  });

  test('fails closed when Flutter metadata is unavailable', () {
    final result = verifyToolchain(
      repositoryRoot: repository,
      flutterExtension: null,
      flutterGradleUtils: null,
    );

    expect(result.passed, isFalse);
    expect(result.flutterNdkVersion, isNull);
    expect(
      result.failures,
      containsAll([
        'Missing Flutter Gradle extension.',
        'Missing Flutter Gradle utilities.',
      ]),
    );
  });
}

File _write(Directory root, String path, String contents) {
  final file = File('${root.path}/$path');
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}
