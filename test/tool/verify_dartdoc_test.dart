import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_dartdoc.dart';

void main() {
  test('accepts a clean result and extracts its public library count', () {
    final result = evaluateDartdocResult(
      exitCode: 0,
      stdout: 'Documented 307 public libraries in 42.0 seconds',
      stderr: '',
    );

    expect(result.passed, isTrue);
    expect(result.libraryCount, 307);
  });

  test('rejects reported warnings even when Dartdoc exits successfully', () {
    final result = evaluateDartdocResult(
      exitCode: 0,
      stdout: 'Documented 307 public libraries',
      stderr: 'dartdoc completed with 1 warning',
    );

    expect(result.passed, isFalse);
    expect(result.libraryCount, 307);
  });

  test('rejects nonzero status without inventing a library count', () {
    final result = evaluateDartdocResult(
      exitCode: 65,
      stdout: '',
      stderr: 'documentation generation failed',
    );

    expect(result.passed, isFalse);
    expect(result.libraryCount, isNull);
  });
}
