import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _terminationGrace = Duration(seconds: 2);
const _posixProcessTreeSupervisor = r'''
import errno
import os
import select
import signal
import struct
import subprocess
import sys
import time

if sys.version_info < (3, 9):
    sys.stderr.write("Bounded process supervision requires Python 3.9 or newer.\n")
    raise SystemExit(69)

WORKER = r"""
import errno
import os
import select
import signal
import struct
import subprocess
import sys

def retain_anchor(signum, frame):
    pass
for name in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(name, retain_anchor)
verified_group = False

def stop_after_parent_loss(timeout):
    readable, _, _ = select.select([gate_fd], [], [], timeout)
    if readable:
        # EOF or any extra activation byte means this parent is gone/invalid.
        # The command never inherits this descriptor and cannot keep it alive.
        os.read(gate_fd, 1)
        os.killpg(os.getpid(), signal.SIGKILL)

try:
    status_fd, gate_fd = int(sys.argv[1]), int(sys.argv[2])
    os.set_inheritable(status_fd, False)
    os.set_inheritable(gate_fd, False)
    if os.getpid() != os.getpgrp() or os.getpid() != os.getsid(0):
        raise SystemExit(70)
    verified_group = True
    if os.write(status_fd, b'R') != 1:
        raise OSError()
    if os.read(gate_fd, 1) != b'G':
        os.killpg(os.getpid(), signal.SIGKILL)
    try:
        # Caught anchor handlers reset at exec. Never use SIG_IGN here.
        command = subprocess.Popen(sys.argv[3:], close_fds=True)
        while True:
            stop_after_parent_loss(0.05)
            status = command.poll()
            if status is not None:
                break
        if status < 0:
            status = 128 - status
    except OSError as error:
        status = 127 if error.errno == errno.ENOENT else 126
    if not 0 <= status <= 255:
        status = 70
    record = struct.pack('!i', status)
    if os.write(status_fd, record) != len(record):
        raise OSError()
    os.close(status_fd)
    # Hold PGID identity until KILL; parent death instead self-kills this group.
    while True:
        stop_after_parent_loss(None)
except BaseException:
    # Internal errors never replay an exception containing paths or arguments.
    if verified_group:
        try:
            os.killpg(os.getpid(), signal.SIGKILL)
        except OSError:
            pass
    raise SystemExit(70)
"""

termination_pending = False
def request_termination(signum, frame):
    global termination_pending
    termination_pending = True
for name in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(name, request_termination)

class Cancelled(Exception):
    pass
class ProtocolFailure(Exception):
    pass

status_read = status_write = gate_read = gate_write = -1
worker = None
owned_group = False
activation_attempted = False
received_bytes = 0
result = 70

def read_bytes(count, eof=False):
    global received_bytes
    data = b''
    while len(data) < count:
        if termination_pending:
            raise Cancelled()
        # Finite polling checks cancellation even when PEP 475 restarts select.
        ready, _, _ = select.select([status_read], [], [], 0.05)
        if not ready:
            continue
        chunk = os.read(status_read, count - len(data))
        received_bytes += len(chunk)
        if received_bytes > 5:
            raise ProtocolFailure()
        if not chunk:
            if eof and not data:
                return b''
            raise ProtocolFailure()
        data += chunk
    if eof:
        raise ProtocolFailure()
    return data

try:
    status_read, status_write = os.pipe()
    gate_read, gate_write = os.pipe()
    worker = subprocess.Popen(
        [sys.executable, '-I', '-S', '-c', WORKER,
         str(status_write), str(gate_read)] + sys.argv[1:],
        start_new_session=True,
        close_fds=True,
        pass_fds=(status_write, gate_read),
    )
    os.close(status_write)
    status_write = -1
    os.close(gate_read)
    gate_read = -1
    # No command can start until both independent group checks and READY pass.
    if os.getpgid(worker.pid) != worker.pid or os.getsid(worker.pid) != worker.pid:
        raise ProtocolFailure()
    owned_group = True
    if read_bytes(1) != b'R':
        raise ProtocolFailure()
    if termination_pending:
        raise Cancelled()
    # This write is the command-dispatch boundary. Mark it before attempting
    # activation so every ambiguous/partial write takes full group cleanup.
    activation_attempted = True
    if os.write(gate_write, b'G') != 1:
        raise ProtocolFailure()
    result = struct.unpack('!i', read_bytes(4))[0]
    if not 0 <= result <= 255:
        raise ProtocolFailure()
    read_bytes(1, eof=True)
except Cancelled:
    result = 143
except BaseException:
    sys.stderr.write("Bounded process supervisor failed before verified completion.\n")
    result = 70
finally:
    cleanup_failed = False
    try:
        if worker is not None:
            # Do not poll/reap the anchor before this sequence: its identity
            # remains reserved even after the actual command has exited.
            if owned_group and activation_attempted:
                try:
                    os.killpg(worker.pid, signal.SIGTERM)
                    time.sleep(0.25)
                except ProcessLookupError:
                    pass
                except BaseException:
                    cleanup_failed = True
                finally:
                    try:
                        os.killpg(worker.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    except BaseException:
                        cleanup_failed = True
            else:
                # No GO was attempted, so no command/descendant can exist.
                # Kill only this known PID; bootstrap handlers may not be ready.
                try:
                    worker.kill()
                except ProcessLookupError:
                    pass
    except BaseException:
        cleanup_failed = True
    finally:
        # Closing the liveness writer also orders self-cleanup if group
        # signalling unexpectedly failed. Private FDs close on every path.
        for descriptor in (status_read, status_write, gate_read, gate_write):
            if descriptor >= 0:
                try:
                    os.close(descriptor)
                except OSError:
                    cleanup_failed = True
    if worker is not None:
        try:
            worker.wait()
        except BaseException:
            cleanup_failed = True
    if cleanup_failed:
        sys.stderr.write("Bounded process supervisor cleanup failed.\n")
        result = 70
if termination_pending:
    result = 143
raise SystemExit(result)
''';

/// Receives one strictly decoded text chunk from a bounded process stream.
///
/// The callback runs synchronously while the stream is consumed. Throwing from
/// it aborts the operation and triggers the same deterministic child cleanup as
/// a deadline or output-limit failure.
typedef ProcessOutputCallback = void Function(String chunk);

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
/// by isolated Python 3.9+; bounded failures and normal completion terminate every
/// remaining member of that group. Callers must configure child tools not to
/// detach into independent sessions. This mode fails closed on unsupported
/// hosts rather than claiming descendant cleanup there.
Future<BoundedProcessResult> runBoundedProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool killProcessTree = false,
  ProcessOutputCallback? onStdout,
  ProcessOutputCallback? onStderr,
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
      killProcessTree ? 'python3' : executable,
      killProcessTree
          ? <String>[
              '-I',
              '-S',
              '-c',
              _posixProcessTreeSupervisor,
              executable,
              ...arguments,
            ]
          : List.unmodifiable(arguments),
      workingDirectory: workingDirectory,
      environment: environment,
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
    onDecodedChunk: onStdout,
  );
  final stderrFuture = _readBoundedUtf8(
    process.stderr,
    streamName: 'stderr',
    maximumBytes: maxStderrBytes,
    onLimit: requestTermination,
    onDecodedChunk: onStderr,
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
  ProcessOutputCallback? onDecodedChunk,
}) async {
  final output = StringBuffer();
  final decoder = utf8.decoder.startChunkedConversion(
    _DecodedOutputSink(output, onDecodedChunk),
  );
  var totalBytes = 0;
  await for (final chunk in input) {
    totalBytes += chunk.length;
    if (totalBytes > maximumBytes) {
      onLimit();
      throw ProcessOutputLimitException(streamName, maximumBytes);
    }
    decoder.add(chunk);
  }
  decoder.close();
  return output.toString();
}

final class _DecodedOutputSink implements Sink<String> {
  _DecodedOutputSink(this._output, this._onDecodedChunk);

  final StringBuffer _output;
  final ProcessOutputCallback? _onDecodedChunk;

  @override
  void add(String data) {
    _output.write(data);
    _onDecodedChunk?.call(data);
  }

  @override
  void close() {}
}
