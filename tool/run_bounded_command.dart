import 'dart:io';

import 'bounded_process.dart';

const _usageExitCode = 64;
const _dataExitCode = 65;
const _unavailableExitCode = 69;
const _softwareExitCode = 70;
const _deadlineExitCode = 124;
const _outputLimitExitCode = 125;
const _launchExitCode = 126;
const _maximumTimeoutSeconds = 2 * 60 * 60;
const _maximumOutputBytes = 128 * 1024 * 1024;

/// Runs one command under the repository's process-tree, output, and deadline
/// policy.
///
/// This entry point accepts only decimal resource bounds and never repeats the
/// executable, arguments, working directory, or child output in watchdog error
/// messages. Long-running callers may opt into live output; chunks are
/// forwarded only after strict UTF-8 decoding and byte accounting.
Future<void> main(List<String> arguments) async {
  final invocation = _parseInvocation(arguments);
  if (invocation == null) {
    _writeFailure('Invalid bounded-command invocation.');
    exitCode = _usageExitCode;
    return;
  }

  try {
    final result = await runBoundedProcess(
      invocation.executable,
      invocation.arguments,
      workingDirectory: invocation.workingDirectory,
      killProcessTree: true,
      onStdout: invocation.streamOutput ? stdout.write : null,
      onStderr: invocation.streamOutput ? stderr.write : null,
      maxStdoutBytes: invocation.maxStdoutBytes,
      maxStderrBytes: invocation.maxStderrBytes,
      timeout: Duration(seconds: invocation.timeoutSeconds),
    );
    if (!invocation.streamOutput) {
      stdout.write(result.stdout);
      stderr.write(result.stderr);
    }
    await stdout.flush();
    await stderr.flush();
    exitCode = _portableExitCode(result.exitCode);
  } on ProcessDeadlineException {
    _writeFailure(
      'Bounded command exceeded its ${invocation.timeoutSeconds}-second '
      'deadline.',
    );
    exitCode = _deadlineExitCode;
  } on ProcessOutputLimitException catch (error) {
    _writeFailure(
      'Bounded command exceeded the ${error.streamName} byte ceiling.',
    );
    exitCode = _outputLimitExitCode;
  } on ProcessLaunchException {
    _writeFailure('Bounded command could not be started.');
    exitCode = _launchExitCode;
  } on FormatException {
    _writeFailure('Bounded command emitted malformed UTF-8.');
    exitCode = _dataExitCode;
  } on UnsupportedError {
    _writeFailure('Bounded process-tree ownership is unavailable.');
    exitCode = _unavailableExitCode;
  } on Object {
    _writeFailure('Bounded command failed inside the execution boundary.');
    exitCode = _softwareExitCode;
  }
}

void _writeFailure(String message) {
  stderr.writeln(message);
}

int _portableExitCode(int childExitCode) {
  if (childExitCode >= 0 && childExitCode <= 255) return childExitCode;
  return _softwareExitCode;
}

_BoundedInvocation? _parseInvocation(List<String> arguments) {
  int? timeoutSeconds;
  int? maxStdoutBytes;
  int? maxStderrBytes;
  String? workingDirectory;
  var streamOutput = false;
  var index = 0;

  String? readValue() {
    if (index + 1 >= arguments.length) return null;
    index += 1;
    final value = arguments[index];
    if (value.isEmpty || value == '--') return null;
    return value;
  }

  while (index < arguments.length && arguments[index] != '--') {
    final option = arguments[index];
    switch (option) {
      case '--timeout-seconds':
        final value = readValue();
        if (value == null || timeoutSeconds != null) return null;
        timeoutSeconds = _parseBoundedDecimal(
          value,
          maximum: _maximumTimeoutSeconds,
        );
        break;
      case '--max-stdout-bytes':
        final value = readValue();
        if (value == null || maxStdoutBytes != null) return null;
        maxStdoutBytes = _parseBoundedDecimal(
          value,
          maximum: _maximumOutputBytes,
        );
        break;
      case '--max-stderr-bytes':
        final value = readValue();
        if (value == null || maxStderrBytes != null) return null;
        maxStderrBytes = _parseBoundedDecimal(
          value,
          maximum: _maximumOutputBytes,
        );
        break;
      case '--working-directory':
        final value = readValue();
        if (value == null || workingDirectory != null) return null;
        workingDirectory = value;
        break;
      case '--stream-output':
        if (streamOutput) return null;
        streamOutput = true;
        break;
      default:
        return null;
    }
    index += 1;
  }

  if (timeoutSeconds == null ||
      maxStdoutBytes == null ||
      maxStderrBytes == null ||
      index >= arguments.length ||
      arguments[index] != '--') {
    return null;
  }
  index += 1;
  if (index >= arguments.length || arguments[index].isEmpty) return null;

  return _BoundedInvocation(
    timeoutSeconds: timeoutSeconds,
    maxStdoutBytes: maxStdoutBytes,
    maxStderrBytes: maxStderrBytes,
    workingDirectory: workingDirectory,
    streamOutput: streamOutput,
    executable: arguments[index],
    arguments: List<String>.unmodifiable(arguments.skip(index + 1)),
  );
}

int? _parseBoundedDecimal(String value, {required int maximum}) {
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) return null;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed > maximum) return null;
  return parsed;
}

final class _BoundedInvocation {
  const _BoundedInvocation({
    required this.timeoutSeconds,
    required this.maxStdoutBytes,
    required this.maxStderrBytes,
    required this.workingDirectory,
    required this.streamOutput,
    required this.executable,
    required this.arguments,
  });

  final int timeoutSeconds;
  final int maxStdoutBytes;
  final int maxStderrBytes;
  final String? workingDirectory;
  final bool streamOutput;
  final String executable;
  final List<String> arguments;
}
