import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory root;
  late Directory bin;
  late File archive;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('utexo_elf_policy_');
    bin = Directory('${root.path}/bin')..createSync();
    for (final relativePath in <String>[
      'scripts/verify-android-native-libraries.sh',
      'scripts/android-artifact-toolchain.sh',
      'scripts/bounded-command.sh',
      'scripts/AndroidNativeLibraryExtractor.java',
      'tool/run_bounded_command.dart',
      'tool/bounded_process.dart',
    ]) {
      final target = File('${root.path}/$relativePath');
      target.parent.createSync(recursive: true);
      File('${Directory.current.path}/$relativePath').copySync(target.path);
    }
    linkTestDartRuntime(root);
    final readelf = File('${bin.path}/llvm-readelf');
    await _writeExecutable(readelf, '''#!/bin/sh
if [ "\$1" = "-lW" ]; then
  printf '  LOAD 0x000000 %s 0x000000 0x000001 0x000001 R E %s\n' "\${FAKE_VIRTUAL_ADDRESS}" "\${FAKE_ALIGNMENT}"
  printf '  GNU_RELRO 0x000000 0x000000 0x000000 0x000000 0x000000 R 0x1\n'
  exit 0
fi
exit 97
''');
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
    'UTEXO_APKSIGNER=/dev/null',
    'UTEXO_AAPT2=/dev/null',
    'UTEXO_ZIPALIGN=/dev/null',
    'UTEXO_LLVM_READELF=${readelf.path}',
  ];
  for (final value in fixed) {
    print(value);
  }
}
''');
    await _writeExecutable(File('${bin.path}/find'), r'''#!/bin/sh
if [ "${FAKE_FIND_PARTIAL:-}" = "1" ]; then
  case " $* " in
    *" -mindepth "*)
      /usr/bin/find "$@" | /usr/bin/head -n 1
      exit 42
      ;;
  esac
fi
exec /usr/bin/find "$@"
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
    await _runRequired('jar', [
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

  Future<BoundedProcessResult> verify({
    required String alignment,
    required String virtualAddress,
    bool failEnumeration = false,
  }) {
    return runTestProcess(
      'bash',
      [
        '${root.path}/scripts/verify-android-native-libraries.sh',
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
        if (failEnumeration) 'FAKE_FIND_PARTIAL': '1',
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );
  }

  test('accepts a congruent power-of-two 16 KiB LOAD alignment', () async {
    final result = await verify(
      alignment: '0x4000',
      virtualAddress: '0x000000',
    );

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, contains('compatible ELF alignment'));
  });

  test('rejects an above-minimum non-power-of-two alignment', () async {
    final result = await verify(
      alignment: '0x5000',
      virtualAddress: '0x000000',
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('non-power-of-two LOAD alignment'));
  });

  test('rejects incongruent LOAD file and virtual addresses', () async {
    final result = await verify(
      alignment: '0x4000',
      virtualAddress: '0x000001',
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('incongruent LOAD offset/address'));
  });

  test('rejects a partial native-library enumeration', () async {
    final result = await verify(
      alignment: '0x4000',
      virtualAddress: '0x000000',
      failEnumeration: true,
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('could not enumerate every extracted'));
  });
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
