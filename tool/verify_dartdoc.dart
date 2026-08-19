import 'dart:io';

import 'bounded_process.dart';

const _dartdocTimeout = Duration(minutes: 10);
const _maximumDartdocOutputBytes = 16 * 1024 * 1024;

/// Parsed outcome of one bounded Dart API documentation run.
final class DartdocVerification {
  const DartdocVerification({required this.passed, required this.libraryCount});

  /// Whether the command exited successfully without reported diagnostics.
  final bool passed;

  /// Number of public libraries reported by Dartdoc, when present.
  final int? libraryCount;
}

/// Interprets Dartdoc's status and bounded diagnostic streams.
DartdocVerification evaluateDartdocResult({
  required int exitCode,
  required String stdout,
  required String stderr,
}) {
  final diagnostics = '$stdout\n$stderr';
  final hasReportedDiagnostics = RegExp(
    r'\b[1-9][0-9]* (?:warnings?|errors?)\b',
    caseSensitive: false,
  ).hasMatch(diagnostics);
  final libraryCount = int.tryParse(
    RegExp(r'Documented ([0-9]+) public libraries')
            .firstMatch(diagnostics)
            ?.group(1) ??
        '',
  );
  return DartdocVerification(
    passed: exitCode == 0 && !hasReportedDiagnostics,
    libraryCount: libraryCount,
  );
}

/// Generates Dart API documentation into an isolated directory.
Future<void> main() async {
  final output = Directory.systemTemp.createTempSync('aster-dartdoc-');
  try {
    final result = await runBoundedProcess(
      Platform.resolvedExecutable,
      ['doc', '--validate-links', '--output', output.path, '.'],
      killProcessTree: true,
      maxStdoutBytes: _maximumDartdocOutputBytes,
      maxStderrBytes: _maximumDartdocOutputBytes,
      timeout: _dartdocTimeout,
    );
    final verification = evaluateDartdocResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
    if (!verification.passed) {
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      stderr.writeln('Dartdoc validation failed.');
      exitCode = result.exitCode == 0 ? 1 : result.exitCode;
      return;
    }

    stdout.writeln(
      'Dartdoc completed without warnings or errors'
      '${verification.libraryCount == null ? '' : ' for ${verification.libraryCount} public libraries'}.',
    );
  } on Object catch (error) {
    stderr.writeln('Dartdoc validation did not complete: $error');
    exitCode = 1;
  } finally {
    if (output.existsSync()) output.deleteSync(recursive: true);
  }
}
