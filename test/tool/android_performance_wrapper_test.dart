import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory bin;
  late Directory sdk;
  late File adbLog;
  late File fvmLog;
  late File releaseQueryCount;
  late File debugQueryCount;
  late File profileQueryCount;

  setUp(() {
    root = Directory.systemTemp.createTempSync('utexo_performance_wrapper_');
    bin = Directory('${root.path}/bin')..createSync();
    sdk = Directory('${root.path}/sdk')..createSync();
    adbLog = File('${root.path}/adb.log');
    fvmLog = File('${root.path}/fvm.log');
    releaseQueryCount = File('${root.path}/release-query-count');
    debugQueryCount = File('${root.path}/debug-query-count');
    profileQueryCount = File('${root.path}/profile-query-count');
    _writeExecutable(File('${bin.path}/fvm'), r'''#!/bin/sh
printf '%s\n' "$*" >> "${UTEXO_TEST_FVM_LOG}"
if [ "$1 $2 $3" = "flutter pub get" ]; then
  exit 0
fi
if [ "$1 $2" = "flutter drive" ]; then
  exit "${UTEXO_TEST_DRIVE_STATUS:-17}"
fi
exit 99
''');
    _writeExecutable(File('${sdk.path}/platform-tools/adb'), r'''#!/bin/sh
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

  ProcessResult run({
    String? failReleaseQueryCall,
    String? failDebugQueryCall,
    String? failProfileQueryCall,
    int driveStatus = 17,
    bool malformedReleaseQuery = false,
  }) {
    return Process.runSync(
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

  test('fails before measurement when release identity query fails', () {
    final result = run(failReleaseQueryCall: '1');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release package before measurement'));
    expect(fvmLog.existsSync(), isFalse);
  });

  test('fails before measurement when Profile state cannot be queried', () {
    final result = run(failProfileQueryCall: '1');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('could not reset the isolated profile'));
    expect(fvmLog.existsSync(), isFalse);
  });

  test('fails before measurement when package output is malformed', () {
    final result = run(malformedReleaseQuery: true);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release package before measurement'));
    expect(fvmLog.existsSync(), isFalse);
  });

  test('fails before measurement when debug identity query fails', () {
    final result = run(failDebugQueryCall: '1');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('debug package before measurement'));
    expect(fvmLog.existsSync(), isFalse);
  });

  test('reports cleanup query failure without replacing drive status', () {
    final result = run(failReleaseQueryCall: '2');

    expect(result.exitCode, 17);
    expect(result.stderr, contains('release package during cleanup'));
    expect(fvmLog.readAsLinesSync(), contains(startsWith('flutter drive')));
  });

  test(
    'reports cleanup debug-query failure without replacing drive status',
    () {
      final result = run(failDebugQueryCall: '2');

      expect(result.exitCode, 17);
      expect(result.stderr, contains('debug package during cleanup'));
    },
  );

  test('fails after measurement when Profile identity query fails', () {
    final result = run(failProfileQueryCall: '2', driveStatus: 0);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Profile package after measurement'));
    expect(fvmLog.readAsLinesSync(), contains(startsWith('flutter drive')));
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
