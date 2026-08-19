import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory root;
  late Directory bin;
  late Directory sdk;
  late File adbLog;
  late File fvmLog;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('utexo_android_wrapper_');
    bin = Directory('${root.path}/bin')..createSync();
    sdk = Directory('${root.path}/sdk')..createSync();
    adbLog = File('${root.path}/adb.log');
    fvmLog = File('${root.path}/fvm.log');
    await _writeExecutable(File('${bin.path}/fvm'), '''#!/bin/sh
printf '%s\n' "\$*" >> "\${UTEXO_TEST_FVM_LOG}"
if [ "\$1 \$2 \$3" = "flutter pub get" ]; then
  exit 0
fi
if [ "\$1 \$2" = "flutter drive" ]; then
  exit 17
fi
exit 99
''');
    await _writeExecutable(File('${sdk.path}/platform-tools/adb'), '''#!/bin/sh
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

  test(
    'preserves failed drive status and force-stops only debug identity',
    () async {
      final result = await runTestProcess(
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

      expect(result.exitCode, 17, reason: result.stderr);
      final commands = adbLog.readAsLinesSync();
      expect(
        commands,
        contains(
          '-s test-device shell am force-stop com.example.asterdev.debug',
        ),
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
    },
  );

  test('fails before launch when release identity cannot be queried', () async {
    final result = await runTestProcess(
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
      result.stderr,
      contains('could not inspect the release package before'),
    );
    expect(fvmLog.existsSync(), isFalse);
  });

  test(
    'fails before launch when release identity output is malformed',
    () async {
      final result = await runTestProcess(
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
        result.stderr,
        contains('could not inspect the release package before'),
      );
      expect(fvmLog.existsSync(), isFalse);
    },
  );
}

Future<void> _writeExecutable(File file, String contents) async {
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  await makeTestExecutable(file);
}
