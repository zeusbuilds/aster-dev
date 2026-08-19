import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory root;
  late Directory bin;
  late Directory sdk;
  late File adbLog;
  late File fvmLog;
  late File releaseQueryCount;
  late File debugQueryCount;
  late File profileQueryCount;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('utexo_performance_wrapper_');
    bin = Directory('${root.path}/bin')..createSync();
    sdk = Directory('${root.path}/sdk')..createSync();
    adbLog = File('${root.path}/adb.log');
    fvmLog = File('${root.path}/fvm.log');
    releaseQueryCount = File('${root.path}/release-query-count');
    debugQueryCount = File('${root.path}/debug-query-count');
    profileQueryCount = File('${root.path}/profile-query-count');
    await _writeExecutable(File('${bin.path}/fvm'), r'''#!/bin/sh
printf '%s\n' "$*" >> "${UTEXO_TEST_FVM_LOG}"
if [ "$1 $2 $3" = "flutter pub get" ]; then
  exit 0
fi
if [ "$1 $2" = "flutter drive" ]; then
  exit "${UTEXO_TEST_DRIVE_STATUS:-17}"
fi
exit 99
''');
    await _writeExecutable(File('${sdk.path}/platform-tools/adb'), r'''#!/bin/sh
printf '%s\n' "$*" >> "${UTEXO_TEST_ADB_LOG}"
case "$*" in
  "-s test-device get-state")
    printf 'device\n'
    ;;
  "-s test-device shell dumpsys SurfaceFlinger")
    printf 'GLES: hardware renderer\n'
    ;;
  "-s test-device shell pm path com.example.asterdev")
    count=0
    if [ -f "${UTEXO_TEST_RELEASE_QUERY_COUNT}" ]; then
      count="$(cat "${UTEXO_TEST_RELEASE_QUERY_COUNT}")"
    fi
    count=$((count + 1))
    printf '%s' "${count}" > "${UTEXO_TEST_RELEASE_QUERY_COUNT}"
    if [ "${UTEXO_TEST_FAIL_RELEASE_QUERY_CALL:-}" = "${count}" ]; then
      exit 42
    fi
    if [ "${UTEXO_TEST_MALFORMED_RELEASE_QUERY:-}" = "1" ]; then
      printf 'Error: package manager unavailable\n'
      exit 0
    fi
    printf 'package:/release/base.apk\n'
    ;;
  "-s test-device shell pm path com.example.asterdev.debug")
    count=0
    if [ -f "${UTEXO_TEST_DEBUG_QUERY_COUNT}" ]; then
      count="$(cat "${UTEXO_TEST_DEBUG_QUERY_COUNT}")"
    fi
    count=$((count + 1))
    printf '%s' "${count}" > "${UTEXO_TEST_DEBUG_QUERY_COUNT}"
    if [ "${UTEXO_TEST_FAIL_DEBUG_QUERY_CALL:-}" = "${count}" ]; then
      exit 44
    fi
    printf 'package:/debug/base.apk\n'
    ;;
  "-s test-device shell pm path com.example.asterdev.profile")
    count=0
    if [ -f "${UTEXO_TEST_PROFILE_QUERY_COUNT}" ]; then
      count="$(cat "${UTEXO_TEST_PROFILE_QUERY_COUNT}")"
    fi
    count=$((count + 1))
    printf '%s' "${count}" > "${UTEXO_TEST_PROFILE_QUERY_COUNT}"
    if [ "${UTEXO_TEST_FAIL_PROFILE_QUERY_CALL:-}" = "${count}" ]; then
      exit 43
    fi
    if [ "${count}" -ge 2 ]; then
      printf 'package:/profile/base.apk\n'
    fi
    ;;
  "-s test-device shell am force-stop com.example.asterdev.profile")
    ;;
  "-s test-device shell pm clear com.example.asterdev.profile")
    printf 'Success\n'
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

  Future<BoundedProcessResult> run({
    String? failReleaseQueryCall,
    String? failDebugQueryCall,
    String? failProfileQueryCall,
    int driveStatus = 17,
    bool malformedReleaseQuery = false,
  }) {
    return runTestProcess(
      'bash',
      ['scripts/run-android-presentation-performance-test.sh', 'test-device'],
      workingDirectory: Directory.current.path,
      environment: <String, String>{
        ...Platform.environment,
        'ANDROID_SDK_ROOT': sdk.path,
        'UTEXO_TEST_ADB_LOG': adbLog.path,
        'UTEXO_TEST_FVM_LOG': fvmLog.path,
        'UTEXO_TEST_RELEASE_QUERY_COUNT': releaseQueryCount.path,
        'UTEXO_TEST_DEBUG_QUERY_COUNT': debugQueryCount.path,
        'UTEXO_TEST_PROFILE_QUERY_COUNT': profileQueryCount.path,
        'UTEXO_TEST_FAIL_RELEASE_QUERY_CALL': ?failReleaseQueryCall,
        'UTEXO_TEST_FAIL_DEBUG_QUERY_CALL': ?failDebugQueryCall,
        'UTEXO_TEST_FAIL_PROFILE_QUERY_CALL': ?failProfileQueryCall,
        'UTEXO_TEST_DRIVE_STATUS': '$driveStatus',
        if (malformedReleaseQuery) 'UTEXO_TEST_MALFORMED_RELEASE_QUERY': '1',
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );
  }

  test('fails before measurement when release identity query fails', () async {
    final result = await run(failReleaseQueryCall: '1');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release package before measurement'));
    expect(fvmLog.existsSync(), isFalse);
  });

  test(
    'fails before measurement when Profile state cannot be queried',
    () async {
      final result = await run(failProfileQueryCall: '1');

      expect(result.exitCode, 64);
      expect(result.stderr, contains('could not reset the isolated profile'));
      expect(fvmLog.existsSync(), isFalse);
    },
  );

  test('fails before measurement when package output is malformed', () async {
    final result = await run(malformedReleaseQuery: true);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release package before measurement'));
    expect(fvmLog.existsSync(), isFalse);
  });

  test('fails before measurement when debug identity query fails', () async {
    final result = await run(failDebugQueryCall: '1');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('debug package before measurement'));
    expect(fvmLog.existsSync(), isFalse);
  });

  test(
    'reports cleanup query failure without replacing drive status',
    () async {
      final result = await run(failReleaseQueryCall: '2');

      expect(result.exitCode, 17);
      expect(result.stderr, contains('release package during cleanup'));
      expect(fvmLog.readAsLinesSync(), contains(startsWith('flutter drive')));
    },
  );

  test(
    'reports cleanup debug-query failure without replacing drive status',
    () async {
      final result = await run(failDebugQueryCall: '2');

      expect(result.exitCode, 17);
      expect(result.stderr, contains('debug package during cleanup'));
    },
  );

  test('fails after measurement when Profile identity query fails', () async {
    final result = await run(failProfileQueryCall: '2', driveStatus: 0);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Profile package after measurement'));
    expect(fvmLog.readAsLinesSync(), contains(startsWith('flutter drive')));
  });
}

Future<void> _writeExecutable(File file, String contents) async {
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  await makeTestExecutable(file);
}
