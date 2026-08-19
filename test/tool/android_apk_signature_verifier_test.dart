import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory root;
  late Directory bin;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('utexo_apk_signature_');
    bin = Directory('${root.path}/bin')..createSync();
    for (final relativePath in <String>[
      'scripts/verify-android-apk-signature.sh',
      'scripts/android-artifact-toolchain.sh',
      'scripts/bounded-command.sh',
      'scripts/AndroidJarSignatureInspector.java',
      'tool/run_bounded_command.dart',
      'tool/bounded_process.dart',
    ]) {
      final target = File('${root.path}/$relativePath');
      target.parent.createSync(recursive: true);
      File('${Directory.current.path}/$relativePath').copySync(target.path);
    }
    linkTestDartRuntime(root);
    final apksigner = File('${bin.path}/apksigner');
    await _writeExecutable(apksigner, '#!/bin/sh\nexit 1\n');
    File('${root.path}/tool/resolve_android_artifact_toolchain.dart')
        .writeAsStringSync('''
void main() {
  const fixed = <String>[
    'UTEXO_AGP_VERSION=9.1.0',
    'UTEXO_BUILD_TOOLS_VERSION=36.0.0',
    'UTEXO_NDK_VERSION=28.2.13676358',
    'UTEXO_AAPT2_PROTO_VERSION=9.1.0',
    'UTEXO_BUNDLETOOL_VERSION=1.18.3',
    'UTEXO_PROTOBUF_VERSION=3.25.5',
    'UTEXO_AAPT2_PROTO_JAR=/dev/null',
    'UTEXO_BUNDLETOOL_JAR=/dev/null',
    'UTEXO_PROTOBUF_JAR=/dev/null',
    'UTEXO_APKSIGNER=${apksigner.path}',
    'UTEXO_AAPT2=/dev/null',
    'UTEXO_ZIPALIGN=/dev/null',
    'UTEXO_LLVM_READELF=/dev/null',
  ];
  for (final value in fixed) {
    print(value);
  }
}
''');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  Future<BoundedProcessResult> verify(File archive) {
    return runTestProcess(
      'bash',
      ['${root.path}/scripts/verify-android-apk-signature.sh', archive.path],
      environment: {
        ...Platform.environment,
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );
  }

  test('accepts an honestly unsigned candidate', () async {
    final archive = await _createArchive(root, 'unsigned.apk');

    final result = await verify(archive);

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, contains('unsigned candidate artifact'));
  });

  test('rejects case-varied v1 signature remnants', () async {
    final archive = await _createArchive(
      root,
      'remnant.apk',
      signatureEntry: 'META-INF/fixture.sf',
    );

    final result = await verify(archive);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('contains an invalid APK signature'));
  });

  test('rejects control characters in archive entry names', () async {
    final archive = await _createArchive(
      root,
      'control.apk',
      signatureEntry: 'META-INF/fixture.sf\nforged-entry',
    );

    final result = await verify(archive);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('could not inspect'));
    expect(result.stderr, contains('control character'));
  });
}

Future<File> _createArchive(
  Directory root,
  String name, {
  String? signatureEntry,
}) async {
  final content = Directory('${root.path}/$name-content')..createSync();
  File('${content.path}/payload.txt').writeAsStringSync('payload');
  if (signatureEntry != null) {
    final signature = File('${content.path}/$signatureEntry');
    signature.createSync(recursive: true);
    signature.writeAsStringSync('corrupt signature metadata');
  }
  final archive = File('${root.path}/$name');
  await _runRequired('jar', [
    '--create',
    '--file',
    archive.path,
    '-C',
    content.path,
    '.',
  ]);
  return archive;
}

Future<void> _writeExecutable(File file, String contents) async {
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  await makeTestExecutable(file);
}

Future<BoundedProcessResult> _runRequired(
  String executable,
  List<String> arguments,
) async {
  final result = await runTestProcess(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError(
      '$executable failed (${result.exitCode}):\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return result;
}
