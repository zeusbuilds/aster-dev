import 'dart:convert';
import 'dart:io';

const _trackerPath = 'docs/PRODUCTION_REFACTOR_TRACKER.md';
const _startMarker = '<!-- FILE_INVENTORY_START -->';
const _endMarker = '<!-- FILE_INVENTORY_END -->';

void main(List<String> arguments) {
  final shouldSync = arguments.contains('--sync');
  final tracker = File(_trackerPath);
  if (!tracker.existsSync()) {
    stderr.writeln('Missing $_trackerPath.');
    exitCode = 1;
    return;
  }

  final repositoryFiles = _repositoryFiles();
  final contents = tracker.readAsStringSync();
  final inventory = _parseInventory(contents);
  final trackedPaths = inventory.keys.toSet();
  final missing = repositoryFiles.difference(trackedPaths).toList()..sort();
  final stale = trackedPaths.difference(repositoryFiles).toList()..sort();

  if (shouldSync) {
    final rows = <String>[];
    for (final path in repositoryFiles.toList()..sort()) {
      final existing = inventory[path];
      rows.add(
        existing ??
            '| `${_escape(path)}` | ${_kind(path)} | unreviewed | - | - | - |',
      );
    }
    final replacement =
        '$_startMarker\n'
        '| File | Kind | Status | Finding IDs | Verification | Fix commit |\n'
        '| --- | --- | --- | --- | --- | --- |\n'
        '${rows.join('\n')}\n'
        '$_endMarker';
    final updated = contents.replaceRange(
      contents.indexOf(_startMarker),
      contents.indexOf(_endMarker) + _endMarker.length,
      replacement,
    );
    tracker.writeAsStringSync(updated);
    stdout.writeln(
      'Synchronized ${repositoryFiles.length} non-generated repository files.',
    );
    return;
  }

  if (missing.isEmpty && stale.isEmpty) {
    stdout.writeln(
      'Tracker inventory matches ${repositoryFiles.length} non-generated files.',
    );
    return;
  }

  for (final path in missing) {
    stderr.writeln('Missing inventory row: $path');
  }
  for (final path in stale) {
    stderr.writeln('Stale inventory row: $path');
  }
  stderr.writeln('Run: dart run tool/verify_production_tracker.dart --sync');
  exitCode = 1;
}

Set<String> _repositoryFiles() {
  final result = Process.runSync('git', const [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
  ]);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    exit(result.exitCode);
  }

  return LineSplitter.split(result.stdout as String).where((path) {
    if (path.isEmpty || _isGenerated(path)) return false;
    return FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound;
  }).toSet();
}

Map<String, String> _parseInventory(String contents) {
  final start = contents.indexOf(_startMarker);
  final end = contents.indexOf(_endMarker);
  if (start < 0 || end < 0 || end <= start) {
    stderr.writeln('Tracker inventory markers are missing or invalid.');
    exit(1);
  }

  final inventory = <String, String>{};
  final region = contents.substring(start, end);
  final rowPattern = RegExp(r'^\| `([^`]+)` \|.*\|$', multiLine: true);
  for (final match in rowPattern.allMatches(region)) {
    final path = match.group(1)!.replaceAll(r'\|', '|');
    inventory[path] = match.group(0)!;
  }
  return inventory;
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
