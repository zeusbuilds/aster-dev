import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_toolchain.dart';

void main() {
  late Directory repository;
  late File flutterExtension;

  setUp(() {
    repository = Directory.systemTemp.createTempSync('utexo_toolchain_');
    flutterExtension = _write(
      repository,
      'flutter/packages/flutter_tools/gradle/src/main/kotlin/'
          'FlutterExtension.kt',
      'val ndkVersion: String = "28.2.13676358"',
    );
    _write(
      repository,
      'android/app/build.gradle.kts',
      'android { ndkVersion = flutter.ndkVersion }',
    );
    _write(
      repository,
      'flake.nix',
      'includeNDK = true;\nndkVersions = [ "28.2.13676358" ];',
    );
    _write(
      repository,
      'docs/DEVELOPMENT.md',
      '- Android NDK 28.2.13676358, matching Flutter',
    );
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
  });

  test('accepts one exact Flutter-owned NDK contract', () {
    final result = verifyToolchain(
      repositoryRoot: repository,
      flutterExtension: flutterExtension,
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.flutterNdkVersion, '28.2.13676358');
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
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must include the Android NDK'),
        contains('exactly Flutter NDK 28.2.13676358'),
      ]),
    );
  });

  test('rejects Android and documentation drift', () {
    _write(
      repository,
      'android/app/build.gradle.kts',
      'android { ndkVersion = "27.0.0" }',
    );
    _write(repository, 'docs/DEVELOPMENT.md', '- Android SDK 36');

    final result = verifyToolchain(
      repositoryRoot: repository,
      flutterExtension: flutterExtension,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must delegate ndkVersion to Flutter'),
        contains('must document Android NDK 28.2.13676358'),
      ]),
    );
  });

  test('fails closed when Flutter metadata is unavailable', () {
    final result = verifyToolchain(
      repositoryRoot: repository,
      flutterExtension: null,
    );

    expect(result.passed, isFalse);
    expect(result.flutterNdkVersion, isNull);
    expect(result.failures, contains('Missing Flutter Gradle extension.'));
  });
}

File _write(Directory root, String path, String contents) {
  final file = File('${root.path}/$path');
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}
