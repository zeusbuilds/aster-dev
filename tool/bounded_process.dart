import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _terminationGrace = Duration(seconds: 2);

/// Captured output from a subprocess executed within explicit resource bounds.
final class BoundedProcessResult {
  const BoundedProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Native process exit status.
  final int exitCode;

  /// Strictly decoded standard output within the caller's byte ceiling.
  final String stdout;

  /// Strictly decoded standard error within the caller's byte ceiling.
  final String stderr;
}

/// Raised when one subprocess output stream exceeds its configured byte limit.
final class ProcessOutputLimitException implements Exception {
  const ProcessOutputLimitException(this.streamName, this.maximumBytes);

  /// Name of the stream that crossed its limit.
  final String streamName;

  /// Maximum number of bytes accepted from that stream.
  final int maximumBytes;

  @override
  String toString() =>
      'ProcessOutputLimitException: $streamName exceeded $maximumBytes bytes.';
}

/// Raised when a subprocess does not complete within its operation deadline.
final class ProcessDeadlineException implements Exception {
  const ProcessDeadlineException(this.timeout);

  /// Maximum execution time allowed by the caller.
  final Duration timeout;

  @override
  String toString() => 'ProcessDeadlineException: process exceeded $timeout.';
}

/// Raised when the operating system cannot start a bounded subprocess.
///
/// The executable, arguments, and working directory are intentionally omitted
/// because release tools can pass sensitive artifact paths to this boundary.
final class ProcessLaunchException implements Exception {
  const ProcessLaunchException();

  @override
  String toString() => 'ProcessLaunchException: unable to start subprocess.';
}

/// Executes a subprocess with strict output, encoding, and time bounds.
///
/// The child is force-terminated if either output stream exceeds its own byte
/// ceiling, strict UTF-8 decoding fails, or [timeout] expires. Arguments and
/// captured output are deliberately absent from thrown exception text so this
/// boundary can also be used by tools that inspect sensitive paths.
Future<BoundedProcessResult> runBoundedProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  required int maxStdoutBytes,
  required int maxStderrBytes,
  required Duration timeout,
}) async {
  if (executable.isEmpty) {
    throw ArgumentError.value(executable, 'executable', 'must not be empty');
  }
  if (maxStdoutBytes <= 0 || maxStderrBytes <= 0) {
    throw ArgumentError('Process output limits must be positive.');
  }
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must be positive');
  }

  final Process process;
  try {
    process = await Process.start(
      executable,
      List.unmodifiable(arguments),
      workingDirectory: workingDirectory,
    );
  } on ProcessException {
    throw const ProcessLaunchException();
  }
  var terminated = false;
  void terminate() {
    if (terminated) return;
    terminated = true;
    var killed = false;
    if (!Platform.isWindows) {
      try {
        killed = process.kill(ProcessSignal.sigkill);
      } on Object {
        // A best-effort fallback below preserves the authoritative failure.
      }
    }
    if (!killed) {
      try {
        process.kill();
      } on Object {
        // Termination errors must never replace a limit or deadline failure.
      }
    }
  }

  final stdoutFuture = _readBoundedUtf8(
    process.stdout,
    streamName: 'stdout',
    maximumBytes: maxStdoutBytes,
    onLimit: terminate,
  );
  final stderrFuture = _readBoundedUtf8(
    process.stderr,
    streamName: 'stderr',
    maximumBytes: maxStderrBytes,
    onLimit: terminate,
  );

  try {
    final values =
        await Future.wait<Object>([
          process.exitCode,
          stdoutFuture,
          stderrFuture,
        ], eagerError: true).timeout(
          timeout,
          onTimeout: () {
            terminate();
            throw ProcessDeadlineException(timeout);
          },
        );
    return BoundedProcessResult(
      exitCode: values[0] as int,
      stdout: values[1] as String,
      stderr: values[2] as String,
    );
  } on Object {
    terminate();
    try {
      await process.exitCode.timeout(_terminationGrace);
    } on Object {
      // The original bounded-process failure remains authoritative.
    }
    rethrow;
  }
}

Future<String> _readBoundedUtf8(
  Stream<List<int>> input, {
  required String streamName,
  required int maximumBytes,
  required void Function() onLimit,
}) async {
  final output = BytesBuilder(copy: false);
  var totalBytes = 0;
  await for (final chunk in input) {
    totalBytes += chunk.length;
    if (totalBytes > maximumBytes) {
      onLimit();
      throw ProcessOutputLimitException(streamName, maximumBytes);
    }
    output.add(chunk);
  }
  return utf8.decode(output.takeBytes());
}
