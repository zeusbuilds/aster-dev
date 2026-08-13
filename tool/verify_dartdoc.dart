import 'dart:io';

/// Generates Dart API documentation into an isolated directory.
Future<void> main() async {
  final output = Directory.systemTemp.createTempSync('utexo-dartdoc-');
  try {
    final result = await Process.run(Platform.resolvedExecutable, [
      'doc',
      '--validate-links',
      '--output',
      output.path,
      '.',
    ]);
    final stdoutText = result.stdout as String;
    final stderrText = result.stderr as String;
    final diagnostics = '$stdoutText\n$stderrText';
    final hasReportedDiagnostics = RegExp(
      r'\b[1-9][0-9]* (?:warnings?|errors?)\b',
      caseSensitive: false,
    ).hasMatch(diagnostics);
    if (result.exitCode != 0 || hasReportedDiagnostics) {
      stdout.write(stdoutText);
      stderr.write(stderrText);
      stderr.writeln('Dartdoc validation failed.');
      exitCode = result.exitCode == 0 ? 1 : result.exitCode;
      return;
    }

    final libraryCount = RegExp(r'Documented ([0-9]+) public libraries')
        .firstMatch(diagnostics)
        ?.group(1);
    stdout.writeln(
      'Dartdoc completed without warnings or errors'
      '${libraryCount == null ? '' : ' for $libraryCount public libraries'}.',
    );
  } finally {
    if (output.existsSync()) output.deleteSync(recursive: true);
  }
}
