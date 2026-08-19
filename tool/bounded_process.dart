import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _terminationGrace = Duration(seconds: 2);
const _posixProcessTreeSupervisor = r'''
exec 3>&1 4>&2
set -m
child_pid=

stop_owned_groups() {
  owned_pids="${child_pid:-} $(jobs -pr 2>/dev/null)"
  had_owned_process=0
  for owned_pid in $owned_pids; do
    if kill -0 -- "-$owned_pid" 2>/dev/null ||
      kill -0 "$owned_pid" 2>/dev/null; then
      had_owned_process=1
      kill -TERM -- "-$owned_pid" 2>/dev/null ||
        kill -TERM "$owned_pid" 2>/dev/null || true
    fi
  done
  if [ "$had_owned_process" -eq 1 ]; then
    sleep 0.25
    for owned_pid in $owned_pids; do
      kill -KILL -- "-$owned_pid" 2>/dev/null ||
        kill -KILL "$owned_pid" 2>/dev/null || true
    done
  fi
  wait 2>/dev/null || true
}

interrupt_owned_group() {
  trap - HUP INT TERM
  stop_owned_groups
  exit 143
}

trap interrupt_owned_group HUP INT TERM
(
  set +m
  "$@" >&3 2>&4
  owned_status=$?
  while :; do /bin/sleep 3600; done &
  exit "$owned_status"
) &
child_pid=$!
wait "$child_pid" 2>/dev/null
status=$?
trap - HUP INT TERM
stop_owned_groups
exit "$status"
''';

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
///
/// Set [killProcessTree] for commands that can spawn descendants. On macOS and
/// Linux, the command is then launched in a dedicated process group supervised
/// by `/bin/bash`; bounded failures and normal completion terminate every
/// remaining member of that group. Callers must configure child tools not to
/// detach into independent sessions. This mode fails closed on unsupported
/// hosts rather than claiming descendant cleanup there.
Future<BoundedProcessResult> runBoundedProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool killProcessTree = false,
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
  if (killProcessTree && (!Platform.isMacOS && !Platform.isLinux)) {
    throw UnsupportedError(
      'Bounded process-tree ownership requires macOS or Linux.',
    );
  }

  final Process process;
  try {
    process = await Process.start(
      killProcessTree ? '/bin/bash' : executable,
      killProcessTree
          ? <String>[
              '--noprofile',
              '--norc',
              '-p',
              '-c',
              _posixProcessTreeSupervisor,
              'utexo-bounded-process',
              executable,
              ...arguments,
            ]
          : List.unmodifiable(arguments),
      workingDirectory: workingDirectory,
    );
  } on ProcessException {
    throw const ProcessLaunchException();
  }
  var terminationRequested = false;
  void requestTermination() {
    if (terminationRequested) return;
    terminationRequested = true;
    try {
      if (Platform.isWindows) {
        process.kill();
      } else {
        process.kill(ProcessSignal.sigterm);
      }
    } on Object {
      // Termination errors must never replace a limit or deadline failure.
    }
  }

  Future<void> ensureTerminated() async {
    requestTermination();
    try {
      await process.exitCode.timeout(_terminationGrace);
      return;
    } on Object {
      // Force termination below if the graceful request did not complete.
    }
    try {
      if (Platform.isWindows) {
        process.kill();
      } else {
        process.kill(ProcessSignal.sigkill);
      }
    } on Object {
      // The original bounded-process failure remains authoritative.
    }
    try {
      await process.exitCode.timeout(_terminationGrace);
    } on Object {
      // The original bounded-process failure remains authoritative.
    }
  }

  final stdoutFuture = _readBoundedUtf8(
    process.stdout,
    streamName: 'stdout',
    maximumBytes: maxStdoutBytes,
    onLimit: requestTermination,
  );
  final stderrFuture = _readBoundedUtf8(
    process.stderr,
    streamName: 'stderr',
    maximumBytes: maxStderrBytes,
    onLimit: requestTermination,
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
            requestTermination();
            throw ProcessDeadlineException(timeout);
          },
        );
    return BoundedProcessResult(
      exitCode: values[0] as int,
      stdout: values[1] as String,
      stderr: values[2] as String,
    );
  } on Object {
    await ensureTerminated();
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
