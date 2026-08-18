import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory bin;
  late File archive;

  setUp(() {
    root = Directory.systemTemp.createTempSync('utexo_elf_policy_');
    bin = Directory('${root.path}/bin')..createSync();
    final readelf = File('${bin.path}/llvm-readelf');
    _writeExecutable(readelf, '''#!/bin/sh
if [ "\$1" = "-lW" ]; then
  printf '  LOAD 0x000000 %s 0x000000 0x000001 0x000001 R E %s\n' "\${FAKE_VIRTUAL_ADDRESS}" "\${FAKE_ALIGNMENT}"
  printf '  GNU_RELRO 0x000000 0x000000 0x000000 0x000000 0x000000 R 0x1\n'
  exit 0
fi
exit 97
''');
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
printf 'UTEXO_APKSIGNER=/dev/null\n'
printf 'UTEXO_AAPT2=/dev/null\n'
printf 'UTEXO_ZIPALIGN=/dev/null\n'
printf 'UTEXO_LLVM_READELF=${readelf.path}\n'
''');
    for (final library in <String>[
      'libapp.so',
      'libflutter.so',
      'librgb_lightning_node.so',
    ]) {
      final content = File('${root.path}/content/base/lib/arm64-v8a/$library');
      content.createSync(recursive: true);
      content.writeAsBytesSync(const [0x7f, 0x45, 0x4c, 0x46]);
    }
    archive = File('${root.path}/fixture.aab');
    _runRequired('jar', [
      '--create',
      '--file',
      archive.path,
      '-C',
      '${root.path}/content',
      'base',
    ]);
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  ProcessResult verify({
    required String alignment,
    required String virtualAddress,
  }) {
    return Process.runSync(
      'bash',
      [
        'scripts/verify-android-native-libraries.sh',
        archive.path,
        'base/lib',
        'aab',
        'arm64-v8a',
      ],
      workingDirectory: Directory.current.path,
      environment: {
        ...Platform.environment,
        'FAKE_ALIGNMENT': alignment,
        'FAKE_VIRTUAL_ADDRESS': virtualAddress,
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );
  }

  test('accepts a congruent power-of-two 16 KiB LOAD alignment', () {
    final result = verify(alignment: '0x4000', virtualAddress: '0x000000');

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('compatible ELF alignment'));
  });

  test('rejects an above-minimum non-power-of-two alignment', () {
    final result = verify(alignment: '0x5000', virtualAddress: '0x000000');

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('non-power-of-two LOAD alignment'));
  });

  test('rejects incongruent LOAD file and virtual addresses', () {
    final result = verify(alignment: '0x4000', virtualAddress: '0x000001');

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('incongruent LOAD offset/address'));
  });
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
