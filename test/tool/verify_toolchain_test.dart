import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_toolchain.dart';

void main() {
  late Directory repository;
  late File flutterVersionMetadata;
  late File flutterExtension;
  late File flutterGradleUtils;

  setUp(() {
    repository = Directory.systemTemp.createTempSync('utexo_toolchain_');
    flutterVersionMetadata = _write(
      repository,
      'flutter/bin/cache/flutter.version.json',
      '{"flutterVersion":"3.47.0","dartSdkVersion":"3.13.0"}',
    );
    flutterExtension = _write(
      repository,
      'flutter/packages/flutter_tools/gradle/src/main/kotlin/'
          'FlutterExtension.kt',
      'val compileSdkVersion: Int = 36\n'
          'val minSdkVersion: Int = 24\n'
          'val targetSdkVersion: Int = 36\n'
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
      'android {\n'
          '  compileSdk = flutter.compileSdkVersion\n'
          '  buildToolsVersion = "36.0.0"\n'
          '  ndkVersion = flutter.ndkVersion\n'
          '  defaultConfig {\n'
          '    minSdk = flutter.minSdkVersion\n'
          '    targetSdk = flutter.targetSdkVersion\n'
          '  }\n'
          '}',
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
      'includeNDK = true;\n'
          'ndkVersions = [ "28.2.13676358" ];\n'
          'platformToolsVersion = "36.0.0";\n'
          'buildToolsVersions = [ "36.0.0" ];\n'
          'platformVersions = [ "36" ];\n'
          'PATH="build-tools/36.0.0";',
    );
    _write(repository, '.fvmrc', '{"flutter":"3.47.0"}');
    _write(
      repository,
      '.vscode/settings.json',
      '{"dart.flutterSdkPath":".fvm/versions/3.47.0"}',
    );
    _write(
      repository,
      '.github/workflows/dart.yml',
      'flutter-version: "3.47.0"\n'
          'run: flutter pub get --enforce-lockfile\n'
          'run: flutter analyze --no-pub --fatal-warnings --fatal-infos\n'
          'run: flutter test --no-pub',
    );
    _write(
      repository,
      'Makefile',
      'dependencies:\n\tfvm flutter pub get --enforce-lockfile',
    );
    _write(
      repository,
      'pubspec.yaml',
      'environment:\n'
          '  sdk: ">=3.13.0 <4.0.0"\n'
          '  flutter: ">=3.47.0"',
    );
    _write(
      repository,
      'docs/DEVELOPMENT.md',
      '- Android SDK platform 36, build tools 36.0.0, and platform tools 36.0.0\n'
          '- Android NDK 28.2.13676358, matching Flutter\n'
          '- Gradle 9.3.1, Android Gradle Plugin 9.1.0, and Kotlin 2.4.0\n'
          '- Flutter 3.47.0 and Dart 3.13.0',
    );
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
  });

  test('accepts the complete Flutter-owned toolchain contract', () {
    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.flutterVersion, '3.47.0');
    expect(result.dartVersion, '3.13.0');
    expect(result.flutterGradleVersion, '9.3.1');
    expect(result.flutterAgpVersion, '9.1.0');
    expect(result.flutterKotlinVersion, '2.4.0');
    expect(result.flutterCompileSdk, 36);
    expect(result.flutterMinSdk, 24);
    expect(result.flutterTargetSdk, 36);
    expect(result.flutterNdkVersion, '28.2.13676358');
    expect(result.androidBuildToolsVersion, '36.0.0');
    expect(result.androidPlatformToolsVersion, '36.0.0');
  });

  test('rejects omitted NDK and divergent Nix revisions', () {
    _write(
      repository,
      'flake.nix',
      'includeNDK = false;\nndkVersions = [ "27.0.0" ];',
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must include the Android NDK'),
        contains('exactly Flutter NDK 28.2.13676358'),
        contains('exactly Android build tools 36.0.0'),
        contains('exactly Android SDK platform 36'),
        contains('Nix Android platform-tools version'),
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

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must delegate compileSdk to Flutter'),
        contains('must delegate minSdk to Flutter'),
        contains('must delegate targetSdk to Flutter'),
        contains('must delegate ndkVersion to Flutter'),
        contains('exactly Android Gradle Plugin 9.1.0'),
        contains('exactly Kotlin Gradle Plugin 2.4.0'),
        contains('wrapper must use Flutter Gradle 9.3.1'),
      ]),
    );
  });

  test('rejects documentation drift', () {
    _write(repository, 'docs/DEVELOPMENT.md', '- Android SDK 36');

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must document Android NDK 28.2.13676358'),
        contains('must document Flutter\'s Android build chain'),
        contains('must document the Android SDK/build-tools chain'),
        contains('must document the Flutter/Dart versions'),
      ]),
    );
  });

  test('rejects Flutter, Dart, CI, editor, and package version drift', () {
    _write(repository, '.fvmrc', '{"flutter":"3.46.0"}');
    _write(
      repository,
      '.vscode/settings.json',
      '{"dart.flutterSdkPath":".fvm/versions/3.46.0"}',
    );
    _write(
      repository,
      '.github/workflows/dart.yml',
      'flutter-version: "3.46.0"\n'
          'run: flutter pub get\n'
          'run: flutter analyze --fatal-warnings --fatal-infos\n'
          'run: flutter test',
    );
    _write(
      repository,
      'pubspec.yaml',
      'environment:\n'
          '  sdk: ">=3.12.0 <4.0.0"\n'
          '  flutter: ">=3.46.0"',
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('.fvmrc Flutter version must be exactly 3.47.0'),
        contains('VS Code Flutter SDK path must be exactly'),
        contains('GitHub Actions Flutter version must be exactly 3.47.0'),
        contains('must resolve the committed Pub lockfile'),
        contains('analysis must not re-resolve dependencies'),
        contains('tests must not re-resolve dependencies'),
        contains('must require Dart >=3.13.0 <4.0.0'),
        contains('must require Flutter >=3.47.0'),
      ]),
    );
  });

  test('rejects build tools from another compile SDK generation', () {
    _write(
      repository,
      'android/app/build.gradle.kts',
      File('${repository.path}/android/app/build.gradle.kts')
          .readAsStringSync()
          .replaceFirst('36.0.0', '35.0.0'),
    );
    _write(
      repository,
      'flake.nix',
      File('${repository.path}/flake.nix')
          .readAsStringSync()
          .replaceAll('36.0.0', '35.0.0'),
    );
    _write(
      repository,
      'docs/DEVELOPMENT.md',
      File('${repository.path}/docs/DEVELOPMENT.md')
          .readAsStringSync()
          .replaceFirst('36.0.0', '35.0.0'),
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains('Android build tools 35.0.0 must match compile SDK 36.'),
    );
  });

  test('rejects unpinned Make dependency resolution', () {
    _write(repository, 'Makefile', 'dependencies:\n\tfvm flutter pub get');

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains(
        'Makefile dependency setup must enforce the committed Pub lockfile.',
      ),
    );
  });

  test('rejects malformed Flutter version metadata', () {
    flutterVersionMetadata.writeAsStringSync('{malformed');

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains('Flutter version metadata must contain one JSON object.'),
    );
  });

  test('fails closed when Flutter metadata is unavailable', () {
    final result = verifyToolchain(
      repositoryRoot: repository,
      flutterVersionMetadata: null,
      flutterExtension: null,
      flutterGradleUtils: null,
    );

    expect(result.passed, isFalse);
    expect(result.flutterVersion, isNull);
    expect(result.flutterNdkVersion, isNull);
    expect(
      result.failures,
      containsAll([
        'Missing Flutter Gradle extension.',
        'Missing Flutter Gradle utilities.',
        'Missing Flutter version metadata.',
      ]),
    );
  });
}

ToolchainVerification _verify(
  Directory repository,
  File flutterVersionMetadata,
  File flutterExtension,
  File flutterGradleUtils,
) {
  return verifyToolchain(
    repositoryRoot: repository,
    flutterVersionMetadata: flutterVersionMetadata,
    flutterExtension: flutterExtension,
    flutterGradleUtils: flutterGradleUtils,
  );
}

File _write(Directory root, String path, String contents) {
  final file = File('${root.path}/$path');
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}
