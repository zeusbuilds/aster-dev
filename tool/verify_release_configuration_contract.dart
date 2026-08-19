import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'release_configuration_manifest.dart';

/// Verifies runtime, tooling, build, and documentation configuration parity.
List<String> verifyReleaseConfigurationContract(Directory repository) {
  final root = repository.absolute.path;
  final failures = <String>[];
  final runtimeKeys = <String>{};
  for (final relative in const [
    'lib/core/config/app_environment.dart',
    'lib/core/config/market_data_configuration.dart',
    'lib/core/config/public_link_configuration.dart',
  ]) {
    final file = File('$root/$relative');
    final source = _read(file, failures);
    if (source == null) continue;
    final parsed = parseString(
      content: source,
      path: file.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    if (parsed.errors.isNotEmpty) {
      failures.add('$relative could not be parsed for release keys.');
      continue;
    }
    final collector = _CompileTimeEnvironmentKeyCollector();
    parsed.unit.accept(collector);
    runtimeKeys.addAll(collector.keys);
  }
  final missingFromRuntime = ReleaseConfigurationKey.all.difference(
    runtimeKeys,
  );
  final unknownRuntime = runtimeKeys.difference(ReleaseConfigurationKey.all);
  if (missingFromRuntime.isNotEmpty || unknownRuntime.isNotEmpty) {
    failures.add(
      'Runtime release keys differ from the manifest contract: '
      'missing=${_sorted(missingFromRuntime)}, '
      'unknown=${_sorted(unknownRuntime)}.',
    );
  }

  final makefile = _read(File('$root/Makefile'), failures);
  if (makefile != null) {
    for (final required in const [
      'prepare-android-release: verify-release-configuration',
      'prepare-ios-release: verify-release-configuration',
      'android-release-bundle: prepare-android-release',
      'android-release-apks: prepare-android-release',
      'ios-release-archive: prepare-ios-release',
      'ios-release-ipa: prepare-ios-release',
      'tool/verify_release_configuration.dart',
      'tool/verify_ios_export_options.dart',
    ]) {
      if (!makefile.contains(required)) {
        failures.add('Makefile is missing release contract: $required.');
      }
    }
    final defineCount = RegExp(
      r'--dart-define-from-file="\$\(RELEASE_CONFIG\)"',
    ).allMatches(makefile).length;
    if (defineCount != 4) {
      failures.add(
        'Every four release artifact builds must consume RELEASE_CONFIG.',
      );
    }
  }

  final ignore = _read(File('$root/.gitignore'), failures);
  if (ignore != null &&
      (!ignore.contains('/config/*.local.json') ||
          !ignore.contains('/ios/ExportOptions*.local.plist'))) {
    failures.add(
      'Local release configuration and export policy are not ignored.',
    );
  }

  final example = _read(File('$root/config/release.example.json'), failures);
  if (example != null) {
    try {
      final decoded = jsonDecode(example);
      final keys = decoded is Map<String, Object?>
          ? decoded.keys.toSet()
          : null;
      if (keys == null ||
          !keys.containsAll(ReleaseConfigurationKey.publicRequired)) {
        failures.add(
          'Release example omits public-distribution required keys.',
        );
      }
    } on FormatException {
      failures.add('Release example is not valid JSON.');
    }
    try {
      ReleaseConfigurationManifest.parse(
        example,
        audience: ReleaseAudience.publicDistribution,
      );
      failures.add(
        'Release example must fail closed until placeholders change.',
      );
    } on FormatException catch (error) {
      if (!error.message.contains('placeholder')) {
        failures.add(
          'Release example does not fail specifically on placeholders.',
        );
      }
    }
  }

  final documentation = _read(File('$root/config/README.md'), failures);
  if (documentation != null) {
    for (final required in const [
      '--dart-define-from-file',
      'internal-beta',
      'public-distribution',
      'must never be committed',
    ]) {
      if (!documentation.contains(required)) {
        failures.add('Release configuration guide is missing: $required.');
      }
    }
  }
  return failures.toSet().toList()..sort();
}

void main() {
  final failures = verifyReleaseConfigurationContract(Directory.current);
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Release configuration keys, build targets, example, and ignore policy '
    'verified.',
  );
}

String? _read(File file, List<String> failures) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    failures.add('Missing or unsafe ${file.path}.');
    return null;
  }
  return file.readAsStringSync();
}

String _sorted(Set<String> values) => (values.toList()..sort()).join(',');

final class _CompileTimeEnvironmentKeyCollector
    extends RecursiveAstVisitor<void> {
  final keys = <String>{};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName;
    if (_isEnvironmentConstructor(constructor.toSource())) {
      _collectFirstString(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (const {'String', 'int'}.contains(node.target?.toSource()) &&
        node.methodName.name == 'fromEnvironment') {
      _collectFirstString(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  void _collectFirstString(ArgumentList arguments) {
    final values = arguments.arguments;
    if (values.isEmpty || values.first is! StringLiteral) return;
    final value = (values.first as StringLiteral).stringValue;
    if (value != null) keys.add(value);
  }

  bool _isEnvironmentConstructor(String source) =>
      source == 'String.fromEnvironment' || source == 'int.fromEnvironment';
}
