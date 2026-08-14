import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Result of checking one repository tree against the barrel policy.
final class BarrelVerification {
  const BarrelVerification({
    required this.sourceCount,
    required this.barrelCount,
    required this.failures,
  });

  /// Number of non-generated Dart sources examined under `lib/`.
  final int sourceCount;

  /// Number of sources containing at least one export directive.
  final int barrelCount;

  /// Deterministically sorted parse or policy failures.
  final List<String> failures;

  /// Whether every examined source satisfies the policy.
  bool get passed => failures.isEmpty;
}

/// Verifies the repository's boundary-only barrel export policy.
void main() {
  final result = verifyBarrelExports(Directory.current);
  if (!result.passed) {
    for (final failure in result.failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Barrel policy verified for ${result.barrelCount} boundaries and '
    '${result.sourceCount} Dart sources.',
  );
}

/// Checks owned Dart sources beneath [repositoryRoot].
BarrelVerification verifyBarrelExports(Directory repositoryRoot) {
  final root = repositoryRoot.absolute;
  final sourceRoot = Directory('${root.path}/lib');
  if (!sourceRoot.existsSync()) {
    return const BarrelVerification(
      sourceCount: 0,
      barrelCount: 0,
      failures: ['Missing lib directory. Run this tool from the repo root.'],
    );
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
    final parsed = _parseDirectives(root, file, failures);
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
        '${_relative(root, path)}: barrel must be named $expectedName for its '
        '$directoryName boundary.',
      );
    }

    final exportUris = parsed.exports
        .map((directive) => directive.uri)
        .toList();
    final sortedUris = [...exportUris]..sort();
    if (!_sameOrder(exportUris, sortedUris)) {
      failures.add('${_relative(root, path)}: exports must be sorted by URI.');
    }
    if (exportUris.toSet().length != exportUris.length) {
      failures.add('${_relative(root, path)}: duplicate export directive.');
    }

    for (final export in parsed.exports) {
      final owner = _relative(root, path);
      if (export.isConditional) {
        failures.add(
          '$owner:${export.line}: conditional barrel exports are prohibited.',
        );
      }
      if (!_isRelativeUri(export.uri)) {
        failures.add(
          '$owner:${export.line}: barrels may export only relative repository '
          'sources.',
        );
        continue;
      }
      if (_isForbiddenExport(export.uri)) {
        failures.add(
          '$owner:${export.line}: generated or private source must not be '
          'exported.',
        );
      }
      final target = _resolve(file, export.uri);
      if (!_isWithinSourceRoot(sourceRoot, target)) {
        failures.add(
          '$owner:${export.line}: export ${export.uri} escapes the lib '
          'boundary.',
        );
      } else if (!target.endsWith('.dart') || !File(target).existsSync()) {
        failures.add(
          '$owner:${export.line}: missing Dart export ${export.uri}.',
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
          '${_relative(root, file.path)}:${import.line}: a source must not '
          'import its own directory barrel ${import.uri}.',
        );
      }
    }
  }

  _findBarrelCycles(root, barrels, directives, failures);
  return BarrelVerification(
    sourceCount: sources.length,
    barrelCount: barrels.length,
    failures: List<String>.unmodifiable(failures..sort()),
  );
}

void _findBarrelCycles(
  Directory root,
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
      ].map((path) => _relative(root, path)).join(' -> ');
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

_Directives _parseDirectives(Directory root, File file, List<String> failures) {
  final imports = <_Directive>[];
  final exports = <_Directive>[];
  final parsed = parseFile(
    path: file.path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  for (final error in parsed.errors) {
    final line = parsed.lineInfo.getLocation(error.offset).lineNumber;
    failures.add(
      '${_relative(root, file.path)}:$line: parse error: ${error.message}',
    );
  }
  for (final directive in parsed.unit.directives) {
    switch (directive) {
      case ImportDirective():
        final uri = directive.uri.stringValue;
        if (uri != null) {
          imports.add(
            _Directive(
              uri: uri,
              line: parsed.lineInfo
                  .getLocation(directive.uri.offset)
                  .lineNumber,
            ),
          );
        }
        for (final configuration in directive.configurations) {
          final configuredUri = configuration.uri.stringValue;
          if (configuredUri != null) {
            imports.add(
              _Directive(
                uri: configuredUri,
                line: parsed.lineInfo
                    .getLocation(configuration.uri.offset)
                    .lineNumber,
              ),
            );
          }
        }
      case ExportDirective():
        final uri = directive.uri.stringValue;
        if (uri != null) {
          exports.add(
            _Directive(
              uri: uri,
              line: parsed.lineInfo
                  .getLocation(directive.uri.offset)
                  .lineNumber,
              isConditional: directive.configurations.isNotEmpty,
            ),
          );
        }
      default:
        break;
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

bool _isWithinSourceRoot(Directory sourceRoot, String path) {
  final rootPath = sourceRoot.absolute.path;
  return path.startsWith('$rootPath${Platform.pathSeparator}');
}

String _relative(Directory root, String path) {
  final rootPath = root.absolute.path;
  final absolute = File(path).absolute.path;
  return absolute.startsWith('$rootPath/')
      ? absolute.substring(rootPath.length + 1)
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
  const _Directive({
    required this.uri,
    required this.line,
    this.isConditional = false,
  });

  final String uri;
  final int line;
  final bool isConditional;
}
