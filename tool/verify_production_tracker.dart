import 'dart:convert';
import 'dart:io';

const _trackerPath = 'docs/PRODUCTION_REFACTOR_TRACKER.md';
const _startMarker = '<!-- FILE_INVENTORY_START -->';
const _endMarker = '<!-- FILE_INVENTORY_END -->';
const _validStatuses = <String>{
  'unreviewed',
  'reviewed-clean',
  'fixing',
  'verified',
  'blocked',
  'accepted-constraint',
};
const _transientStatuses = <String>{'unreviewed', 'fixing'};

/// Result of validating the production tracker against one repository tree.
final class ProductionTrackerVerification {
  const ProductionTrackerVerification({
    required this.repositoryFileCount,
    required this.inventoryRowCount,
    required this.findingCount,
    required this.phaseCount,
    required this.failures,
  });

  /// Number of owned non-generated files found in Git's working tree view.
  final int repositoryFileCount;

  /// Number of structurally valid inventory rows found in the tracker.
  final int inventoryRowCount;

  /// Number of structurally valid finding rows found in the tracker.
  final int findingCount;

  /// Number of structurally valid execution-phase rows found in the tracker.
  final int phaseCount;

  /// Deterministically sorted schema, inventory, or readiness failures.
  final List<String> failures;

  /// Whether the tracker satisfies every requested check.
  bool get passed => failures.isEmpty;
}

void main(List<String> arguments) {
  final unknownArguments = arguments
      .where((argument) => argument != '--sync' && argument != '--release')
      .toList();
  if (unknownArguments.isNotEmpty) {
    stderr.writeln('Unknown arguments: ${unknownArguments.join(', ')}');
    exitCode = 64;
    return;
  }

  final root = Directory.current;
  if (arguments.contains('--sync')) {
    final failure = _synchronizeTracker(root);
    if (failure != null) {
      stderr.writeln(failure);
      exitCode = 1;
    }
    return;
  }

  final releaseMode = arguments.contains('--release');
  final result = verifyProductionTracker(root, releaseMode: releaseMode);
  if (!result.passed) {
    for (final failure in result.failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Tracker schema and inventory match ${result.repositoryFileCount} '
    'non-generated files and ${result.findingCount} findings'
    '${releaseMode ? ' in release mode' : ''}.',
  );
}

/// Validates tracker schema, references, inventory coverage, and optional
/// release-closeout state beneath [repositoryRoot].
///
/// [repositoryFiles] exists for deterministic fault fixtures. Production
/// callers should omit it so Git remains the source of owned-file truth.
ProductionTrackerVerification verifyProductionTracker(
  Directory repositoryRoot, {
  bool releaseMode = false,
  Set<String>? repositoryFiles,
}) {
  final root = repositoryRoot.absolute;
  final failures = <String>[];
  final files = repositoryFiles ?? _repositoryFiles(root, failures: failures);
  final tracker = File('${root.path}/$_trackerPath');
  if (!tracker.existsSync()) {
    failures.add('Missing $_trackerPath.');
    return ProductionTrackerVerification(
      repositoryFileCount: files.length,
      inventoryRowCount: 0,
      findingCount: 0,
      phaseCount: 0,
      failures: List<String>.unmodifiable(failures..sort()),
    );
  }

  final document = _parseTracker(tracker.readAsStringSync(), failures);
  final trackedPaths = document.inventory.keys.toSet();
  final missing = files.difference(trackedPaths).toList()..sort();
  final stale = trackedPaths.difference(files).toList()..sort();
  for (final path in missing) {
    failures.add('Missing inventory row: $path');
  }
  for (final path in stale) {
    failures.add('Stale inventory row: $path');
  }

  for (final row in document.inventory.values) {
    for (final reference in row.findingIds) {
      if (!document.declaredIds.contains(reference)) {
        failures.add(
          'Inventory row ${row.path} references unknown ID $reference.',
        );
      }
    }
    if (releaseMode && _transientStatuses.contains(row.status)) {
      failures.add(
        'Inventory row ${row.path} remains ${row.status} in release mode.',
      );
    }
  }
  if (releaseMode) {
    for (final phase in document.phases) {
      if (_transientStatuses.contains(phase.status)) {
        failures.add(
          'Phase ${phase.id} remains ${phase.status} in release mode.',
        );
      }
    }
    for (final finding in document.findings) {
      if (_transientStatuses.contains(finding.status)) {
        failures.add(
          'Finding ${finding.id} remains ${finding.status} in release mode.',
        );
      }
    }
  }

  final uniqueFailures = failures.toSet().toList()..sort();
  return ProductionTrackerVerification(
    repositoryFileCount: files.length,
    inventoryRowCount: document.inventory.length,
    findingCount: document.findings.length,
    phaseCount: document.phases.length,
    failures: List<String>.unmodifiable(uniqueFailures),
  );
}

String? _synchronizeTracker(Directory root) {
  final tracker = File('${root.absolute.path}/$_trackerPath');
  if (!tracker.existsSync()) return 'Missing $_trackerPath.';

  final failures = <String>[];
  final repositoryFiles = _repositoryFiles(root, failures: failures);
  final contents = tracker.readAsStringSync();
  final document = _parseTracker(contents, failures);
  if (failures.isNotEmpty) {
    return 'Refusing to synchronize an invalid tracker:\n'
        '${(failures..sort()).join('\n')}';
  }

  final rows = <String>[];
  for (final path in repositoryFiles.toList()..sort()) {
    final existing = document.inventory[path];
    rows.add(
      existing?.source ??
          '| `${_escape(path)}` | ${_kind(path)} | unreviewed | - | - | - |',
    );
  }
  final replacement =
      '$_startMarker\n'
      '| File | Kind | Status | Finding IDs | Verification | Fix commit |\n'
      '| --- | --- | --- | --- | --- | --- |\n'
      '${rows.join('\n')}\n'
      '$_endMarker';
  final start = contents.indexOf(_startMarker);
  final end = contents.indexOf(_endMarker) + _endMarker.length;
  tracker.writeAsStringSync(contents.replaceRange(start, end, replacement));
  stdout.writeln(
    'Synchronized ${repositoryFiles.length} non-generated repository files.',
  );
  return null;
}

Set<String> _repositoryFiles(Directory root, {required List<String> failures}) {
  final result = Process.runSync('git', const [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) {
    failures.add('Could not enumerate repository files: ${result.stderr}');
    return const <String>{};
  }

  return LineSplitter.split(result.stdout as String).where((path) {
    if (path.isEmpty || _isGenerated(path)) return false;
    return FileSystemEntity.typeSync(
          '${root.path}/$path',
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound;
  }).toSet();
}

_TrackerDocument _parseTracker(String contents, List<String> failures) {
  final start = contents.indexOf(_startMarker);
  final end = contents.indexOf(_endMarker);
  if (start < 0 ||
      end < 0 ||
      end <= start ||
      contents.lastIndexOf(_startMarker) != start ||
      contents.lastIndexOf(_endMarker) != end) {
    failures.add(
      'Tracker inventory markers are missing, duplicated, or invalid.',
    );
    return const _TrackerDocument(
      inventory: {},
      phases: [],
      findings: [],
      declaredIds: {},
    );
  }

  final declaredIds = <String>{};
  final declaredIdPattern = RegExp(r'^[A-Z]+-[0-9]{3}$');
  for (final line in const LineSplitter().convert(contents)) {
    final cells = _markdownCells(line);
    if (cells == null || cells.isEmpty) continue;
    final candidate = cells.first;
    if (declaredIdPattern.hasMatch(candidate) && !declaredIds.add(candidate)) {
      failures.add('Duplicate tracker ID: $candidate.');
    }
  }

  final phases = <_PhaseRow>[];
  final phaseNumbers = <int>{};
  final phaseStart = contents.indexOf('## Phase Plan');
  final findingsStart = contents.indexOf('## Findings');
  if (phaseStart < 0 || findingsStart <= phaseStart) {
    failures.add('Phase Plan section is missing or invalid.');
  } else {
    final region = contents.substring(phaseStart, findingsStart);
    for (final entry in const LineSplitter().convert(region).indexed) {
      final lineNumber =
          const LineSplitter()
              .convert(contents.substring(0, phaseStart))
              .length +
          entry.$1 +
          1;
      final cells = _markdownCells(entry.$2);
      if (cells == null || cells.isEmpty) continue;
      if (cells.first == 'Phase' || cells.first == '---') continue;
      final phaseNumber = int.tryParse(cells.first);
      if (phaseNumber == null) continue;
      if (cells.length != 4) {
        failures.add(
          'Phase row ${cells.first} on line $lineNumber must have 4 '
          'columns, found ${cells.length}.',
        );
        continue;
      }
      final status = cells[2];
      if (!_validStatuses.contains(status)) {
        failures.add('Phase ${cells.first} has invalid status $status.');
      }
      if (!phaseNumbers.add(phaseNumber)) {
        failures.add('Duplicate phase row: $phaseNumber.');
        continue;
      }
      for (var index = 1; index < cells.length; index++) {
        if (cells[index].isEmpty) {
          failures.add(
            'Phase ${cells.first} has an empty column ${index + 1}.',
          );
        }
      }
      phases.add(_PhaseRow(id: phaseNumber, status: status));
    }
    if (phases.isEmpty) {
      failures.add('Phase Plan contains no phase rows.');
    } else {
      final highestPhase = phaseNumbers.reduce(
        (left, right) => left > right ? left : right,
      );
      for (var phase = 0; phase <= highestPhase; phase += 1) {
        if (!phaseNumbers.contains(phase)) {
          failures.add('Phase Plan is missing phase $phase.');
        }
      }
    }
  }

  final findings = <_FindingRow>[];
  final findingsEnd = contents.indexOf('## Generated Artifact Validation');
  if (findingsStart < 0 || findingsEnd <= findingsStart) {
    failures.add('Findings section is missing or invalid.');
  } else {
    final region = contents.substring(findingsStart, findingsEnd);
    for (final entry in const LineSplitter().convert(region).indexed) {
      final lineNumber =
          const LineSplitter()
              .convert(contents.substring(0, findingsStart))
              .length +
          entry.$1 +
          1;
      final cells = _markdownCells(entry.$2);
      if (cells == null || cells.isEmpty) continue;
      if (cells.first == 'ID' || cells.first == '---') continue;
      if (!declaredIdPattern.hasMatch(cells.first)) continue;
      if (cells.length != 8) {
        failures.add(
          'Findings row ${cells.first} on line $lineNumber must have 8 '
          'columns, found ${cells.length}.',
        );
        continue;
      }
      final severity = cells[1];
      final status = cells[3];
      if (!const {'P0', 'P1', 'P2', 'P3'}.contains(severity)) {
        failures.add('Finding ${cells.first} has invalid severity $severity.');
      }
      if (!_validStatuses.contains(status)) {
        failures.add('Finding ${cells.first} has invalid status $status.');
      }
      for (var index = 2; index < cells.length; index++) {
        if (cells[index].isEmpty) {
          failures.add(
            'Finding ${cells.first} has an empty column ${index + 1}.',
          );
        }
      }
      findings.add(_FindingRow(id: cells.first, status: status));
    }
  }

  final inventory = <String, _InventoryRow>{};
  final inventoryRegion = contents.substring(start + _startMarker.length, end);
  for (final entry in const LineSplitter().convert(inventoryRegion).indexed) {
    final line = entry.$2;
    final cells = _markdownCells(line);
    if (cells == null || cells.isEmpty) continue;
    if (cells.first == 'File' || cells.first == '---') continue;
    final lineNumber =
        const LineSplitter()
            .convert(contents.substring(0, start + _startMarker.length))
            .length +
        entry.$1 +
        1;
    if (cells.length != 6) {
      failures.add(
        'Inventory row on line $lineNumber must have 6 columns, found '
        '${cells.length}.',
      );
      continue;
    }
    final encodedPath = cells.first;
    if (encodedPath.length < 2 ||
        !encodedPath.startsWith('`') ||
        !encodedPath.endsWith('`')) {
      failures.add('Inventory row on line $lineNumber has an invalid path.');
      continue;
    }
    final path = encodedPath.substring(1, encodedPath.length - 1);
    final status = cells[2];
    if (path.isEmpty || path.startsWith('/') || path.contains('..')) {
      failures.add('Inventory row on line $lineNumber has unsafe path $path.');
    }
    if (!_validStatuses.contains(status)) {
      failures.add('Inventory row $path has invalid status $status.');
    }
    final findingIds = cells[3] == '-'
        ? const <String>[]
        : cells[3].split(',').map((id) => id.trim()).toList();
    for (final id in findingIds) {
      if (!declaredIdPattern.hasMatch(id)) {
        failures.add('Inventory row $path has malformed finding ID $id.');
      } else if (!declaredIds.contains(id)) {
        failures.add('Inventory row $path references unknown ID $id.');
      }
    }
    if (inventory.containsKey(path)) {
      failures.add('Duplicate inventory row: $path.');
      continue;
    }
    inventory[path] = _InventoryRow(
      path: path,
      status: status,
      findingIds: findingIds,
      source: line,
    );
  }

  return _TrackerDocument(
    inventory: Map<String, _InventoryRow>.unmodifiable(inventory),
    phases: List<_PhaseRow>.unmodifiable(phases),
    findings: List<_FindingRow>.unmodifiable(findings),
    declaredIds: Set<String>.unmodifiable(declaredIds),
  );
}

List<String>? _markdownCells(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) return null;
  final cells = <String>[];
  final buffer = StringBuffer();
  var escaped = false;
  for (var index = 1; index < trimmed.length - 1; index++) {
    final character = trimmed[index];
    if (character == '|' && !escaped) {
      cells.add(buffer.toString().trim().replaceAll(r'\|', '|'));
      buffer.clear();
      continue;
    }
    buffer.write(character);
    escaped = character == r'\' && !escaped;
    if (character != r'\') escaped = false;
  }
  cells.add(buffer.toString().trim().replaceAll(r'\|', '|'));
  return cells;
}

bool _isGenerated(String path) {
  return path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart') ||
      path.endsWith('.mocks.dart') ||
      path == 'pubspec.lock' ||
      path == 'ios/Podfile.lock' ||
      path == 'lib/objectbox-model.json' ||
      path.startsWith('ios/.spm.pods/');
}

String _kind(String path) {
  if (path.startsWith('lib/')) return 'Dart source';
  if (path.startsWith('test/') || path.startsWith('integration_test/')) {
    return 'Test';
  }
  if (path.startsWith('assets/')) return 'Asset';
  if (path.startsWith('docs/')) return 'Documentation';
  if (path.startsWith('android/')) return 'Android platform';
  if (path.startsWith('ios/')) return 'iOS platform';
  if (path.startsWith('.github/')) return 'CI';
  if (path.startsWith('scripts/') || path.startsWith('tool/')) return 'Tooling';
  return 'Project configuration';
}

String _escape(String path) => path.replaceAll('|', r'\|');

final class _TrackerDocument {
  const _TrackerDocument({
    required this.inventory,
    required this.phases,
    required this.findings,
    required this.declaredIds,
  });

  final Map<String, _InventoryRow> inventory;
  final List<_PhaseRow> phases;
  final List<_FindingRow> findings;
  final Set<String> declaredIds;
}

final class _InventoryRow {
  const _InventoryRow({
    required this.path,
    required this.status,
    required this.findingIds,
    required this.source,
  });

  final String path;
  final String status;
  final List<String> findingIds;
  final String source;
}

final class _PhaseRow {
  const _PhaseRow({required this.id, required this.status});

  final int id;
  final String status;
}

final class _FindingRow {
  const _FindingRow({required this.id, required this.status});

  final String id;
  final String status;
}
