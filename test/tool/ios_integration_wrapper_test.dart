import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory bin;
  late File bundleLog;
  late File xcrunLog;
  late File listAppsCount;
  late File installedDebugMarker;

  setUp(() {
    root = Directory.systemTemp.createTempSync('utexo_ios_wrapper_');
    bin = Directory('${root.path}/bin')..createSync();
    bundleLog = File('${root.path}/bundle.log');
    xcrunLog = File('${root.path}/xcrun.log');
    listAppsCount = File('${root.path}/listapps-count');
    installedDebugMarker = File('${root.path}/debug-installed');

    final scripts = Directory('${root.path}/scripts')..createSync();
    File('scripts/run-ios-integration-test.sh')
        .copySync('${scripts.path}/run-ios-integration-test.sh');
    File('${root.path}/integration_test/wallet_storage_security_test.dart')
        .createSync(recursive: true);
    File('${root.path}/build/ios/iphonesimulator/Runner.app/Info.plist')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '{ CFBundleIdentifier = "com.example.asterdev.debug"; }',
      );

    _writeExecutable(File('${bin.path}/bundle'), r'''#!/bin/sh
printf '%s\n' "$*" >> "${UTEXO_TEST_BUNDLE_LOG}"
case "$*" in
  "--version")
    printf '4.0.10\n'
    ;;
  "check")
    ;;
  "exec fvm flutter pub get --enforce-lockfile")
    ;;
  "exec fvm flutter test --no-pub integration_test/wallet_storage_security_test.dart -d test-simulator")
    exit "${UTEXO_TEST_TEST_STATUS:-17}"
    ;;
  "exec fvm flutter build ios --simulator --debug --no-pub")
    ;;
  *)
    exit 98
    ;;
esac
''');
    _writeExecutable(File('${bin.path}/xcrun'), r'''#!/bin/sh
printf '%s\n' "$*" >> "${UTEXO_TEST_XCRUN_LOG}"
case "$*" in
  "simctl getenv test-simulator SIMULATOR_UDID")
    printf 'test-simulator\n'
    ;;
  "simctl listapps test-simulator")
    count=0
    if [ -f "${UTEXO_TEST_LISTAPPS_COUNT}" ]; then
      count="$(cat "${UTEXO_TEST_LISTAPPS_COUNT}")"
    fi
    count=$((count + 1))
    printf '%s' "${count}" > "${UTEXO_TEST_LISTAPPS_COUNT}"
    if [ "${UTEXO_TEST_FAIL_LISTAPPS_CALL:-}" = "${count}" ]; then
      exit 42
    fi
    if [ "${UTEXO_TEST_LISTAPPS_MODE:-}" = "malformed" ]; then
      printf 'not a plist\n'
      exit 0
    fi
    printf '{\n'
    if [ "${UTEXO_TEST_LISTAPPS_MODE:-}" = "missing-path" ]; then
      printf '  "com.example.asterdev" = { };\n'
    elif [ "${UTEXO_TEST_LISTAPPS_MODE:-}" = "present" ]; then
      printf '  "com.example.asterdev" = { Path = "/Applications/Release.app"; };\n'
    fi
    if [ -f "${UTEXO_TEST_INSTALLED_DEBUG_MARKER}" ]; then
      printf '  "com.example.asterdev.debug" = { Path = "/Applications/Debug.app"; };\n'
    fi
    printf '}\n'
    ;;
  "simctl install test-simulator "*)
    : > "${UTEXO_TEST_INSTALLED_DEBUG_MARKER}"
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

  ProcessResult run({
    String listAppsMode = 'empty',
    String? failListAppsCall,
    int testStatus = 17,
  }) {
    return Process.runSync(
      'bash',
      [
        'scripts/run-ios-integration-test.sh',
        'integration_test/wallet_storage_security_test.dart',
        'test-simulator',
      ],
      workingDirectory: root.path,
      environment: <String, String>{
        ...Platform.environment,
        'UTEXO_TEST_BUNDLE_LOG': bundleLog.path,
        'UTEXO_TEST_XCRUN_LOG': xcrunLog.path,
        'UTEXO_TEST_LISTAPPS_COUNT': listAppsCount.path,
        'UTEXO_TEST_INSTALLED_DEBUG_MARKER': installedDebugMarker.path,
        'UTEXO_TEST_LISTAPPS_MODE': listAppsMode,
        'UTEXO_TEST_FAIL_LISTAPPS_CALL': ?failListAppsCall,
        'UTEXO_TEST_TEST_STATUS': '$testStatus',
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );
  }

  test('fails before Flutter work when listapps transport fails', () {
    final result = run(failListAppsCall: '1');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release bundle before'));
    expect(
      bundleLog.readAsLinesSync(),
      isNot(contains(startsWith('exec fvm flutter pub get'))),
    );
  });

  test('fails before Flutter work when listapps output is malformed', () {
    final result = run(listAppsMode: 'malformed');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release bundle before'));
    expect(
      bundleLog.readAsLinesSync(),
      isNot(contains(startsWith('exec fvm flutter pub get'))),
    );
  });

  test('rejects an installed release bundle without a path', () {
    final result = run(listAppsMode: 'missing-path');

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release bundle before'));
  });

  test('accepts an absent release app and preserves test failure status', () {
    final result = run();

    expect(result.exitCode, 17);
    expect(
      bundleLog.readAsLinesSync(),
      contains('exec fvm flutter build ios --simulator --debug --no-pub'),
    );
    expect(
      xcrunLog.readAsLinesSync(),
      contains(startsWith('simctl install test-simulator ')),
    );
  });

  test('fails when the post-run release query fails', () {
    final result = run(
      listAppsMode: 'present',
      failListAppsCall: '2',
      testStatus: 0,
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release bundle after the integration'));
  });

  test('fails when the installed debug query fails', () {
    final result = run(failListAppsCall: '3', testStatus: 0);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('installed debug bundle'));
  });

  test('fails when the post-install release query fails', () {
    final result = run(failListAppsCall: '4', testStatus: 0);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('release bundle after debug installation'));
  });

  test('completes with exact debug and preserved release identities', () {
    final result = run(listAppsMode: 'present', testStatus: 0);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('used com.example.asterdev.debug'));
    expect(listAppsCount.readAsStringSync(), '4');
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
