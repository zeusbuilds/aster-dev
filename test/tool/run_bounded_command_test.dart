import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late String dart;
  late String runner;

  setUpAll(() {
    dart = testDartExecutable();
    runner = '${Directory.current.path}/tool/run_bounded_command.dart';
  });

  Future<({int exitCode, String stdout, String stderr})> run(
    List<String> command, {
    int timeoutSeconds = 5,
    int maxStdoutBytes = 4096,
    int maxStderrBytes = 4096,
    bool streamOutput = false,
  }) async {
    final result = await runTestProcess(
      dart,
      <String>[
        '--disable-dart-dev',
        runner,
        '--timeout-seconds',
        '$timeoutSeconds',
        '--max-stdout-bytes',
        '$maxStdoutBytes',
        '--max-stderr-bytes',
        '$maxStderrBytes',
        if (streamOutput) '--stream-output',
        '--',
        ...command,
      ],
      timeout: Duration(seconds: timeoutSeconds + 5),
      maxStdoutBytes: maxStdoutBytes + 4096,
      maxStderrBytes: maxStderrBytes + 4096,
    );
    return (
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  test('preserves output and child exit status in capture mode', () async {
    final result = await run(<String>[
      '/bin/sh',
      '-c',
      'printf output; printf failure >&2; exit 17',
    ]);

    expect(result.exitCode, 17);
    expect(result.stdout, 'output');
    expect(result.stderr, 'failure');
  });

  test('forwards output once in stream mode', () async {
    final result = await run(<String>[
      '/bin/sh',
      '-c',
      'printf output; printf failure >&2',
    ], streamOutput: true);

    expect(result.exitCode, 0);
    expect(result.stdout, 'output');
    expect(result.stderr, 'failure');
  });

  test('maps a deadline to a stable redacted status', () async {
    const secret = 'deadline-secret-argument';
    final result = await run(<String>[
      '/bin/sh',
      '-c',
      'sleep 30',
      secret,
    ], timeoutSeconds: 1);

    expect(result.exitCode, 124);
    expect(result.stderr, contains('1-second deadline'));
    expect(result.stderr, isNot(contains(secret)));
  });

  test('maps an output overflow to a stable redacted status', () async {
    final result = await run(<String>[
      '/bin/sh',
      '-c',
      "printf '123456789'",
    ], maxStdoutBytes: 8);

    expect(result.exitCode, 125);
    expect(result.stderr, contains('stdout byte ceiling'));
    expect(result.stderr, isNot(contains('123456789')));
  });

  test('rejects malformed UTF-8 without replaying bytes', () async {
    final directory = Directory.systemTemp.createTempSync(
      'utexo_bounded_command_utf8_',
    );
    try {
      final fixture = File('${directory.path}/fixture.dart')
        ..writeAsStringSync(
          "import 'dart:io';\n"
          'void main() => stdout.add(const <int>[0xff]);\n',
        );
      final result = await run(<String>[
        dart,
        '--disable-dart-dev',
        fixture.path,
      ]);

      expect(result.exitCode, 65);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('malformed UTF-8'));
    } finally {
      directory.deleteSync(recursive: true);
    }
  });

  test('rejects invalid policy without exposing later arguments', () async {
    const secret = 'invalid-policy-secret';
    final result = await runTestProcess(
      dart,
      <String>[
        '--disable-dart-dev',
        runner,
        '--timeout-seconds',
        '0',
        '--max-stdout-bytes',
        '1',
        '--max-stderr-bytes',
        '1',
        '--',
        secret,
      ],
      timeout: const Duration(seconds: 5),
      maxStdoutBytes: 4096,
      maxStderrBytes: 4096,
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Invalid bounded-command invocation'));
    expect(result.stderr, isNot(contains(secret)));
  });
}
