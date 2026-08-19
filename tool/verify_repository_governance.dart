import 'dart:io';

import 'package:yaml/yaml.dart';

/// Verifies versioned ownership, dependency-update, review, and CI policy.
List<String> verifyRepositoryGovernance(Directory repository) {
  final root = repository.absolute.path;
  final failures = <String>[];
  final workflows =
      Directory('$root/.github/workflows')
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (file) => file.path.endsWith('.yml') || file.path.endsWith('.yaml'),
          )
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  final workflowNames = workflows
      .map((file) => file.uri.pathSegments.last)
      .toSet();
  const expectedWorkflowNames = {'dart.yml', 'platform.yml'};
  if (workflowNames.length != expectedWorkflowNames.length ||
      !workflowNames.containsAll(expectedWorkflowNames)) {
    failures.add('Expected exactly dart.yml and platform.yml workflow files.');
  }
  for (final workflow in workflows) {
    _verifyWorkflow(workflow, failures);
  }

  final codeowners = _read(File('$root/.github/CODEOWNERS'), failures);
  if (codeowners != null) {
    const expected = <String>[
      '* @zeusbuilds',
      '/.github/ @zeusbuilds',
      '/android/ @zeusbuilds',
      '/ios/ @zeusbuilds',
      '/lib/core/ @zeusbuilds',
      '/lib/features/wallet/ @zeusbuilds',
      '/scripts/ @zeusbuilds',
      '/tool/ @zeusbuilds',
    ];
    final active = codeowners
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList(growable: false);
    if (!_orderedEquals(active, expected)) {
      failures.add(
        'CODEOWNERS active rules must exactly match the reviewed ownership '
        'order.',
      );
    }
  }

  final dependabot = _read(File('$root/.github/dependabot.yml'), failures);
  if (dependabot != null) {
    try {
      final document = loadYaml(dependabot);
      final updates = document is YamlMap ? document['updates'] : null;
      final ecosystems = <String, YamlMap>{};
      if (updates is YamlList) {
        for (final entry in updates.whereType<YamlMap>()) {
          final ecosystem = entry['package-ecosystem'];
          if (ecosystem is String && !ecosystems.containsKey(ecosystem)) {
            ecosystems[ecosystem] = entry;
          } else {
            failures.add('Dependabot ecosystems must be unique mappings.');
          }
        }
      }
      const required = <String, (String, String)>{
        'pub': ('/', 'weekly'),
        'github-actions': ('/', 'weekly'),
        'gradle': ('/android', 'monthly'),
        'bundler': ('/', 'monthly'),
      };
      if (document is! YamlMap ||
          document['version'] != 2 ||
          updates is! YamlList ||
          updates.length != required.length ||
          ecosystems.keys.toSet().length != required.length ||
          !ecosystems.keys.toSet().containsAll(required.keys)) {
        failures.add(
          'Dependabot does not cover every owned package ecosystem.',
        );
      } else {
        for (final MapEntry(key: ecosystem, value: policy)
            in required.entries) {
          final entry = ecosystems[ecosystem]!;
          final schedule = entry['schedule'];
          final pullRequestLimit = entry['open-pull-requests-limit'];
          if (entry['directory'] != policy.$1 ||
              schedule is! YamlMap ||
              schedule['interval'] != policy.$2 ||
              pullRequestLimit is! int ||
              pullRequestLimit <= 0 ||
              pullRequestLimit > 10) {
            failures.add(
              'Dependabot $ecosystem ownership, schedule, or bounds drifted.',
            );
          }
        }
      }
      if (document is YamlMap && document.containsKey('registries')) {
        failures.add('Dependabot must not consume private registries.');
      }
    } on Object {
      failures.add('Dependabot configuration is malformed.');
    }
  }

  final template = _read(
    File('$root/.github/pull_request_template.md'),
    failures,
  );
  if (template != null) {
    for (final phrase in const [
      'make lint',
      'Generated sources',
      'No secret',
      'Tracker rows',
    ]) {
      if (!template.contains(phrase)) {
        failures.add('Pull request template is missing $phrase policy.');
      }
    }
  }

  return (failures.toSet().toList()..sort());
}

Future<void> main() async {
  final failures = verifyRepositoryGovernance(Directory.current);
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Repository governance and CI policy verified.');
}

void _verifyWorkflow(File file, List<String> failures) {
  final source = _read(file, failures);
  if (source == null) return;
  final YamlMap? document;
  try {
    final parsed = loadYaml(source);
    document = parsed is YamlMap ? parsed : null;
  } on Object {
    failures.add('${file.path} is not valid workflow YAML.');
    return;
  }
  if (document == null) {
    failures.add('${file.path} must contain one workflow mapping.');
    return;
  }
  final permissions = document['permissions'];
  if (permissions is! YamlMap ||
      permissions.length != 1 ||
      permissions['contents'] != 'read') {
    failures.add('${file.path} must declare read-only contents permission.');
  }
  if (RegExp(
    r'\$\{\{[^}]*\b(?:secrets|github\s*\.\s*token)\b',
    multiLine: true,
  ).hasMatch(source)) {
    failures.add('${file.path} must not consume repository secrets.');
  }
  if (_hasWorkflowEvent(document['on'], 'pull_request_target')) {
    failures.add('${file.path} must not use pull_request_target.');
  }
  final jobs = document['jobs'];
  if (jobs is! YamlMap || jobs.isEmpty) {
    failures.add('${file.path} must declare at least one job.');
  } else {
    for (final MapEntry(:key, :value) in jobs.entries) {
      final timeout = value is YamlMap ? value['timeout-minutes'] : null;
      if (key is! String ||
          value is! YamlMap ||
          timeout is! int ||
          timeout <= 0 ||
          timeout > 120) {
        failures.add(
          '${file.path} job $key must have a 1...120 minute timeout.',
        );
      }
      if (value is! YamlMap) continue;
      if (value.containsKey('permissions')) {
        failures.add(
          '${file.path} job $key must not override workflow permissions.',
        );
      }
      final reusableWorkflow = value['uses'];
      if (reusableWorkflow != null) {
        _verifyActionReference(
          reusableWorkflow,
          file: file,
          failures: failures,
        );
      }
      final steps = value['steps'];
      if (steps is! YamlList) continue;
      for (final step in steps) {
        if (step is! YamlMap || !step.containsKey('uses')) continue;
        _verifyActionReference(step['uses'], file: file, failures: failures);
      }
    }
  }
  final commands = _workflowRunCommands(document);
  if (file.path.endsWith('/platform.yml')) {
    if (jobs is! YamlMap ||
        !_setEquals(jobs.keys.whereType<String>().toSet(), const {
          'android-debug',
          'ios-simulator',
        })) {
      failures.add(
        'Platform workflow must contain exactly the reviewed platform jobs.',
      );
    }
    for (final required in const <String>[
      'flutter pub get --enforce-lockfile',
      'dart run build_runner build',
      'flutter build apk --debug --no-pub',
      './gradlew :app:testDebugUnitTest --no-daemon',
      'bundle exec flutter build ios --simulator --debug --no-pub',
    ]) {
      if (!commands.contains(required)) {
        failures.add('Platform workflow is missing: $required.');
      }
    }
    final android = jobs is YamlMap ? jobs['android-debug'] : null;
    final ios = jobs is YamlMap ? jobs['ios-simulator'] : null;
    if (android is! YamlMap || android['runs-on'] != 'ubuntu-24.04') {
      failures.add('Android platform CI must pin ubuntu-24.04.');
    }
    if (ios is! YamlMap || ios['runs-on'] != 'macos-26') {
      failures.add('iOS platform CI must pin macos-26.');
    }
    if (!_jobUsesJava21(android)) {
      failures.add('Android platform CI must configure Java 21.');
    }
    if (commands.any(
      (command) =>
          command.contains('--release') ||
          command.toLowerCase().contains('regtest') ||
          command.contains('ASTER_'),
    )) {
      failures.add(
        'Platform CI must remain compile-only and configuration-free.',
      );
    }
  } else if (file.path.endsWith('/dart.yml')) {
    if (jobs is! YamlMap ||
        !_setEquals(jobs.keys.whereType<String>().toSet(), const {
          'format-and-analyze',
        })) {
      failures.add('Quality workflow must contain exactly one reviewed job.');
    }
    final quality = jobs is YamlMap ? jobs['format-and-analyze'] : null;
    if (quality is! YamlMap || quality['runs-on'] != 'ubuntu-24.04') {
      failures.add('Quality CI must pin ubuntu-24.04.');
    }
    for (final required in const <String>[
      'flutter pub get --enforce-lockfile',
      'dart format --output=none --set-exit-if-changed .',
      'dart run build_runner build',
      'flutter analyze --no-pub --fatal-warnings --fatal-infos',
      'flutter test --no-pub',
      'dart run tool/verify_dartdoc.dart',
      'dart run tool/verify_toolchain.dart',
      'dart run tool/verify_barrel_exports.dart',
      'dart run tool/verify_architecture.dart',
      'dart run tool/verify_design_system.dart',
      'dart run tool/verify_repository_governance.dart',
      'dart run tool/verify_release_configuration_contract.dart',
      'dart run tool/verify_production_tracker.dart',
    ]) {
      if (!commands.contains(required)) {
        failures.add('Quality workflow is missing: $required.');
      }
    }
  }
}

void _verifyActionReference(
  Object? value, {
  required File file,
  required List<String> failures,
}) {
  if (value is! String || value.isEmpty) {
    failures.add('${file.path} contains a malformed action reference.');
    return;
  }
  if (value.startsWith('./')) return;
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$')
      .hasMatch(value)) {
    failures.add('${file.path} contains an unpinned action: $value.');
  }
}

bool _hasWorkflowEvent(Object? value, String event) {
  if (value == event) return true;
  if (value is YamlList) return value.contains(event);
  if (value is YamlMap) return value.containsKey(event);
  return false;
}

List<String> _workflowRunCommands(YamlMap document) {
  final commands = <String>[];
  final jobs = document['jobs'];
  if (jobs is! YamlMap) return commands;
  for (final job in jobs.values.whereType<YamlMap>()) {
    final steps = job['steps'];
    if (steps is! YamlList) continue;
    for (final step in steps.whereType<YamlMap>()) {
      final command = step['run'];
      if (command is String) commands.add(command);
    }
  }
  return commands;
}

bool _jobUsesJava21(Object? job) {
  if (job is! YamlMap) return false;
  final steps = job['steps'];
  if (steps is! YamlList) return false;
  for (final step in steps.whereType<YamlMap>()) {
    final action = step['uses'];
    final options = step['with'];
    if (action is String &&
        action.startsWith('actions/setup-java@') &&
        options is YamlMap &&
        options['java-version'] == '21') {
      return true;
    }
  }
  return false;
}

bool _orderedEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _setEquals<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

String? _read(File file, List<String> failures) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    failures.add('Missing or unsafe ${file.path}.');
    return null;
  }
  return file.readAsStringSync();
}
