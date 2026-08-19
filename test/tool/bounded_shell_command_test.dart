import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('utexo_bounded_shell_');
    for (final relativePath in <String>[
      'scripts/bounded-command.sh',
      'tool/run_bounded_command.dart',
      'tool/bounded_process.dart',
    ]) {
      final target = File('${fixture.path}/$relativePath');
      target.parent.createSync(recursive: true);
      File('${Directory.current.path}/$relativePath').copySync(target.path);
    }
    linkTestDartRuntime(fixture);
  });

  tearDown(() {
    fixture.deleteSync(recursive: true);
  });

  Future<BoundedProcessResult> runSource(
    String body, {
    Map<String, String>? environment,
  }) {
    return runTestProcess(
      '/bin/bash',
      <String>['--noprofile', '--norc', '-p', '-c', body],
      workingDirectory: fixture.path,
      environment: <String, String>{...Platform.environment, ...?environment},
      timeout: const Duration(seconds: 8),
      maxStdoutBytes: 8192,
      maxStderrBytes: 8192,
    );
  }

  Directory createFlutterRoot(
    String name, {
    String? version,
    String? metadata,
  }) {
    final root = Directory('${fixture.path}/$name')..createSync();
    if (version != null || metadata != null) {
      File('${root.path}/bin/cache/flutter.version.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          metadata ?? '{\n  "frameworkVersion": "$version",\n}\n',
        );
    }
    final dart = Link('${root.path}/bin/cache/dart-sdk/bin/dart');
    dart.parent.createSync(recursive: true);
    dart.createSync(testDartExecutable());
    return root;
  }

  void removeLocalFlutterRuntime() {
    Directory('${fixture.path}/.fvm').deleteSync(recursive: true);
  }

  test('reinitializes instead of trusting an inherited guard', () async {
    final result = await runSource(
      r'''
source scripts/bounded-command.sh
utexo_bounded_capture 2 8 8 -- /bin/sh -c "printf 123456789"
''',
      environment: const <String, String>{
        'UTEXO_BOUNDED_COMMAND_LOADED': 'inherited-bypass',
      },
    );

    expect(result.exitCode, 125);
    expect(result.stderr, contains('stdout byte ceiling'));
  });

  test('allows repeated sourcing only after local initialization', () async {
    final result = await runSource(r'''
source scripts/bounded-command.sh
source scripts/bounded-command.sh
utexo_capture_quick /bin/sh -c "printf ready"
''');

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, 'ready');
  });

  test('uses an exact pinned absolute FLUTTER_ROOT in CI', () async {
    final flutterRoot = createFlutterRoot('ci-flutter', version: '3.47.0');
    removeLocalFlutterRuntime();

    final result = await runSource(
      r'''
source scripts/bounded-command.sh
utexo_capture_quick /bin/sh -c "printf ci-ready"
''',
      environment: <String, String>{'FLUTTER_ROOT': flutterRoot.path},
    );

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, 'ci-ready');
  });

  test('rejects a mismatched FLUTTER_ROOT version', () async {
    final flutterRoot = createFlutterRoot('wrong-flutter', version: '3.46.0');
    removeLocalFlutterRuntime();

    final result = await runSource(
      'source scripts/bounded-command.sh\n'
      'utexo_capture_quick /bin/sh -c "printf unreachable"\n',
      environment: <String, String>{'FLUTTER_ROOT': flutterRoot.path},
    );

    expect(result.exitCode, 69);
    expect(result.stdout, isEmpty);
  });

  test('rejects FLUTTER_ROOT without version metadata', () async {
    final flutterRoot = createFlutterRoot('missing-metadata');
    removeLocalFlutterRuntime();

    final result = await runSource(
      'source scripts/bounded-command.sh\n'
      'utexo_capture_quick /bin/sh -c "printf unreachable"\n',
      environment: <String, String>{'FLUTTER_ROOT': flutterRoot.path},
    );

    expect(result.exitCode, 69);
    expect(result.stdout, isEmpty);
  });

  test('rejects malformed FLUTTER_ROOT version metadata', () async {
    final flutterRoot = createFlutterRoot(
      'malformed-metadata',
      metadata: '{"frameworkVersion": 3.47}\n',
    );
    removeLocalFlutterRuntime();

    final result = await runSource(
      'source scripts/bounded-command.sh\n'
      'utexo_capture_quick /bin/sh -c "printf unreachable"\n',
      environment: <String, String>{'FLUTTER_ROOT': flutterRoot.path},
    );

    expect(result.exitCode, 69);
    expect(result.stdout, isEmpty);
  });

  test('rejects duplicate FLUTTER_ROOT version metadata', () async {
    final flutterRoot = createFlutterRoot(
      'duplicate-metadata',
      metadata:
          '{\n'
          '  "frameworkVersion": "3.47.0",\n'
          '  "frameworkVersion": "3.47.0",\n'
          '}\n',
    );
    removeLocalFlutterRuntime();

    final result = await runSource(
      'source scripts/bounded-command.sh\n'
      'utexo_capture_quick /bin/sh -c "printf unreachable"\n',
      environment: <String, String>{'FLUTTER_ROOT': flutterRoot.path},
    );

    expect(result.exitCode, 69);
    expect(result.stdout, isEmpty);
  });

  test('rejects a relative FLUTTER_ROOT', () async {
    createFlutterRoot('relative-flutter', version: '3.47.0');
    removeLocalFlutterRuntime();

    final result = await runSource(
      'source scripts/bounded-command.sh\n'
      'utexo_capture_quick /bin/sh -c "printf unreachable"\n',
      environment: const <String, String>{'FLUTTER_ROOT': 'relative-flutter'},
    );

    expect(result.exitCode, 69);
    expect(result.stdout, isEmpty);
  });

  test('prefers repository FVM over a mismatched FLUTTER_ROOT', () async {
    final flutterRoot = createFlutterRoot('ignored-flutter', version: '3.46.0');

    final result = await runSource(
      r'''
source scripts/bounded-command.sh
utexo_capture_quick /bin/sh -c "printf local-ready"
''',
      environment: <String, String>{'FLUTTER_ROOT': flutterRoot.path},
    );

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, 'local-ready');
  });

  test('rejects direct execution of the source-only boundary', () async {
    final result = await runTestProcess(
      '/bin/bash',
      <String>['scripts/bounded-command.sh'],
      workingDirectory: fixture.path,
      timeout: const Duration(seconds: 5),
      maxStdoutBytes: 4096,
      maxStderrBytes: 4096,
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('must be sourced'));
  });
}
