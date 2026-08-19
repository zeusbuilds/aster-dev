import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_production_tracker.dart';

void main() {
  late Directory repository;

  setUp(() {
    repository = Directory.systemTemp.createTempSync('utexo_tracker_');
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
  });

  test('accepts complete schema and release-closeout state', () {
    _writeTracker(repository, _validTracker());

    final result = verifyProductionTracker(
      repository,
      releaseMode: true,
      repositoryFiles: const {
        'docs/PRODUCTION_REFACTOR_TRACKER.md',
        'lib/a.dart',
      },
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.repositoryFileCount, 2);
    expect(result.inventoryRowCount, 2);
    expect(result.findingCount, 1);
    expect(result.phaseCount, 2);
  });

  test('reports duplicate malformed unknown and mismatched inventory rows', () {
    _writeTracker(
      repository,
      _validTracker().replaceFirst(
        '<!-- FILE_INVENTORY_END -->',
        '| `lib/a.dart` | Dart source | invented | UNKNOWN-999 | - | - |\n'
            '| not-code | too | short |\n'
            '<!-- FILE_INVENTORY_END -->',
      ),
    );

    final result = verifyProductionTracker(
      repository,
      repositoryFiles: const {
        'docs/PRODUCTION_REFACTOR_TRACKER.md',
        'lib/a.dart',
        'lib/missing.dart',
      },
    );

    expect(result.passed, isFalse);
    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('Duplicate inventory row: lib/a.dart'),
        contains('invalid status invented'),
        contains('references unknown ID UNKNOWN-999'),
        contains('must have 6 columns'),
        contains('Missing inventory row: lib/missing.dart'),
      ]),
    );
  });

  test(
    'rejects duplicate IDs, invalid finding schema, and unknown references',
    () {
      final invalid = _validTracker()
          .replaceFirst('| TEST-001 | P1 |', '| TEST-001 | PX |')
          .replaceFirst(
            '## Generated Artifact Validation',
            '| TEST-001 | duplicate |\n\n## Generated Artifact Validation',
          )
          .replaceFirst('| TEST-001 | evidence', '| TEST-999 | evidence');
      _writeTracker(repository, invalid);

      final result = verifyProductionTracker(
        repository,
        repositoryFiles: const {
          'docs/PRODUCTION_REFACTOR_TRACKER.md',
          'lib/a.dart',
        },
      );

      expect(result.passed, isFalse);
      expect(
        result.failures,
        containsAll(<Matcher>[
          contains('Duplicate tracker ID: TEST-001'),
          contains('invalid severity PX'),
          contains('references unknown ID TEST-999'),
        ]),
      );
    },
  );

  test('release mode rejects transient file and finding statuses', () {
    final transient = _validTracker()
        .replaceFirst(
          '| TEST-001 | P1 | Tooling | verified |',
          '| TEST-001 | P1 | Tooling | fixing |',
        )
        .replaceFirst(
          '| `lib/a.dart` | Dart source | verified |',
          '| `lib/a.dart` | Dart source | unreviewed |',
        );
    _writeTracker(repository, transient);

    final normal = verifyProductionTracker(
      repository,
      repositoryFiles: const {
        'docs/PRODUCTION_REFACTOR_TRACKER.md',
        'lib/a.dart',
      },
    );
    final release = verifyProductionTracker(
      repository,
      releaseMode: true,
      repositoryFiles: const {
        'docs/PRODUCTION_REFACTOR_TRACKER.md',
        'lib/a.dart',
      },
    );

    expect(normal.passed, isTrue, reason: normal.failures.join('\n'));
    expect(release.passed, isFalse);
    expect(
      release.failures,
      containsAll(<Matcher>[
        contains('Finding TEST-001 remains fixing'),
        contains('Inventory row lib/a.dart remains unreviewed'),
      ]),
    );
  });

  test('release mode rejects a transient execution phase', () {
    final transient = _validTracker().replaceFirst(
      '| 1 | Closeout | verified | Complete. |',
      '| 1 | Closeout | unreviewed | Pending. |',
    );
    _writeTracker(repository, transient);

    final normal = verifyProductionTracker(
      repository,
      repositoryFiles: const {
        'docs/PRODUCTION_REFACTOR_TRACKER.md',
        'lib/a.dart',
      },
    );
    final release = verifyProductionTracker(
      repository,
      releaseMode: true,
      repositoryFiles: const {
        'docs/PRODUCTION_REFACTOR_TRACKER.md',
        'lib/a.dart',
      },
    );

    expect(normal.passed, isTrue, reason: normal.failures.join('\n'));
    expect(
      release.failures,
      contains('Phase 1 remains unreviewed in release mode.'),
    );
  });

  test('rejects malformed duplicate and non-contiguous phase rows', () {
    final invalid = _validTracker()
        .replaceFirst('| 0 | Foundation | verified | Complete. |\n', '')
        .replaceFirst(
          '| 1 | Closeout | verified | Complete. |',
          '| 1 | Closeout | invented | Complete. |\n'
              '| 1 | Duplicate | verified | Complete. |',
        );
    _writeTracker(repository, invalid);

    final result = verifyProductionTracker(
      repository,
      repositoryFiles: const {
        'docs/PRODUCTION_REFACTOR_TRACKER.md',
        'lib/a.dart',
      },
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('Phase 1 has invalid status invented'),
        contains('Duplicate phase row: 1'),
        contains('Phase Plan is missing phase 0'),
      ]),
    );
  });

  test('deduplicates repeated validation failures deterministically', () {
    _writeTracker(
      repository,
      _validTracker().replaceFirst(
        '| TEST-001 | evidence',
        '| TEST-999 | evidence',
      ),
    );

    final result = verifyProductionTracker(
      repository,
      repositoryFiles: const {
        'docs/PRODUCTION_REFACTOR_TRACKER.md',
        'lib/a.dart',
      },
    );

    expect(
      result.failures.where(
        (failure) =>
            failure ==
            'Inventory row lib/a.dart references unknown ID TEST-999.',
      ),
      hasLength(1),
    );
    expect(result.failures, orderedEquals(result.failures.toList()..sort()));
  });

  test('fails closed for missing or duplicated inventory markers', () {
    _writeTracker(
      repository,
      '${_validTracker()}\n<!-- FILE_INVENTORY_START -->',
    );

    final result = verifyProductionTracker(
      repository,
      repositoryFiles: const {},
    );

    expect(result.passed, isFalse);
    expect(result.failures.single, contains('markers are missing, duplicated'));
  });

  test('parses exact NUL-framed Git inventory without line ambiguity', () {
    _writeFile(repository, 'lib/a.dart');
    _writeFile(repository, 'lib/generated.g.dart');
    _writeFile(repository, 'docs/read me.md');

    final files = parseRepositoryFileInventory(
      repository,
      'lib/a.dart\u0000lib/generated.g.dart\u0000'
      'docs/read me.md\u0000missing.dart\u0000',
    );

    expect(files, {'lib/a.dart', 'docs/read me.md'});
  });

  test('rejects truncated, duplicate, empty, or unsafe Git records', () {
    for (final output in <String>[
      'lib/a.dart',
      'lib/a.dart\u0000lib/a.dart\u0000',
      'lib/a.dart\u0000\u0000',
      'lib/a\n.dart\u0000',
      '../outside.dart\u0000',
      'lib/a\\b.dart\u0000',
      'lib/`a`.dart\u0000',
    ]) {
      expect(
        () => parseRepositoryFileInventory(repository, output),
        throwsFormatException,
        reason: output.codeUnits.toString(),
      );
    }
  });
}

String _validTracker() => '''
# Tracker

Statuses are documented.

## Phase Plan

| Phase | Scope | Status | Exit evidence |
| --- | --- | --- | --- |
| 0 | Foundation | verified | Complete. |
| 1 | Closeout | verified | Complete. |

## Findings

| ID | Severity | Area | Status | Finding | Evidence | Fix commit | Verification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TEST-001 | P1 | Tooling | verified | A finding. | Evidence. | abc1234 | Verified. |

## Generated Artifact Validation

## File Review Inventory

<!-- FILE_INVENTORY_START -->
| File | Kind | Status | Finding IDs | Verification | Fix commit |
| --- | --- | --- | --- | --- | --- |
| `docs/PRODUCTION_REFACTOR_TRACKER.md` | Documentation | verified | - | self | abc1234 |
| `lib/a.dart` | Dart source | verified | TEST-001 | evidence | abc1234 |
<!-- FILE_INVENTORY_END -->
''';

void _writeTracker(Directory root, String contents) {
  final file = File('${root.path}/docs/PRODUCTION_REFACTOR_TRACKER.md');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void _writeFile(Directory root, String path) {
  final file = File('${root.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('fixture');
}
