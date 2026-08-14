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
}

String _validTracker() => '''
# Tracker

Statuses are documented.

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
