import 'dart:io';

/// Verifies the repository's boundary-only barrel export policy.
void main() {
  final sourceRoot = Directory('lib').absolute;
  if (!sourceRoot.existsSync()) {
    stderr.writeln('Missing lib directory. Run this tool from the repo root.');
    exitCode = 1;
    return;
  }

  final sources =
      sourceRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => _isOwnedDartSource(file.path))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final directives = <String, _Directives>{};
  final barrels = <String>{};
  final failures = <String>[];

  for (final file in sources) {
    final parsed = _parseDirectives(file);
    directives[file.absolute.path] = parsed;
    if (parsed.exports.isEmpty) continue;

    final path = file.absolute.path;
    barrels.add(path);
    final directoryName = file.parent.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    final expectedName = directoryName == 'view_model'
        ? 'view_models.dart'
        : '$directoryName.dart';
    if (_basename(path) != expectedName) {
      failures.add(
        '${_relative(path)}: barrel must be named $expectedName for its '
        '$directoryName boundary.',
      );
    }

    final exportUris = parsed.exports
        .map((directive) => directive.uri)
        .toList();
    final sortedUris = [...exportUris]..sort();
    if (!_sameOrder(exportUris, sortedUris)) {
      failures.add('${_relative(path)}: exports must be sorted by URI.');
    }
    if (exportUris.toSet().length != exportUris.length) {
      failures.add('${_relative(path)}: duplicate export directive.');
    }

    for (final export in parsed.exports) {
      if (!_isRelativeUri(export.uri)) {
        failures.add(
          '${_relative(path)}:${export.line}: barrels may export only '
          'relative repository sources.',
        );
        continue;
      }
      if (_isForbiddenExport(export.uri)) {
        failures.add(
          '${_relative(path)}:${export.line}: generated or private source '
          'must not be exported.',
        );
      }
      final target = _resolve(file, export.uri);
      if (!File(target).existsSync()) {
        failures.add(
          '${_relative(path)}:${export.line}: missing export ${export.uri}.',
        );
      }
    }
  }

  for (final file in sources) {
    final parsed = directives[file.absolute.path]!;
    for (final import in parsed.imports) {
      if (!_isRelativeUri(import.uri)) continue;
      final target = _resolve(file, import.uri);
      if (barrels.contains(target) &&
          file.parent.absolute.path == File(target).parent.absolute.path) {
        failures.add(
          '${_relative(file.path)}:${import.line}: a source must not import '
          'its own directory barrel ${import.uri}.',
        );
      }
    }
  }

  _findBarrelCycles(barrels, directives, failures);

  if (failures.isNotEmpty) {
    for (final failure in failures..sort()) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Barrel policy verified for ${barrels.length} boundaries and '
    '${sources.length} Dart sources.',
  );
}

void _findBarrelCycles(
  Set<String> barrels,
  Map<String, _Directives> directives,
  List<String> failures,
) {
  final visiting = <String>{};
  final visited = <String>{};

  void visit(String barrel, List<String> path) {
    if (visiting.contains(barrel)) {
      final cycleStart = path.indexOf(barrel);
      final cycle = [
        ...path.sublist(cycleStart),
        barrel,
      ].map(_relative).join(' -> ');
      failures.add('Barrel export cycle: $cycle.');
      return;
    }
    if (!visited.add(barrel)) return;

    visiting.add(barrel);
    final file = File(barrel);
    for (final export in directives[barrel]!.exports) {
      if (!_isRelativeUri(export.uri)) continue;
      final target = _resolve(file, export.uri);
      if (barrels.contains(target)) visit(target, [...path, barrel]);
    }
    visiting.remove(barrel);
  }

  for (final barrel in barrels) {
    visit(barrel, const []);
  }
}

_Directives _parseDirectives(File file) {
  final imports = <_Directive>[];
  final exports = <_Directive>[];
  final pattern = RegExp(r'''^\s*(import|export)\s+['"]([^'"]+)['"]''');
  final lines = file.readAsLinesSync();
  for (var index = 0; index < lines.length; index++) {
    final match = pattern.firstMatch(lines[index]);
    if (match == null) continue;
    final directive = _Directive(uri: match.group(2)!, line: index + 1);
    if (match.group(1) == 'import') {
      imports.add(directive);
    } else {
      exports.add(directive);
    }
  }
  return _Directives(imports: imports, exports: exports);
}

bool _isOwnedDartSource(String path) {
  return path.endsWith('.dart') &&
      !path.endsWith('.g.dart') &&
      !path.endsWith('.freezed.dart') &&
      !path.endsWith('.mocks.dart');
}

bool _isRelativeUri(String uri) {
  return !uri.startsWith('dart:') &&
      !uri.startsWith('package:') &&
      !uri.startsWith('/');
}

bool _isForbiddenExport(String uri) {
  final name = _basename(uri);
  return name.startsWith('_') ||
      name.endsWith('.g.dart') ||
      name.endsWith('.freezed.dart') ||
      name.endsWith('.mocks.dart');
}

String _resolve(File owner, String relativeUri) {
  return File.fromUri(owner.parent.uri.resolve(relativeUri)).absolute.path;
}

String _relative(String path) {
  final root = Directory.current.absolute.path;
  final absolute = File(path).absolute.path;
  return absolute.startsWith('$root/')
      ? absolute.substring(root.length + 1)
      : absolute;
}

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

bool _sameOrder(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _Directives {
  const _Directives({required this.imports, required this.exports});

  final List<_Directive> imports;
  final List<_Directive> exports;
}

final class _Directive {
  const _Directive({required this.uri, required this.line});

  final String uri;
  final int line;
}
