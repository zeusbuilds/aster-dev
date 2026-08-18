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

Future<BoundedProcessResult> _runDart(
  String body, {
  int maxStdoutBytes = 4096,
  int maxStderrBytes = 4096,
  Duration timeout = const Duration(seconds: 2),
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
