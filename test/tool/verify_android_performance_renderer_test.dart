import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  late File verifier;
  late File fakeAdb;

  setUp(() async {
    fixture = Directory.systemTemp.createTempSync(
      'utexo_android_performance_renderer_',
    );
    verifier = File(
      '${Directory.current.path}/scripts/'
      'verify-android-performance-renderer.sh',
    );
    fakeAdb = File('${fixture.path}/adb')
      ..writeAsStringSync('''
#!/usr/bin/env bash
set -euo pipefail
[[ "\$*" == "-s emulator-5554 shell dumpsys SurfaceFlinger" ]]
printf '%s\n' "\${UTEXO_TEST_SURFACE_FLINGER_OUTPUT:-}"
''');
    final chmod = await Process.run('chmod', ['755', fakeAdb.path]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
  });

  tearDown(() {
    fixture.deleteSync(recursive: true);
  });

  test('accepts and reports a hardware-backed renderer', () async {
    final result = await _verify(
      verifier,
      fakeAdb,
      'GLES: Google (Apple), Android Emulator OpenGL ES Translator '
      '(Apple M4 Pro), OpenGL ES 3.0',
    );

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      contains('Android Emulator OpenGL ES Translator (Apple M4 Pro)'),
    );
  });

  for (final renderer in <String>[
    'ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device))',
    'Mesa llvmpipe',
    'Mesa lavapipe',
    'Gallium softpipe',
    'Android software rasterizer',
  ]) {
    test('rejects software renderer $renderer', () async {
      final result = await _verify(verifier, fakeAdb, 'GLES: $renderer');

      expect(result.exitCode, 64);
      expect(result.stderr, contains('software rendering'));
    });
  }

  test('fails closed when SurfaceFlinger omits its renderer', () async {
    final result = await _verify(
      verifier,
      fakeAdb,
      'SurfaceFlinger diagnostics unavailable',
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('did not report a GLES renderer'));
  });
}

Future<ProcessResult> _verify(
  File verifier,
  File adb,
  String surfaceFlingerOutput,
) {
  return Process.run(
    'bash',
    [verifier.path, adb.path, 'emulator-5554'],
    environment: <String, String>{
      ...Platform.environment,
      'UTEXO_TEST_SURFACE_FLINGER_OUTPUT': surfaceFlingerOutput,
    },
  );
}
