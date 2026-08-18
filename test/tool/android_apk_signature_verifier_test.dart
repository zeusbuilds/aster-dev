import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory bin;

  setUp(() {
    root = Directory.systemTemp.createTempSync('utexo_apk_signature_');
    bin = Directory('${root.path}/bin')..createSync();
    final apksigner = File('${bin.path}/apksigner');
    _writeExecutable(apksigner, '#!/bin/sh\nexit 1\n');
    _writeExecutable(File('${bin.path}/fvm'), '''#!/bin/sh
printf '\n'
printf 'UTEXO_AGP_VERSION=9.1.0\n'
printf 'UTEXO_BUILD_TOOLS_VERSION=36.0.0\n'
printf 'UTEXO_NDK_VERSION=28.2.13676358\n'
printf 'UTEXO_AAPT2_PROTO_VERSION=9.1.0\n'
printf 'UTEXO_BUNDLETOOL_VERSION=1.18.3\n'
printf 'UTEXO_PROTOBUF_VERSION=3.25.5\n'
printf 'UTEXO_AAPT2_PROTO_JAR=/dev/null\n'
printf 'UTEXO_BUNDLETOOL_JAR=/dev/null\n'
printf 'UTEXO_PROTOBUF_JAR=/dev/null\n'
printf 'UTEXO_APKSIGNER=${apksigner.path}\n'
printf 'UTEXO_AAPT2=/dev/null\n'
printf 'UTEXO_ZIPALIGN=/dev/null\n'
printf 'UTEXO_LLVM_READELF=/dev/null\n'
''');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  ProcessResult verify(File archive) {
    return Process.runSync(
      'bash',
      ['scripts/verify-android-apk-signature.sh', archive.path],
      workingDirectory: Directory.current.path,
      environment: {
        ...Platform.environment,
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );
  }

  test('accepts an honestly unsigned candidate', () {
    final archive = _createArchive(root, 'unsigned.apk');

    final result = verify(archive);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('unsigned candidate artifact'));
  });

  test('rejects case-varied v1 signature remnants', () {
    final archive = _createArchive(
      root,
      'remnant.apk',
      signatureEntry: 'META-INF/fixture.sf',
    );

    final result = verify(archive);

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('contains an invalid APK signature'));
  });

  test('rejects control characters in archive entry names', () {
    final archive = _createArchive(
      root,
      'control.apk',
      signatureEntry: 'META-INF/fixture.sf\nforged-entry',
    );

    final result = verify(archive);

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('could not inspect'));
    expect('${result.stderr}', contains('control character'));
  });
}

File _createArchive(Directory root, String name, {String? signatureEntry}) {
  final content = Directory('${root.path}/$name-content')..createSync();
  File('${content.path}/payload.txt').writeAsStringSync('payload');
  if (signatureEntry != null) {
    final signature = File('${content.path}/$signatureEntry');
    signature.createSync(recursive: true);
    signature.writeAsStringSync('corrupt signature metadata');
  }
  final archive = File('${root.path}/$name');
  _runRequired('jar', [
    '--create',
    '--file',
    archive.path,
    '-C',
    content.path,
    '.',
  ]);
  return archive;
}

void _writeExecutable(File file, String contents) {
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  _runRequired('chmod', ['755', file.path]);
}

ProcessResult _runRequired(String executable, List<String> arguments) {
  final result = Process.runSync(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError(
      '$executable failed (${result.exitCode}):\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return result;
}
