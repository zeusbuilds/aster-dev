import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../support/bounded_test_process.dart';

void main() {
  final workflow = loadYaml(
    File('.github/workflows/platform.yml').readAsStringSync(),
  ) as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;
  final android = jobs['android-debug'] as YamlMap;
  final steps = (android['steps'] as YamlList).cast<YamlMap>();
  final provision = steps.singleWhere(
    (step) => step['name'] == 'Provision pinned Android NDK',
  );
  final script = provision['run'] as String;

  test('NDK provisioning precedes one-shot compile and host tests', () {
    expect(provision['shell'], 'bash');
    final compile = steps.singleWhere(
      (step) => step['name'] == 'Compile Android host integration',
    );
    final tests = steps.singleWhere(
      (step) => step['name'] == 'Run Android host tests',
    );
    expect(
      steps.toList().indexOf(provision),
      lessThan(steps.toList().indexOf(compile)),
    );
    expect(
      steps.toList().indexOf(compile),
      lessThan(steps.toList().indexOf(tests)),
    );
    expect(compile['run'], 'flutter build apk --debug --no-pub');
    expect(tests['run'], './gradlew :app:testDebugUnitTest --no-daemon');
    expect(tests['working-directory'], 'android');
    expect(compile.containsKey('continue-on-error'), isFalse);
    expect(tests.containsKey('continue-on-error'), isFalse);
  });

  for (final (scenario, expectedCode, calls) in [
    ('cached', 0, 0),
    ('transient', 0, 2),
    ('wrong-version', 1, 3),
    ('broken-compiler', 1, 3),
    ('exhausted', 1, 3),
    ('missing-manager', 1, 0),
  ]) {
    test('actual NDK workflow shell handles $scenario offline', () async {
      final root = Directory.systemTemp.createTempSync('aster-ci-ndk-');
      addTearDown(() => root.deleteSync(recursive: true));
      final sdk = '${root.path}/sdk';
      Directory('$sdk/cmdline-tools/latest/bin').createSync(recursive: true);
      Directory('${root.path}/bin').createSync();
      final ndk = '$sdk/ndk/28.2.13676358';
      Future<void> executable(String path, String content) async {
        final file = File(path)..writeAsStringSync(content);
        await makeTestExecutable(file);
      }

      await executable('${root.path}/bin/sleep', '#!/bin/sh\nexit 0\n');
      if (scenario != 'missing-manager') {
        await executable(
          '$sdk/cmdline-tools/latest/bin/sdkmanager',
          r'''#!/bin/sh
printf '%s\n' "$*" >> "$FIXTURE_ROOT/calls"
count=$(wc -l < "$FIXTURE_ROOT/calls" | tr -d ' ')
if [ "$SCENARIO" = transient ] && [ "$count" = 1 ]; then exit 1; fi
if [ "$SCENARIO" = exhausted ]; then exit 1; fi
ndk="$ANDROID_SDK_ROOT/ndk/28.2.13676358"
mkdir -p "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
version=28.2.13676358
if [ "$SCENARIO" = wrong-version ]; then version=99.0.0; fi
printf 'Pkg.Revision = %s\n' "$version" > "$ndk/source.properties"
status=0
if [ "$SCENARIO" = broken-compiler ]; then status=1; fi
printf '#!/bin/sh\nexit %s\n' "$status" > "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
chmod 700 "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
''',
        );
      }
      if (scenario == 'cached') {
        Directory('$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin')
            .createSync(recursive: true);
        File('$ndk/source.properties')
            .writeAsStringSync('Pkg.Revision = 28.2.13676358\n');
        await executable(
          '$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/clang',
          '#!/bin/sh\nexit 0\n',
        );
      }
      final result = await runTestProcess(
        '/bin/bash',
        ['--noprofile', '--norc', '-p', '-c', script],
        workingDirectory: root.path,
        environment: {
          ...Platform.environment,
          'FIXTURE_ROOT': root.path,
          'SCENARIO': scenario,
          'ANDROID_SDK_ROOT': sdk,
          'PATH': '${root.path}/bin:${Platform.environment['PATH'] ?? ''}',
        },
        timeout: const Duration(seconds: 8),
        maxStdoutBytes: 8192,
        maxStderrBytes: 8192,
      );
      expect(
        result.exitCode,
        expectedCode,
        reason: '${result.stdout}\n${result.stderr}',
      );
      final log = File('${root.path}/calls');
      final requests = log.existsSync() ? log.readAsLinesSync() : <String>[];
      expect(requests, hasLength(calls));
      expect(
        requests.every(
          (line) => line == '--install ndk;28.2.13676358 --channel=0',
        ),
        isTrue,
      );
    });
  }
}
