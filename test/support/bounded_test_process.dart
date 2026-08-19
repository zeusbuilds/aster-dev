import 'dart:io';

import '../../tool/bounded_process.dart';

export '../../tool/bounded_process.dart' show BoundedProcessResult;

const _defaultTimeout = Duration(seconds: 30);
const _defaultOutputBytes = 32 * 1024 * 1024;

/// Runs a real test fixture process with deterministic descendant ownership.
Future<BoundedProcessResult> runTestProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  Duration timeout = _defaultTimeout,
  int maxStdoutBytes = _defaultOutputBytes,
  int maxStderrBytes = _defaultOutputBytes,
}) {
  return runBoundedProcess(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    killProcessTree: Platform.isMacOS || Platform.isLinux,
    maxStdoutBytes: maxStdoutBytes,
    maxStderrBytes: maxStderrBytes,
    timeout: timeout,
  );
}

/// Makes a POSIX fixture executable through the same bounded process owner.
Future<void> makeTestExecutable(File file) async {
  if (Platform.isWindows) return;
  final result = await runTestProcess(
    '/bin/chmod',
    <String>['755', file.path],
    timeout: const Duration(seconds: 10),
    maxStdoutBytes: 4096,
    maxStderrBytes: 4096,
  );
  if (result.exitCode != 0) {
    throw StateError('Could not make the test fixture executable.');
  }
}

/// Returns a repository-compatible Dart VM without invoking a version manager.
String testDartExecutable() {
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  final repositoryDart = <String>[
    Directory.current.path,
    '.fvm',
    'flutter_sdk',
    'bin',
    'cache',
    'dart-sdk',
    'bin',
    executableName,
  ].join(Platform.pathSeparator);
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?)
      '$root/bin/cache/dart-sdk/bin/$executableName',
    repositoryDart,
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

/// Installs the test VM at the fixed path expected by bounded shell scripts.
void linkTestDartRuntime(Directory repository) {
  if (Platform.isWindows) {
    throw UnsupportedError('Bounded shell fixtures require a POSIX host.');
  }
  final link = Link(
    '${repository.path}/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart',
  );
  link.parent.createSync(recursive: true);
  link.createSync(testDartExecutable());
}
