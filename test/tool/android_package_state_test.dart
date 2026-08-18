import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File adb;
  late File adbLog;

  setUp(() {
    root = Directory.systemTemp.createTempSync('utexo_android_package_state_');
    adb = File('${root.path}/adb');
    adbLog = File('${root.path}/adb.log');
    _writeExecutable(adb, r'''#!/bin/sh
printf '%s\n' "$*" >> "${UTEXO_TEST_ADB_LOG}"
case "${UTEXO_TEST_PACKAGE_MODE:-absent}" in
  absent)
    ;;
  paths)
    printf 'package:/z/base.apk\r\npackage:/a/base.apk\r\npackage:/z/base.apk\r\n'
    ;;
  malformed)
    printf 'Error: package manager unavailable\n'
    ;;
  embedded-cr)
    printf 'pack\rage:/release/base.apk\n'
    ;;
  oversized)
    awk 'BEGIN {
      printf "package:/"
      for (i = 0; i < 70000; i++) printf "a"
      printf "\n"
    }'
    ;;
  failure)
    exit 42
    ;;
  *)
    exit 99
    ;;
esac
''');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  ProcessResult run(String mode, {String packageName = 'com.example.app'}) {
    const command =
        'set -euo pipefail; '
        'source scripts/android-package-state.sh; '
        'utexo_android_package_paths "\$1" test-device "\$2"';
    return Process.runSync(
      'bash',
      ['-c', command, 'android-package-state-test', adb.path, packageName],
      workingDirectory: Directory.current.path,
      environment: <String, String>{
        ...Platform.environment,
        'UTEXO_TEST_ADB_LOG': adbLog.path,
        'UTEXO_TEST_PACKAGE_MODE': mode,
      },
    );
  }

  test('distinguishes an absent package from query failure', () {
    final absent = run('absent');
    final failed = run('failure');

    expect(absent.exitCode, 0);
    expect(absent.stdout, isEmpty);
    expect(failed.exitCode, isNonZero);
  });

  test('normalizes CRLF paths into one sorted exact set', () {
    final result = run('paths');

    expect(result.exitCode, 0);
    expect(result.stdout, 'package:/a/base.apk\npackage:/z/base.apk\n');
  });

  test('rejects successful diagnostic output as malformed', () {
    final result = run('malformed');

    expect(result.exitCode, isNonZero);
    expect(result.stdout, isEmpty);
  });

  test('does not repair embedded control bytes during CRLF normalization', () {
    final result = run('embedded-cr');

    expect(result.exitCode, isNonZero);
    expect(result.stdout, isEmpty);
  });

  test('rejects package-manager output above the owned byte limit', () {
    final result = run('oversized');

    expect(result.exitCode, isNonZero);
    expect(result.stdout, isEmpty);
  });

  test('rejects malformed package identities before invoking adb', () {
    final result = run('absent', packageName: '../release');

    expect(result.exitCode, 64);
    expect(adbLog.existsSync(), isFalse);
  });
}

void _writeExecutable(File file, String contents) {
  file.writeAsStringSync(contents);
  final chmod = Process.runSync('chmod', ['755', file.path]);
  if (chmod.exitCode != 0) {
    throw StateError('Could not make ${file.path} executable: ${chmod.stderr}');
  }
}
