import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync(
      'aster_android_toolchain_script_',
    );
    Directory('${fixture.path}/scripts').createSync();
    Directory('${fixture.path}/tool').createSync();
    File('${Directory.current.path}/scripts/android-artifact-toolchain.sh')
        .copySync('${fixture.path}/scripts/android-artifact-toolchain.sh');
    File('${Directory.current.path}/scripts/bounded-command.sh')
        .copySync('${fixture.path}/scripts/bounded-command.sh');
    File('${Directory.current.path}/tool/run_bounded_command.dart')
        .copySync('${fixture.path}/tool/run_bounded_command.dart');
    File('${Directory.current.path}/tool/bounded_process.dart')
        .copySync('${fixture.path}/tool/bounded_process.dart');
    linkTestDartRuntime(fixture);
    File('${fixture.path}/tool/resolve_android_artifact_toolchain.dart')
        .writeAsStringSync(r'''
void main() {
  const values = <String>[
    'ASTER_AGP_VERSION=resolved-agp',
    'ASTER_BUILD_TOOLS_VERSION=resolved-build-tools',
    'ASTER_NDK_VERSION=resolved-ndk',
    'ASTER_AAPT2_PROTO_VERSION=resolved-aapt-schema',
    'ASTER_BUNDLETOOL_VERSION=resolved-bundletool-version',
    'ASTER_PROTOBUF_VERSION=resolved-protobuf-version',
    'ASTER_AAPT2_PROTO_JAR=/resolved/aapt-schema.jar',
    'ASTER_BUNDLETOOL_JAR=/resolved/bundletool.jar',
    'ASTER_PROTOBUF_JAR=/resolved/protobuf.jar',
    'ASTER_APKSIGNER=/resolved/apksigner',
    'ASTER_AAPT2=/resolved/aapt2',
    'ASTER_ZIPALIGN=/resolved/zipalign',
    'ASTER_LLVM_READELF=/resolved/llvm-readelf',
  ];
  for (final value in values) {
    print(value);
  }
}
''');
  });

  tearDown(() {
    fixture.deleteSync(recursive: true);
  });

  test('replaces inherited paths with the exact resolved toolchain', () async {
    final environment = Map<String, String>.of(Platform.environment)
      ..addAll({
        'ASTER_AAPT2_PROTO_JAR': '/inherited/aapt-schema.jar',
        'ASTER_BUNDLETOOL_JAR': '/inherited/bundletool.jar',
        'ASTER_PROTOBUF_JAR': '/inherited/protobuf.jar',
        'ASTER_APKSIGNER': '/inherited/apksigner',
        'ASTER_AAPT2': '/inherited/aapt2',
        'ASTER_ZIPALIGN': '/inherited/zipalign',
        'ASTER_LLVM_READELF': '/inherited/llvm-readelf',
      });
    const resolveCommand = r'''
source scripts/android-artifact-toolchain.sh
aster_resolve_android_artifact_toolchain
printf '%s\n' "$ASTER_AAPT2_PROTO_JAR" "$ASTER_BUNDLETOOL_JAR" \
  "$ASTER_PROTOBUF_JAR" "$ASTER_APKSIGNER" "$ASTER_AAPT2" \
  "$ASTER_ZIPALIGN" "$ASTER_LLVM_READELF"
''';
    final result = await runTestProcess(
      'bash',
      ['-c', resolveCommand],
      workingDirectory: fixture.path,
      environment: environment,
    );

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout.trim().split('\n'), [
      '/resolved/aapt-schema.jar',
      '/resolved/bundletool.jar',
      '/resolved/protobuf.jar',
      '/resolved/apksigner',
      '/resolved/aapt2',
      '/resolved/zipalign',
      '/resolved/llvm-readelf',
    ]);
  });
}
