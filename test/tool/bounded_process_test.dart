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
        'aster_process_tree_success_',
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
            'aster-process-tree-fixture',
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
        'aster_process_tree_',
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

  for (final phase in [
    'registration',
    'cleanup',
    'interrupted-cleanup',
    'parent-death',
  ]) {
    test(
      '$phase cancellation closes the owned group and both streams',
      () async {
        final result = await _runSupervisorFixture(phase: phase);
        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.stdout, 'owned group and both streams closed\n');
        expect(result.stderr, isEmpty);
      },
      skip: Platform.isWindows,
    );
  }

  for (final mutation in <(String, String, String)>[
    ('missing READY', "os.write(status_fd, b'R')", "os.write(status_fd, b'X')"),
    ('short status', "struct.pack('!i', status)", "b'\\x00'"),
    (
      'trailing status',
      "struct.pack('!i', status)",
      "struct.pack('!i', status) + b'X'",
    ),
    ('invalid status', "struct.pack('!i', status)", "struct.pack('!i', 256)"),
    ('invalid session', 'start_new_session=True,', 'start_new_session=False,'),
    (
      'worker startup fault',
      'verified_group = True',
      "raise RuntimeError('sensitive-worker-path')",
    ),
    (
      'cleanup fault',
      'os.killpg(worker.pid, signal.SIGTERM)',
      "(_ for _ in ()).throw(OSError('sensitive-cleanup-path'))",
    ),
    (
      'cleanup liveness fallback',
      'activation_attempted = False',
      "activation_attempted = False\n"
          "def fixture_parent_signal(group, signum):\n"
          "    raise OSError('sensitive-cleanup-path')\n"
          'os.killpg = fixture_parent_signal',
    ),
  ]) {
    test('fails closed and redacts ${mutation.$1}', () async {
      final result = await _runSupervisorFixture(
        phase: 'protocol',
        mutation: (mutation.$2, mutation.$3),
        expectCommand: ![
          'missing READY',
          'invalid session',
          'worker startup fault',
        ].contains(mutation.$1),
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, 'protocol failure contained\n');
      expect(result.stderr, isEmpty);
    }, skip: Platform.isWindows);
  }

  test('actual command retains default TERM disposition', () async {
    final result = await runBoundedProcess(
      '/bin/sh',
      ['-c', 'kill -TERM "\$\$"; printf should-not-run'],
      killProcessTree: true,
      maxStdoutBytes: 4096,
      maxStderrBytes: 4096,
      timeout: const Duration(seconds: 3),
    );
    expect(result.exitCode, 143);
    expect(result.stdout, isEmpty);
    expect(result.stderr, isEmpty);
  }, skip: Platform.isWindows);

  test('tree supervision fails closed when Python is unavailable', () async {
    final directory = Directory.systemTemp.createTempSync('aster_no_python_');
    try {
      await expectLater(
        runBoundedProcess(
          '/bin/echo',
          ['sensitive-command-argument'],
          environment: {'PATH': directory.path},
          killProcessTree: true,
          maxStdoutBytes: 4096,
          maxStderrBytes: 4096,
          timeout: const Duration(seconds: 3),
        ),
        throwsA(isA<ProcessLaunchException>()),
      );
    } finally {
      directory.deleteSync(recursive: true);
    }
  }, skip: Platform.isWindows);

  test(
    'tree supervision rejects an unsupported Python before launch',
    () async {
      final result = await _runSupervisorFixture(
        phase: 'unsupported',
        mutation: ('sys.version_info < (3, 9)', 'True'),
        expectCommand: false,
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, 'unsupported runtime rejected\n');
      expect(result.stderr, isEmpty);
    },
    skip: Platform.isWindows,
  );

  test(
    'isolated supervisor ignores Python environment and startup code',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'aster_python_isolation_',
      );
      try {
        File(
          '${directory.path}/sitecustomize.py',
        ).writeAsStringSync("raise RuntimeError('sensitive-startup-path')\n");
        File(
          '${directory.path}/signal.py',
        ).writeAsStringSync("raise RuntimeError('sensitive-shadow-module')\n");
        final result = await runBoundedProcess(
          '/bin/echo',
          ['isolated'],
          environment: {
            'PYTHONHOME': '${directory.path}/nonexistent',
            'PYTHONPATH': directory.path,
            'PYTHONSTARTUP': '${directory.path}/sitecustomize.py',
          },
          workingDirectory: directory.path,
          killProcessTree: true,
          maxStdoutBytes: 4096,
          maxStderrBytes: 4096,
          timeout: const Duration(seconds: 3),
        );
        expect(result.exitCode, 0);
        expect(result.stdout, 'isolated\n');
        expect(result.stderr, isEmpty);
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
    skip: Platform.isWindows,
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
        '/definitely/missing/aster-release-inspector',
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

// Read the actual private program: fixtures interpose scheduling/faults only,
// without adding test hooks to the production process owner.
String _supervisorSource() {
  final source = File('tool/bounded_process.dart').readAsStringSync();
  const prefix = "const _posixProcessTreeSupervisor = r'''";
  final start = source.indexOf(prefix);
  expect(start, greaterThanOrEqualTo(0));
  final end = source.indexOf("''';", start + prefix.length);
  expect(end, greaterThan(start));
  return source.substring(start + prefix.length, end);
}

Future<BoundedProcessResult> _runSupervisorFixture({
  required String phase,
  (String, String)? mutation,
  bool expectCommand = true,
}) async {
  final directory = Directory.systemTemp.createTempSync('aster_python_owner_');
  try {
    var supervisor = _supervisorSource();
    if (mutation case final replacement?) {
      expect(replacement.$1.allMatches(supervisor), hasLength(1));
      supervisor = supervisor.replaceFirst(replacement.$1, replacement.$2);
    }
    const launch = 'worker = subprocess.Popen(';
    expect(launch.allMatches(supervisor), hasLength(1));
    supervisor = supervisor.replaceFirst(launch, 'worker = fixture_spawn(');
    const setup = 'try:\n    status_read, status_write = os.pipe()';
    expect(setup.allMatches(supervisor), hasLength(1));
    supervisor = supervisor.replaceFirst(
      setup,
      '$_supervisorFixtureHooks\n$setup',
    );
    if (phase == 'cleanup' || phase == 'interrupted-cleanup') {
      const grace = '                    time.sleep(0.25)';
      expect(grace.allMatches(supervisor), hasLength(1));
      supervisor = supervisor.replaceFirst(
        grace,
        '                    fixture_barrier()\n$grace',
      );
    }
    final program = File('${directory.path}/supervisor.py')
      ..writeAsStringSync(supervisor);
    final command = File('${directory.path}/command.sh')
      ..writeAsStringSync(r'''
(
  trap '' HUP INT TERM
  : > "$ASTER_PROCESS_FIXTURE_ROOT/grandchild-ready"
  while :; do /bin/sleep 3600; done
) &
while [ ! -f "$ASTER_PROCESS_FIXTURE_ROOT/grandchild-ready" ]; do /bin/sleep 0.01; done
printf output
printf failure >&2
: > "$ASTER_PROCESS_FIXTURE_ROOT/child-output-ready"
if [ "$ASTER_PROCESS_FIXTURE_PHASE" = interrupted-cleanup ] || [ "$ASTER_PROCESS_FIXTURE_PHASE" = parent-death ]; then
  while :; do /bin/sleep 3600; done
fi
''');
    final controller = File('${directory.path}/controller.py')
      ..writeAsStringSync(_supervisorFixtureController);
    return await runBoundedProcess(
      'python3',
      ['-I', '-S', controller.path, program.path, command.path],
      environment: {
        'ASTER_PROCESS_FIXTURE_ROOT': directory.path,
        'ASTER_PROCESS_FIXTURE_PHASE': phase,
        'ASTER_PROCESS_FIXTURE_EXPECT_COMMAND': expectCommand ? '1' : '0',
      },
      killProcessTree: true,
      maxStdoutBytes: 4096,
      maxStderrBytes: 4096,
      timeout: const Duration(seconds: 8),
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
}

const _supervisorFixtureHooks = r'''
def fixture_barrier():
    root = os.environ['ASTER_PROCESS_FIXTURE_ROOT']
    open(root + '/barrier-ready', 'w').close()
    while not os.path.exists(root + '/release'):
        if termination_pending:
            open(root + '/latched', 'w').close()
        time.sleep(0.005)

def fixture_spawn(*args, **kwargs):
    child = subprocess.Popen(*args, **kwargs)
    if os.getpgid(child.pid) == child.pid:
        with open(os.environ['ASTER_PROCESS_FIXTURE_ROOT'] + '/group', 'w') as record:
            record.write(str(child.pid))
    if os.environ['ASTER_PROCESS_FIXTURE_PHASE'] == 'registration':
        fixture_barrier()
    return child
''';

const _supervisorFixtureController = r'''
import os
import signal
import subprocess
import sys
import time

root = os.environ['ASTER_PROCESS_FIXTURE_ROOT']
phase = os.environ['ASTER_PROCESS_FIXTURE_PHASE']
parent = None

def wait_file(name):
    deadline = time.monotonic() + 3
    while not os.path.exists(root + '/' + name):
        if time.monotonic() > deadline:
            raise AssertionError('fixture barrier did not arrive: ' + name)
        time.sleep(0.005)

def group_alive():
    if not os.path.exists(root + '/group'):
        return False
    with open(root + '/group') as record:
        group = int(record.read())
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False

try:
    parent = subprocess.Popen(
        [sys.executable, '-I', '-S', sys.argv[1], '/bin/sh', sys.argv[2]],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, close_fds=True,
    )
    if phase == 'interrupted-cleanup' or phase == 'parent-death':
        wait_file('child-output-ready')
        parent.send_signal(signal.SIGKILL if phase == 'parent-death' else signal.SIGTERM)
    if phase in ('registration', 'cleanup', 'interrupted-cleanup'):
        wait_file('barrier-ready')
        parent.send_signal(signal.SIGTERM)
        wait_file('latched')
        open(root + '/release', 'w').close()
    # communicate proves EOF of BOTH pipes, independently of the exit status.
    output, error = parent.communicate(timeout=3)
    if phase == 'unsupported':
        assert parent.returncode == 69
        assert output == b''
        assert error == b'Bounded process supervision requires Python 3.9 or newer.\n'
        assert not os.path.exists(root + '/child-output-ready')
        print('unsupported runtime rejected')
    elif phase == 'protocol':
        assert parent.returncode == 70, (parent.returncode, output, error)
        assert b'sensitive' not in error and b'Traceback' not in error
        assert b'Bounded process supervisor' in error
        expected = os.environ['ASTER_PROCESS_FIXTURE_EXPECT_COMMAND'] == '1'
        assert os.path.exists(root + '/child-output-ready') == expected
        assert output == (b'output' if expected else b'')
        print('protocol failure contained')
    else:
        assert parent.returncode == (-signal.SIGKILL if phase == 'parent-death' else 143)
        assert output == (b'' if phase == 'registration' else b'output'), output
        assert error == (b'' if phase == 'registration' else b'failure'), error
        assert os.path.exists(root + '/child-output-ready') == (phase != 'registration')
        print('owned group and both streams closed')
    deadline = time.monotonic() + 1
    while group_alive() and time.monotonic() < deadline:
        time.sleep(0.005)
    assert not group_alive(), 'owned group survived cleanup'
finally:
    # Only the exact invocation-owned group recorded by the actual spawn hook
    # is eligible for fixture cleanup; no system-wide discovery or old groups.
    if group_alive():
        with open(root + '/group') as record:
            os.killpg(int(record.read()), signal.SIGKILL)
    open(root + '/release', 'w').close()
    if parent is not None and parent.poll() is None:
        parent.kill()
        parent.communicate(timeout=1)
''';

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
  final directory = Directory.systemTemp.createTempSync('aster_process_');
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
