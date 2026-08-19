import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bounded_process.dart';

void main() {
  test('captures bounded output and preserves a nonzero exit status', () async {
    final result = await _runDart(
      "stdout.write('out'); stderr.write('err'); exitCode = 7;",
    );

    expect(result.exitCode, 7);
    expect(result.stdout, 'out');
    expect(result.stderr, 'err');
  });

  test('process-tree supervision preserves normal output and status', () async {
    final result = await _runDart(
      "stdout.write('out'); stderr.write('err'); exitCode = 9;",
      killProcessTree: true,
    );

    expect(result.exitCode, 9);
    expect(result.stdout, 'out');
    expect(result.stderr, 'err');
  });

  test('forwards strictly decoded chunks without changing capture', () async {
    final forwardedStdout = StringBuffer();
    final forwardedStderr = StringBuffer();
    final result = await _runDart(
      "stdout.write('alpha'); stderr.write('beta');",
      onStdout: forwardedStdout.write,
      onStderr: forwardedStderr.write,
    );

    expect(result.stdout, 'alpha');
    expect(result.stderr, 'beta');
    expect(forwardedStdout.toString(), result.stdout);
    expect(forwardedStderr.toString(), result.stderr);
  });

  test('rejects stdout beyond its independent byte ceiling', () async {
    await expectLater(
      _runDart("stdout.write('123456789');", maxStdoutBytes: 8),
      throwsA(
        isA<ProcessOutputLimitException>()
            .having((error) => error.streamName, 'stream', 'stdout')
            .having((error) => error.maximumBytes, 'limit', 8),
      ),
    );
  });

  test('rejects stderr beyond its independent byte ceiling', () async {
    await expectLater(
      _runDart("stderr.write('123456789');", maxStderrBytes: 8),
      throwsA(
        isA<ProcessOutputLimitException>()
            .having((error) => error.streamName, 'stream', 'stderr')
            .having((error) => error.maximumBytes, 'limit', 8),
      ),
    );
  });

  test('force-terminates a subprocess at its deadline', () async {
    final stopwatch = Stopwatch()..start();

    await expectLater(
      _runDart(
        'await Future<void>.delayed(const Duration(seconds: 30));',
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(isA<ProcessDeadlineException>()),
    );

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test(
    'process-tree success terminates a surviving grandchild',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'utexo_process_tree_success_',
      );
      try {
        final fixture = _writeProcessTreeFixture(
          directory,
          grandchildDelay: const Duration(seconds: 2),
          parentDelay: Duration.zero,
        );

        final result = await runBoundedProcess(
          '/bin/sh',
          <String>[
            '-c',
            r'''"$1" "$2" "$3" "$4" &
while [ ! -e "$3" ]; do sleep 0.01; done
exit 0''',
            'utexo-process-tree-fixture',
            _dartExecutable(),
            fixture.grandchild.path,
            fixture.readyMarker.path,
            fixture.survivalMarker.path,
          ],
          killProcessTree: true,
          maxStdoutBytes: 4096,
          maxStderrBytes: 4096,
          timeout: const Duration(seconds: 5),
        );

        expect(result.exitCode, 0);
        expect(fixture.readyMarker.existsSync(), isTrue);
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(
          fixture.survivalMarker.existsSync(),
          isFalse,
          reason: 'A successful parent must not leave an owned descendant.',
        );
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
    skip: Platform.isWindows
        ? 'POSIX process-group supervision is unavailable on Windows.'
        : false,
  );

  test(
    'process-tree deadline terminates the parent and grandchild',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'utexo_process_tree_',
      );
      try {
        final fixture = _writeProcessTreeFixture(
          directory,
          grandchildDelay: const Duration(seconds: 4),
          parentDelay: const Duration(seconds: 30),
        );

        await expectLater(
          runBoundedProcess(
            _dartExecutable(),
            fixture.arguments,
            killProcessTree: true,
            maxStdoutBytes: 4096,
            maxStderrBytes: 4096,
            timeout: const Duration(seconds: 2),
          ),
          throwsA(isA<ProcessDeadlineException>()),
        );

        expect(
          fixture.readyMarker.existsSync(),
          isTrue,
          reason: 'The grandchild must start before the deadline is tested.',
        );
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(
          fixture.survivalMarker.existsSync(),
          isFalse,
          reason: 'No owned descendant may outlive a bounded failure.',
        );
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
    skip: Platform.isWindows
        ? 'POSIX process-group supervision is unavailable on Windows.'
        : false,
  );

  test(
    'rejects malformed UTF-8 instead of repairing inspector output',
    () async {
      await expectLater(
        _runDart('stdout.add(const <int>[0xff]);'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('redacts executable arguments when process launch fails', () async {
    const secretMarker = 'sensitive-artifact-path';

    Object? failure;
    try {
      await runBoundedProcess(
        '/definitely/missing/utexo-release-inspector',
        const [secretMarker],
        maxStdoutBytes: 1,
        maxStderrBytes: 1,
        timeout: const Duration(seconds: 1),
      );
    } on Object catch (error) {
      failure = error;
    }

    expect(failure, isA<ProcessLaunchException>());
    expect(failure.toString(), isNot(contains(secretMarker)));
  });

  test('rejects invalid resource policy before launching', () async {
    await expectLater(
      runBoundedProcess(
        '/bin/sh',
        const ['-c', 'exit 0'],
        maxStdoutBytes: 0,
        maxStderrBytes: 1,
        timeout: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
    await expectLater(
      runBoundedProcess(
        '/bin/sh',
        const ['-c', 'exit 0'],
        maxStdoutBytes: 1,
        maxStderrBytes: 1,
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}

({
  List<String> arguments,
  File grandchild,
  File readyMarker,
  File survivalMarker,
})
_writeProcessTreeFixture(
  Directory directory, {
  required Duration grandchildDelay,
  required Duration parentDelay,
}) {
  final readyMarker = File('${directory.path}/grandchild-ready');
  final survivalMarker = File('${directory.path}/grandchild-survived');
  final grandchild = File('${directory.path}/grandchild.dart')
    ..writeAsStringSync(
      "import 'dart:async';\n"
      "import 'dart:io';\n"
      'Future<void> main(List<String> arguments) async {\n'
      "  File(arguments[0]).writeAsStringSync('ready');\n"
      '  await Future<void>.delayed('
      'const Duration(milliseconds: ${grandchildDelay.inMilliseconds}));\n'
      "  File(arguments[1]).writeAsStringSync('survived');\n"
      '}\n',
    );
  final parent = File('${directory.path}/parent.dart')
    ..writeAsStringSync(
      "import 'dart:async';\n"
      "import 'dart:io';\n"
      'Future<void> main(List<String> arguments) async {\n'
      '  await Process.start(arguments[0], arguments.sublist(1));\n'
      '  while (!File(arguments[2]).existsSync()) {\n'
      '    await Future<void>.delayed(const Duration(milliseconds: 10));\n'
      '  }\n'
      '  await Future<void>.delayed('
      'const Duration(milliseconds: ${parentDelay.inMilliseconds}));\n'
      '}\n',
    );
  return (
    arguments: <String>[
      parent.path,
      _dartExecutable(),
      grandchild.path,
      readyMarker.path,
      survivalMarker.path,
    ],
    grandchild: grandchild,
    readyMarker: readyMarker,
    survivalMarker: survivalMarker,
  );
}

Future<BoundedProcessResult> _runDart(
  String body, {
  int maxStdoutBytes = 4096,
  int maxStderrBytes = 4096,
  Duration timeout = const Duration(seconds: 2),
  bool killProcessTree = false,
  ProcessOutputCallback? onStdout,
  ProcessOutputCallback? onStderr,
}) async {
  final directory = Directory.systemTemp.createTempSync('utexo_process_');
  try {
    final script = File('${directory.path}/fixture.dart')
      ..writeAsStringSync(
        "import 'dart:io';\n"
        'Future<void> main() async {\n'
        '$body\n'
        '}\n',
      );
    return await runBoundedProcess(
      _dartExecutable(),
      [script.path],
      killProcessTree: killProcessTree,
      onStdout: onStdout,
      onStderr: onStderr,
      maxStdoutBytes: maxStdoutBytes,
      maxStderrBytes: maxStderrBytes,
      timeout: timeout,
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
}

String _dartExecutable() {
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?)
      '$root/bin/cache/dart-sdk/bin/$executableName',
    '${Directory.current.path}/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/$executableName',
    Platform.resolvedExecutable,
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync() &&
        candidate.split(Platform.pathSeparator).last == executableName) {
      return candidate;
    }
  }
  throw StateError('The Dart executable could not be resolved for this test.');
}
