import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../support/bounded_test_process.dart';

const _sdk = '/usr/local/lib/android/sdk';
const _defaultNdk = '$_sdk/ndk/27.3.13750724';
const _pinnedNdk = '$_sdk/ndk/28.2.13676358';
const _unusedNdks = ['$_sdk/ndk/29.0.14206865', '$_sdk/ndk/30.0.16248370'];

void main() {
  final workflow = loadYaml(
    File('.github/workflows/platform.yml').readAsStringSync(),
  ) as YamlMap;
  final job = (workflow['jobs'] as YamlMap)['android-debug'] as YamlMap;
  final steps = (job['steps'] as YamlList).cast<YamlMap>().toList();
  final cleanup = steps.singleWhere(
    (step) => step['name'] == 'Reclaim unused hosted Android NDKs',
  );
  final capacity = steps.singleWhere(
    (step) => step['name'] == 'Verify Android compile disk headroom',
  );

  test(
    'platform jobs verify isolated supervisor runtime before generation',
    () {
      for (final platformJob
          in (workflow['jobs'] as YamlMap).values.cast<YamlMap>()) {
        final platformSteps = (platformJob['steps'] as YamlList)
            .cast<YamlMap>()
            .toList();
        final runtime = platformSteps.singleWhere(
          (step) => step['name'] == 'Verify process supervisor runtime',
        );
        expect(
          runtime['run'],
          "python3 -I -S -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 69)'",
        );
        expect(
          platformSteps.indexOf(runtime),
          lessThan(
            platformSteps.indexWhere(
              (step) => step['name'] == 'Generate sources',
            ),
          ),
        );
        expect(runtime.containsKey('continue-on-error'), isFalse);
      }
    },
  );

  test(
    'capacity reclamation precedes setup and final check precedes compile',
    () {
      expect(cleanup['shell'], 'bash');
      expect(capacity['shell'], 'bash');
      final setup = steps.indexWhere((step) => step['name'] == 'Setup Java');
      final compile = steps.indexWhere(
        (step) => step['name'] == 'Compile Android host integration',
      );
      expect(steps.indexOf(cleanup), lessThan(setup));
      expect(steps.indexOf(capacity), compile - 1);
      expect(
        steps.indexWhere(
          (step) => step['name'] == 'Provision pinned Android NDK',
        ),
        lessThan(steps.indexOf(capacity)),
      );
      expect(cleanup.containsKey('continue-on-error'), isFalse);
      expect(capacity.containsKey('continue-on-error'), isFalse);
    },
  );

  for (final (scenario, expectedCode, cleanupCalls, diskCalls) in [
    ('normal', 0, 1, 2),
    ('missing-paths', 0, 1, 2),
    ('wrong-host', 1, 0, 0),
    ('wrong-os', 1, 0, 0),
    ('wrong-root', 1, 0, 0),
    ('root-symlink', 1, 0, 0),
    ('parent-symlink', 1, 0, 0),
    ('ndk-symlink', 1, 0, 0),
    ('active-normalized', 1, 0, 0),
    ('active-symlink', 1, 0, 0),
    ('cleanup-failure', 23, 1, 2),
    ('disk-failure', 31, 0, 1),
  ]) {
    test('actual runner cleanup shell handles $scenario safely', () async {
      final fixture = await _Fixture.create(scenario);
      addTearDown(fixture.dispose);
      final result = await fixture.run(cleanup['run'] as String);
      expect(
        result.exitCode,
        expectedCode,
        reason: '${result.stdout}\n${result.stderr}',
      );
      final removals = fixture.calls('rm');
      expect(removals, hasLength(cleanupCalls));
      for (final arguments in removals) {
        expect(arguments, ['-rf', '--', ..._unusedNdks]);
      }
      expect(fixture.calls('sudo'), hasLength(cleanupCalls));
      expect(fixture.calls('df'), hasLength(diskCalls));
      if (expectedCode == 0) {
        expect(fixture.path(_defaultNdk).existsSync(), isTrue);
        expect(fixture.path(_pinnedNdk).existsSync(), isTrue);
        for (final ndk in _unusedNdks) {
          expect(fixture.path(ndk).existsSync(), isFalse);
        }
        expect(result.stdout, contains('before allowlisted'));
        expect(result.stdout, contains('after allowlisted'));
      } else if (scenario == 'cleanup-failure') {
        expect(fixture.path(_unusedNdks.first).existsSync(), isTrue);
        expect(result.stdout, contains('after allowlisted'));
      }
    });
  }

  for (final (scenario, available, expectedCode) in [
    ('exact-floor', '12582912', 0),
    ('below-floor', '12582911', 1),
    ('invalid-capacity', 'unavailable', 1),
    ('disk-failure', '16777216', 31),
  ]) {
    test('actual precompile disk shell handles $scenario', () async {
      final fixture = await _Fixture.create(scenario, available: available);
      addTearDown(fixture.dispose);
      final result = await fixture.run(capacity['run'] as String);
      expect(
        result.exitCode,
        expectedCode,
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(fixture.calls('df'), hasLength(1));
      expect(fixture.calls('rm'), isEmpty);
      expect(fixture.calls('sudo'), isEmpty);
      if (scenario == 'exact-floor') {
        expect(result.stdout, contains('12884901888'));
      } else if (scenario == 'below-floor') {
        expect(result.stderr, contains('At least 12 GiB'));
      }
    });
  }
}

final class _Fixture {
  _Fixture(this.root, this.scenario, this.available);

  final Directory root;
  final String scenario;
  final String available;

  static Future<_Fixture> create(
    String scenario, {
    String available = '16777216',
  }) async {
    final temporary = Directory.systemTemp.createTempSync('aster-ci-capacity-');
    final fixture = _Fixture(
      Directory(temporary.resolveSymbolicLinksSync()),
      scenario,
      available,
    );
    Directory('${fixture.root.path}/bin').createSync();
    for (final ndk in [_defaultNdk, _pinnedNdk, ..._unusedNdks]) {
      if (scenario == 'missing-paths' && _unusedNdks.contains(ndk)) continue;
      fixture.path(ndk).createSync(recursive: true);
    }
    if (scenario == 'root-symlink') {
      fixture.path(_sdk).renameSync('${fixture.root.path}/alternate');
      Link(fixture.path(_sdk).path)
          .createSync('${fixture.root.path}/alternate');
    } else if (scenario == 'parent-symlink') {
      fixture.path('$_sdk/ndk').renameSync('${fixture.root.path}/alternate');
      Link(fixture.path('$_sdk/ndk').path)
          .createSync('${fixture.root.path}/alternate');
    } else if (scenario == 'ndk-symlink') {
      fixture.path(_unusedNdks.last).deleteSync();
      Link(fixture.path(_unusedNdks.last).path)
          .createSync(fixture.path(_defaultNdk).path);
    } else if (scenario == 'active-symlink') {
      Link('${fixture.root.path}/virtual/default-ndk')
          .createSync(fixture.path(_unusedNdks.first).path);
    }
    final fake = File('${fixture.root.path}/bin/fake-tool')
      ..writeAsStringSync(_fakeTool);
    await makeTestExecutable(fake);
    for (final tool in ['df', 'realpath', 'stat', 'sudo', 'rm']) {
      Link('${fixture.root.path}/bin/$tool').createSync(fake.path);
    }
    return fixture;
  }

  Directory path(String virtualPath) =>
      Directory('${root.path}/virtual$virtualPath');

  List<List<String>> calls(String tool) {
    final log = File('${root.path}/calls.jsonl');
    if (!log.existsSync()) return [];
    return log
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as List<dynamic>)
        .where((entry) => entry.first == tool)
        .map((entry) => entry.skip(1).cast<String>().toList())
        .toList();
  }

  Future<BoundedProcessResult> run(String script) => runTestProcess(
    '/bin/bash',
    ['--noprofile', '--norc', '-p', '-c', script],
    workingDirectory: root.path,
    environment: {
      ...Platform.environment,
      'FIXTURE_ROOT': root.path,
      'SCENARIO': scenario,
      'AVAILABLE_KIB': available,
      'RUNNER_ENVIRONMENT': scenario == 'wrong-host'
          ? 'self-hosted'
          : 'github-hosted',
      'RUNNER_OS': scenario == 'wrong-os' ? 'macOS' : 'Linux',
      'ANDROID_SDK_ROOT': scenario == 'wrong-root' ? '/unexpected/sdk' : _sdk,
      'ANDROID_NDK': _defaultNdk,
      'ANDROID_NDK_HOME': _defaultNdk,
      'ANDROID_NDK_ROOT': switch (scenario) {
        'active-normalized' => '${_unusedNdks.first}/../29.0.14206865/',
        'active-symlink' => '/default-ndk',
        _ => _defaultNdk,
      },
      'GITHUB_WORKSPACE': root.path,
      'PATH': '${root.path}/bin:${Platform.environment['PATH'] ?? ''}',
    },
    timeout: const Duration(seconds: 10),
    maxStdoutBytes: 8192,
    maxStderrBytes: 8192,
  );

  void dispose() => root.deleteSync(recursive: true);
}

// Only these fixture-owned tools can reach deletion. The actual workflow shell
// stays unmodified; every virtual system path resolves under this temporary tree.
const _fakeTool = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
root = pathlib.Path(os.environ['FIXTURE_ROOT'])
virtual = root / 'virtual'
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps([tool, *args]) + '\n')
def fixture_path(value):
    assert value.startswith('/')
    return virtual / value.lstrip('/')
if tool == 'realpath':
    assert args[:2] in (['-e', '--'], ['-m', '--']) and len(args) == 3
    resolved = fixture_path(args[2]).resolve(strict=args[0] == '-e')
    print('/' + str(resolved.relative_to(virtual)) if resolved.is_relative_to(virtual) else resolved)
elif tool == 'stat':
    assert args[:3] == ['-c', '%F', '--'] and len(args) == 4
    print('directory' if fixture_path(args[3]).is_dir() else 'regular file')
elif tool == 'df':
    assert args == ['-Pk', '--', str(root)]
    if os.environ['SCENARIO'] == 'disk-failure': sys.exit(31)
    print('Filesystem 1024-blocks Used Available Capacity Mounted on')
    print('fixture 99999999 0 ' + os.environ['AVAILABLE_KIB'] + ' 1% /')
elif tool == 'sudo':
    assert args == ['rm', '-rf', '--', '/usr/local/lib/android/sdk/ndk/29.0.14206865', '/usr/local/lib/android/sdk/ndk/30.0.16248370']
    os.execvp('rm', args)
elif tool == 'rm':
    assert args == ['-rf', '--', '/usr/local/lib/android/sdk/ndk/29.0.14206865', '/usr/local/lib/android/sdk/ndk/30.0.16248370']
    if os.environ['SCENARIO'] == 'cleanup-failure': sys.exit(23)
    for target in args[2:]:
        path = fixture_path(target)
        assert path.is_relative_to(virtual)
        if path.is_symlink(): path.unlink()
        elif path.exists(): shutil.rmtree(path)
else:
    sys.exit(99)
''';
