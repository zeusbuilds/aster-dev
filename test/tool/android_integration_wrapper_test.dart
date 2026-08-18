import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory bin;
  late Directory sdk;
  late File adbLog;
  late File fvmLog;

  setUp(() {
    root = Directory.systemTemp.createTempSync('utexo_android_wrapper_');
    bin = Directory('${root.path}/bin')..createSync();
    sdk = Directory('${root.path}/sdk')..createSync();
    adbLog = File('${root.path}/adb.log');
    fvmLog = File('${root.path}/fvm.log');
    _writeExecutable(File('${bin.path}/fvm'), '''#!/bin/sh
printf '%s\n' "\$*" >> "\${UTEXO_TEST_FVM_LOG}"
if [ "\$1 \$2 \$3" = "flutter pub get" ]; then
  exit 0
fi
if [ "\$1 \$2" = "flutter drive" ]; then
  exit 17
fi
exit 99
''');
    _writeExecutable(File('${sdk.path}/platform-tools/adb'), '''#!/bin/sh
printf '%s\n' "\$*" >> "\${UTEXO_TEST_ADB_LOG}"
case "\$*" in
  "-s test-device get-state")
    printf 'device\n'
    ;;
  "-s test-device shell pm path com.example.asterdev")
    if [ "\${UTEXO_TEST_FAIL_RELEASE_QUERY:-}" = "1" ]; then
      exit 42
    fi
    if [ "\${UTEXO_TEST_MALFORMED_RELEASE_QUERY:-}" = "1" ]; then
      printf 'Error: package manager unavailable\n'
      exit 0
    fi
    printf 'package:/release/base.apk\n'
    ;;
  "-s test-device shell pm path com.example.asterdev.debug")
    printf 'package:/debug/base.apk\n'
    ;;
  "-s test-device shell am force-stop com.example.asterdev.debug")
    ;;
  *)
    exit 98
    ;;
esac
''');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('preserves failed drive status and force-stops only debug identity', () {
    final result = Process.runSync(
      'bash',
      [
        'scripts/run-android-integration-test.sh',
        'integration_test/wallet_storage_security_test.dart',
        'test-device',
      ],
      workingDirectory: Directory.current.path,
      environment: {
        ...Platform.environment,
        'ANDROID_SDK_ROOT': sdk.path,
        'UTEXO_TEST_ADB_LOG': adbLog.path,
        'UTEXO_TEST_FVM_LOG': fvmLog.path,
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );

    expect(result.exitCode, 17, reason: '${result.stderr}');
    final commands = adbLog.readAsLinesSync();
    expect(
      commands,
      contains('-s test-device shell am force-stop com.example.asterdev.debug'),
    );
    expect(
      commands.where(
        (command) =>
            command == '-s test-device shell pm path com.example.asterdev',
      ),
      hasLength(2),
    );
    expect(
      commands.where((command) => command.contains('force-stop')),
      hasLength(1),
    );
  });

  test('fails before launch when release identity cannot be queried', () {
    final result = Process.runSync(
      'bash',
      [
        'scripts/run-android-integration-test.sh',
        'integration_test/wallet_storage_security_test.dart',
        'test-device',
      ],
      workingDirectory: Directory.current.path,
      environment: {
        ...Platform.environment,
        'ANDROID_SDK_ROOT': sdk.path,
        'UTEXO_TEST_ADB_LOG': adbLog.path,
        'UTEXO_TEST_FVM_LOG': fvmLog.path,
        'UTEXO_TEST_FAIL_RELEASE_QUERY': '1',
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );

    expect(result.exitCode, 64);
    expect(
      '${result.stderr}',
      contains('could not inspect the release package before'),
    );
    expect(fvmLog.existsSync(), isFalse);
  });

  test('fails before launch when release identity output is malformed', () {
    final result = Process.runSync(
      'bash',
      [
        'scripts/run-android-integration-test.sh',
        'integration_test/wallet_storage_security_test.dart',
        'test-device',
      ],
      workingDirectory: Directory.current.path,
      environment: {
        ...Platform.environment,
        'ANDROID_SDK_ROOT': sdk.path,
        'UTEXO_TEST_ADB_LOG': adbLog.path,
        'UTEXO_TEST_FVM_LOG': fvmLog.path,
        'UTEXO_TEST_MALFORMED_RELEASE_QUERY': '1',
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );

    expect(result.exitCode, 64);
    expect(
      '${result.stderr}',
      contains('could not inspect the release package before'),
    );
    expect(fvmLog.existsSync(), isFalse);
  });
}

void _writeExecutable(File file, String contents) {
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  final chmod = Process.runSync('chmod', ['755', file.path]);
  if (chmod.exitCode != 0) {
    throw StateError('Could not make ${file.path} executable: ${chmod.stderr}');
  }
}
