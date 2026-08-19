import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory root;
  late Directory bin;
  late File bundleLog;
  late File xcrunLog;
  late File listAppsCount;
  late File installedDebugMarker;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('aster_ios_wrapper_');
    bin = Directory('${root.path}/bin')..createSync();
    bundleLog = File('${root.path}/bundle.log');
    xcrunLog = File('${root.path}/xcrun.log');
    listAppsCount = File('${root.path}/listapps-count');
    installedDebugMarker = File('${root.path}/debug-installed');

    final scripts = Directory('${root.path}/scripts')..createSync();
    File('scripts/run-ios-integration-test.sh')
        .copySync('${scripts.path}/run-ios-integration-test.sh');
    File('scripts/bounded-command.sh')
        .copySync('${scripts.path}/bounded-command.sh');
    Directory('${root.path}/tool').createSync();
    File('tool/run_bounded_command.dart')
        .copySync('${root.path}/tool/run_bounded_command.dart');
    File('tool/bounded_process.dart')
        .copySync('${root.path}/tool/bounded_process.dart');
    linkTestDartRuntime(root);
    File('${root.path}/integration_test/wallet_storage_security_test.dart')
        .createSync(recursive: true);
    File('${root.path}/build/ios/iphonesimulator/Runner.app/Info.plist')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '{ CFBundleIdentifier = "com.example.asterdev.debug"; }',
      );

    await _writeExecutable(File('${bin.path}/bundle'), r'''#!/bin/sh
printf '%s\n' "$*" >> "${ASTER_TEST_BUNDLE_LOG}"
case "$*" in
  "--version")
    printf '4.0.10\n'
    ;;
  "check")
    ;;
  "exec fvm flutter pub get --enforce-lockfile")
    ;;
  "exec fvm flutter test --no-pub integration_test/wallet_storage_security_test.dart -d test-simulator")
    exit "${ASTER_TEST_TEST_STATUS:-17}"
    ;;
  "exec fvm flutter build ios --simulator --debug --no-pub")
    ;;
  *)
    exit 98
    ;;
esac
''');
    await _writeExecutable(File('${bin.path}/xcrun'), r'''#!/bin/sh
printf '%s\n' "$*" >> "${ASTER_TEST_XCRUN_LOG}"
case "$*" in
  "simctl getenv test-simulator SIMULATOR_UDID")
    printf 'test-simulator\n'
    ;;
  "simctl listapps test-simulator")
    count=0
    if [ -f "${ASTER_TEST_LISTAPPS_COUNT}" ]; then
      count="$(cat "${ASTER_TEST_LISTAPPS_COUNT}")"
    fi
    count=$((count + 1))
    printf '%s' "${count}" > "${ASTER_TEST_LISTAPPS_COUNT}"
    if [ "${ASTER_TEST_FAIL_LISTAPPS_CALL:-}" = "${count}" ]; then
      exit 42
    fi
    if [ "${ASTER_TEST_LISTAPPS_MODE:-}" = "malformed" ]; then
      printf 'not a plist\n'
      exit 0
    fi
    printf '{\n'
    if [ "${ASTER_TEST_LISTAPPS_MODE:-}" = "missing-path" ]; then
      printf '  "com.example.asterdev" = { };\n'
    elif [ "${ASTER_TEST_LISTAPPS_MODE:-}" = "present" ]; then
      printf '  "com.example.asterdev" = { Path = "/Applications/Release.app"; };\n'
    fi
    if [ -f "${ASTER_TEST_INSTALLED_DEBUG_MARKER}" ]; then
      printf '  "com.example.asterdev.debug" = { Path = "/Applications/Debug.app"; };\n'
    fi
    printf '}\n'
    ;;
  "simctl install test-simulator "*)
    : > "${ASTER_TEST_INSTALLED_DEBUG_MARKER}"
    ;;
  *)
    exit 99
    ;;
esac
''');
    await _writeExecutable(File('${bin.path}/plutil'), r'''#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  -lint)
    readonly contents="$(<"$2")"
    [[ "${contents}" == \{* && "${contents}" == *\} ]] || exit 1
    ;;
  -extract)
    readonly key="$2"
    [[ "$3" == raw ]] || exit 64
    if [[ "${4:-}" == -- ]]; then
      readonly plist="$5"
    else
      readonly plist="$4"
    fi
    readonly contents="$(<"${plist}")"
    case "${key}" in
      'com\.example\.asterdev.Path')
        [[ "${contents}" == *'"com.example.asterdev" = { Path = "/Applications/Release.app"; };'* ]] || exit 1
        printf '/Applications/Release.app\n'
        ;;
      'com\.example\.asterdev\.debug.Path')
        [[ "${contents}" == *'"com.example.asterdev.debug" = { Path = "/Applications/Debug.app"; };'* ]] || exit 1
        printf '/Applications/Debug.app\n'
        ;;
      CFBundleIdentifier)
        [[ "${contents}" == *'CFBundleIdentifier = "com.example.asterdev.debug";'* ]] || exit 1
        printf 'com.example.asterdev.debug\n'
        ;;
      *) exit 1 ;;
    esac
    ;;
  -type)
    readonly key="$2"
    readonly contents="$(<"$3")"
    case "${key}" in
      'com\.example\.asterdev' | 'com.example.asterdev')
        [[ "${contents}" == *'"com.example.asterdev" = {'* ]] || exit 1
        ;;
      'com\.example\.asterdev\.debug' | 'com.example.asterdev.debug')
        [[ "${contents}" == *'"com.example.asterdev.debug" = {'* ]] || exit 1
        ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 64 ;;
esac
''');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  Future<BoundedProcessResult> run({
    String listAppsMode = 'empty',
    String? failListAppsCall,
    int testStatus = 17,
  }) {
    return runTestProcess(
      'bash',
      [
        'scripts/run-ios-integration-test.sh',
        'integration_test/wallet_storage_security_test.dart',
        'test-simulator',
      ],
      workingDirectory: root.path,
      environment: <String, String>{
        ...Platform.environment,
        'ASTER_TEST_BUNDLE_LOG': bundleLog.path,
        'ASTER_TEST_XCRUN_LOG': xcrunLog.path,
        'ASTER_TEST_LISTAPPS_COUNT': listAppsCount.path,
        'ASTER_TEST_INSTALLED_DEBUG_MARKER': installedDebugMarker.path,
        'ASTER_TEST_LISTAPPS_MODE': listAppsMode,
        'ASTER_TEST_FAIL_LISTAPPS_CALL': ?failListAppsCall,
        'ASTER_TEST_TEST_STATUS': '$testStatus',
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );
  }

  test('fails before Flutter work when listapps transport fails', () async {
    final result = await run(failListAppsCall: '1');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release bundle before'));
    expect(
      bundleLog.readAsLinesSync(),
      isNot(contains(startsWith('exec fvm flutter pub get'))),
    );
  });

  test('fails before Flutter work when listapps output is malformed', () async {
    final result = await run(listAppsMode: 'malformed');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release bundle before'));
    expect(
      bundleLog.readAsLinesSync(),
      isNot(contains(startsWith('exec fvm flutter pub get'))),
    );
  });

  test('rejects an installed release bundle without a path', () async {
    final result = await run(listAppsMode: 'missing-path');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release bundle before'));
  });

  test(
    'accepts an absent release app and preserves test failure status',
    () async {
      final result = await run();

      expect(result.exitCode, 17);
      expect(
        bundleLog.readAsLinesSync(),
        contains('exec fvm flutter build ios --simulator --debug --no-pub'),
      );
      expect(
        xcrunLog.readAsLinesSync(),
        contains(startsWith('simctl install test-simulator ')),
      );
    },
  );

  test('fails when the post-run release query fails', () async {
    final result = await run(
      listAppsMode: 'present',
      failListAppsCall: '2',
      testStatus: 0,
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release bundle after the integration'));
  });

  test('fails when the installed debug query fails', () async {
    final result = await run(failListAppsCall: '3', testStatus: 0);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('installed debug bundle'));
  });

  test('fails when the post-install release query fails', () async {
    final result = await run(failListAppsCall: '4', testStatus: 0);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release bundle after debug installation'));
  });

  test('completes with exact debug and preserved release identities', () async {
    final result = await run(listAppsMode: 'present', testStatus: 0);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('used com.example.asterdev.debug'));
    expect(listAppsCount.readAsStringSync(), '4');
  });
}

Future<void> _writeExecutable(File file, String contents) async {
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  await makeTestExecutable(file);
}
