import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('utexo_bounded_shell_');
    for (final relativePath in <String>[
      'scripts/bounded-command.sh',
      'tool/run_bounded_command.dart',
      'tool/bounded_process.dart',
    ]) {
      final target = File('${fixture.path}/$relativePath');
      target.parent.createSync(recursive: true);
      File('${Directory.current.path}/$relativePath').copySync(target.path);
    }
    linkTestDartRuntime(fixture);
  });

  tearDown(() {
    fixture.deleteSync(recursive: true);
  });

  Future<BoundedProcessResult> runSource(
    String body, {
    Map<String, String>? environment,
  }) {
    return runTestProcess(
      '/bin/bash',
      <String>['--noprofile', '--norc', '-p', '-c', body],
      workingDirectory: fixture.path,
      environment: <String, String>{...Platform.environment, ...?environment},
      timeout: const Duration(seconds: 8),
      maxStdoutBytes: 8192,
      maxStderrBytes: 8192,
    );
  }

  test('reinitializes instead of trusting an inherited guard', () async {
    final result = await runSource(
      r'''
source scripts/bounded-command.sh
utexo_bounded_capture 2 8 8 -- /bin/sh -c "printf 123456789"
''',
      environment: const <String, String>{
        'UTEXO_BOUNDED_COMMAND_LOADED': 'inherited-bypass',
      },
    );

    expect(result.exitCode, 125);
    expect(result.stderr, contains('stdout byte ceiling'));
  });

  test('allows repeated sourcing only after local initialization', () async {
    final result = await runSource(r'''
source scripts/bounded-command.sh
source scripts/bounded-command.sh
utexo_capture_quick /bin/sh -c "printf ready"
''');

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, 'ready');
  });

  test('rejects direct execution of the source-only boundary', () async {
    final result = await runTestProcess(
      '/bin/bash',
      <String>['scripts/bounded-command.sh'],
      workingDirectory: fixture.path,
      timeout: const Duration(seconds: 5),
      maxStdoutBytes: 4096,
      maxStderrBytes: 4096,
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('must be sourced'));
  });
}
