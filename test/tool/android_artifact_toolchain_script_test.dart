import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync(
      'utexo_android_toolchain_script_',
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
    'UTEXO_AGP_VERSION=resolved-agp',
    'UTEXO_BUILD_TOOLS_VERSION=resolved-build-tools',
    'UTEXO_NDK_VERSION=resolved-ndk',
    'UTEXO_AAPT2_PROTO_VERSION=resolved-aapt-schema',
    'UTEXO_BUNDLETOOL_VERSION=resolved-bundletool-version',
    'UTEXO_PROTOBUF_VERSION=resolved-protobuf-version',
    'UTEXO_AAPT2_PROTO_JAR=/resolved/aapt-schema.jar',
    'UTEXO_BUNDLETOOL_JAR=/resolved/bundletool.jar',
    'UTEXO_PROTOBUF_JAR=/resolved/protobuf.jar',
    'UTEXO_APKSIGNER=/resolved/apksigner',
    'UTEXO_AAPT2=/resolved/aapt2',
    'UTEXO_ZIPALIGN=/resolved/zipalign',
    'UTEXO_LLVM_READELF=/resolved/llvm-readelf',
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
        'UTEXO_AAPT2_PROTO_JAR': '/inherited/aapt-schema.jar',
        'UTEXO_BUNDLETOOL_JAR': '/inherited/bundletool.jar',
        'UTEXO_PROTOBUF_JAR': '/inherited/protobuf.jar',
        'UTEXO_APKSIGNER': '/inherited/apksigner',
        'UTEXO_AAPT2': '/inherited/aapt2',
        'UTEXO_ZIPALIGN': '/inherited/zipalign',
        'UTEXO_LLVM_READELF': '/inherited/llvm-readelf',
      });
    const resolveCommand = r'''
source scripts/android-artifact-toolchain.sh
utexo_resolve_android_artifact_toolchain
printf '%s\n' "$UTEXO_AAPT2_PROTO_JAR" "$UTEXO_BUNDLETOOL_JAR" \
  "$UTEXO_PROTOBUF_JAR" "$UTEXO_APKSIGNER" "$UTEXO_AAPT2" \
  "$UTEXO_ZIPALIGN" "$UTEXO_LLVM_READELF"
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
