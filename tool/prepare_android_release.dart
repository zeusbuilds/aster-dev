import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Immutable dependency inputs captured around Flutter's Release preparation.
final class AndroidReleaseDependencySnapshot {
  const AndroidReleaseDependencySnapshot({
    required this.lockfile,
    required this.packageGraph,
  });

  factory AndroidReleaseDependencySnapshot.capture(Directory repository) {
    final lockfile = File('${repository.path}/pubspec.lock');
    final packageConfig = File(
      '${repository.path}/.dart_tool/package_config.json',
    );
    if (!lockfile.existsSync() || !packageConfig.existsSync()) {
      throw const FormatException(
        'Run the enforced dependency step before Android Release preparation.',
      );
    }
    return AndroidReleaseDependencySnapshot(
      lockfile: lockfile.readAsStringSync(),
      packageGraph: _normalizePackageGraph(packageConfig.readAsStringSync()),
    );
  }

  final String lockfile;
  final String packageGraph;
}

/// Outcome of validating Flutter's generated Android Release plugin surface.
final class AndroidReleasePreparationReport {
  const AndroidReleasePreparationReport({
    required this.productionPlugins,
    required this.excludedDevelopmentPlugins,
    required this.failures,
  });

  final int productionPlugins;
  final int excludedDevelopmentPlugins;
  final List<String> failures;

  bool get passed => failures.isEmpty;
}

/// Verifies dependency immutability and the generated Release registrant.
AndroidReleasePreparationReport verifyAndroidReleasePreparation({
  required AndroidReleaseDependencySnapshot before,
  required AndroidReleaseDependencySnapshot after,
  required String pluginMetadata,
  required String generatedRegistrant,
  required String Function(String pluginPath) readPluginPubspec,
}) {
  final failures = <String>[];
  if (before.lockfile != after.lockfile) {
    failures.add('Flutter Release preparation changed pubspec.lock.');
  }
  if (before.packageGraph != after.packageGraph) {
    failures.add(
      'Flutter Release preparation changed the resolved package graph.',
    );
  }

  final plugins = _androidPlugins(pluginMetadata, failures);
  final expectedProduction = <String>{};
  final development = <String>{};
  for (final plugin in plugins) {
    final name = plugin.name;
    final requiresRegistration = _requiresAndroidRegistration(
      name,
      plugin.path,
      readPluginPubspec,
      failures,
    );
    if (!requiresRegistration) continue;
    if (plugin.isDevelopmentDependency) {
      development.add(name);
    } else {
      expectedProduction.add(name);
    }
  }

  final registrations = <String>{};
  for (final match in _registrationMarker.allMatches(generatedRegistrant)) {
    final name = match.group(1)!;
    if (!registrations.add(name)) {
      failures.add('Android plugin $name is registered more than once.');
    }
  }
  if (!generatedRegistrant.contains('Generated file. Do not edit.')) {
    failures.add('Android GeneratedPluginRegistrant.java is malformed.');
  }

  final leakedDevelopment = registrations.intersection(development).toList()
    ..sort();
  for (final name in leakedDevelopment) {
    failures.add(
      'Development plugin $name leaked into the Release registrant.',
    );
  }
  final missingProduction =
      expectedProduction.difference(registrations).toList()..sort();
  for (final name in missingProduction) {
    failures.add(
      'Production plugin $name is missing from the Release registrant.',
    );
  }
  final unknown =
      registrations
          .difference(expectedProduction)
          .difference(development)
          .toList()
        ..sort();
  for (final name in unknown) {
    failures.add('Unknown plugin $name is present in the Release registrant.');
  }

  failures.sort();
  return AndroidReleasePreparationReport(
    productionPlugins: expectedProduction.length,
    excludedDevelopmentPlugins: development.length,
    failures: List.unmodifiable(failures),
  );
}

Future<void> main() async {
  final repository = Directory.current.absolute;
  AndroidReleaseDependencySnapshot before;
  try {
    before = AndroidReleaseDependencySnapshot.capture(repository);
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
    return;
  }

  // Flutter issue 169336 requires a Pub-enabled config-only pass to filter
  // development plugins from the Android Release registrant. The snapshots
  // make that upstream workaround fail closed on any dependency drift.
  Process process;
  try {
    process = await Process.start(
      'fvm',
      const ['flutter', 'build', 'apk', '--release', '--config-only'],
      workingDirectory: repository.path,
      mode: ProcessStartMode.inheritStdio,
    );
  } on ProcessException {
    stderr.writeln('Flutter Android Release configuration could not start.');
    exitCode = 1;
    return;
  }
  final processExitCode = await process.exitCode;
  if (processExitCode != 0) {
    stderr.writeln('Flutter Android Release configuration failed.');
    exitCode = processExitCode;
    return;
  }

  try {
    final report = verifyAndroidReleasePreparation(
      before: before,
      after: AndroidReleaseDependencySnapshot.capture(repository),
      pluginMetadata: File('${repository.path}/.flutter-plugins-dependencies')
          .readAsStringSync(),
      generatedRegistrant: File(
        '${repository.path}/android/app/src/main/java/io/flutter/plugins/'
        'GeneratedPluginRegistrant.java',
      ).readAsStringSync(),
      readPluginPubspec: (pluginPath) =>
          File('$pluginPath/pubspec.yaml').readAsStringSync(),
    );
    if (!report.passed) {
      for (final failure in report.failures) {
        stderr.writeln(failure);
      }
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Android Release tooling prepared with '
      '${report.productionPlugins} production '
      '${_plural(report.productionPlugins, 'plugin')} and '
      '${report.excludedDevelopmentPlugins} development '
      '${_plural(report.excludedDevelopmentPlugins, 'plugin')} excluded; '
      'the lockfile and resolved package graph are unchanged.',
    );
  } on Object catch (error) {
    stderr.writeln('Android Release preparation validation failed: $error');
    exitCode = 1;
  }
}

String _normalizePackageGraph(String packageConfig) {
  final decoded = jsonDecode(packageConfig);
  if (decoded is! Map<String, Object?> ||
      decoded['packages'] is! List<Object?>) {
    throw const FormatException('Malformed .dart_tool/package_config.json.');
  }
  final packages = <Map<String, Object?>>[];
  for (final value in decoded['packages']! as List<Object?>) {
    if (value is! Map<String, Object?> || value['name'] is! String) {
      throw const FormatException('Malformed package entry.');
    }
    packages.add({
      'name': value['name'],
      'rootUri': value['rootUri'],
      'packageUri': value['packageUri'],
      'languageVersion': value['languageVersion'],
    });
  }
  packages.sort(
    (left, right) =>
        (left['name']! as String).compareTo(right['name']! as String),
  );
  return jsonEncode(packages);
}

List<_AndroidPlugin> _androidPlugins(
  String pluginMetadata,
  List<String> failures,
) {
  Object? decoded;
  try {
    decoded = jsonDecode(pluginMetadata);
  } on FormatException {
    failures.add('.flutter-plugins-dependencies is not valid JSON.');
    return const [];
  }
  if (decoded is! Map<String, Object?> ||
      decoded['plugins'] is! Map<String, Object?>) {
    failures.add('.flutter-plugins-dependencies has no plugin map.');
    return const [];
  }
  final platforms = decoded['plugins']! as Map<String, Object?>;
  final android = platforms['android'];
  if (android is! List<Object?>) {
    failures.add('.flutter-plugins-dependencies has no Android plugin list.');
    return const [];
  }

  final plugins = <_AndroidPlugin>[];
  final names = <String>{};
  for (final value in android) {
    if (value is! Map<String, Object?> ||
        value['name'] is! String ||
        value['path'] is! String ||
        value['dev_dependency'] is! bool) {
      failures.add('Android plugin metadata contains a malformed entry.');
      continue;
    }
    final name = value['name']! as String;
    if (!names.add(name)) {
      failures.add('Android plugin metadata contains duplicate $name entries.');
      continue;
    }
    plugins.add(
      _AndroidPlugin(
        name: name,
        path: value['path']! as String,
        isDevelopmentDependency: value['dev_dependency']! as bool,
      ),
    );
  }
  return plugins;
}

bool _requiresAndroidRegistration(
  String name,
  String path,
  String Function(String pluginPath) readPluginPubspec,
  List<String> failures,
) {
  try {
    final document = loadYaml(readPluginPubspec(path));
    final flutter = document is YamlMap ? document['flutter'] : null;
    final plugin = flutter is YamlMap ? flutter['plugin'] : null;
    final platforms = plugin is YamlMap ? plugin['platforms'] : null;
    final android = platforms is YamlMap ? platforms['android'] : null;
    if (android is! YamlMap) return false;
    return android['package'] is String && android['pluginClass'] is String;
  } on Object {
    failures.add('Could not parse Android plugin metadata for $name.');
    return false;
  }
}

final _registrationMarker = RegExp(
  r'Error registering plugin ([A-Za-z0-9_]+),',
);

String _plural(int count, String noun) => count == 1 ? noun : '${noun}s';

final class _AndroidPlugin {
  const _AndroidPlugin({
    required this.name,
    required this.path,
    required this.isDevelopmentDependency,
  });

  final String name;
  final String path;
  final bool isDevelopmentDependency;
}
