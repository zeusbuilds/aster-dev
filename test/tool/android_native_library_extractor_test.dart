import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File zipWriter;

  setUp(() {
    root = Directory.systemTemp.createTempSync('utexo_native_archive_');
    zipWriter = File('${root.path}/ZipFixtureWriter.java');
    zipWriter.writeAsStringSync(r'''
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public final class ZipFixtureWriter {
  public static void main(String[] arguments) throws Exception {
    try (ZipOutputStream output =
        new ZipOutputStream(new FileOutputStream(arguments[0]))) {
      for (int index = 1; index < arguments.length; index++) {
        output.putNextEntry(new ZipEntry(arguments[index]));
        output.write("fixture".getBytes(StandardCharsets.UTF_8));
        output.closeEntry();
      }
    }
  }
}
''');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  ProcessResult extract(File archive, Directory output) {
    return Process.runSync('java', [
      'scripts/AndroidNativeLibraryExtractor.java',
      archive.path,
      'base/lib',
      output.path,
      'arm64-v8a',
    ], workingDirectory: Directory.current.path);
  }

  test('extracts a complete exact native-library matrix', () {
    final archive = _createArchive(root, zipWriter, 'valid.aab', <String>[
      ..._requiredLibraries,
      'base/lib/arm64-v8a/libplugin_fixture.so',
    ]);
    final output = Directory('${root.path}/valid-output')..createSync();

    final result = extract(archive, output);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', contains('EXTRACTED_NATIVE_LIBRARIES=4'));
    expect(
      File('${output.path}/arm64-v8a/librgb_lightning_node.so')
          .readAsStringSync(),
      'fixture',
    );
  });

  test('rejects traversal-shaped archive paths without writing output', () {
    final archive = _createArchive(root, zipWriter, 'traversal.aab', <String>[
      ..._requiredLibraries,
      'base/lib/../../outside.so',
    ]);
    final output = Directory('${root.path}/traversal-output')..createSync();

    final result = extract(archive, output);

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('unsafe path'));
    expect(output.listSync(), isEmpty);
    expect(File('${root.path}/outside.so').existsSync(), isFalse);
  });

  test('rejects nested native-library paths', () {
    final archive = _createArchive(root, zipWriter, 'nested.aab', <String>[
      ..._requiredLibraries,
      'base/lib/arm64-v8a/nested/libplugin.so',
    ]);
    final output = Directory('${root.path}/nested-output')..createSync();

    final result = extract(archive, output);

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('malformed native-library path'));
    expect(output.listSync(), isEmpty);
  });

  test('rejects a missing required runtime library', () {
    final archive = _createArchive(root, zipWriter, 'missing.aab', <String>[
      'base/lib/arm64-v8a/libapp.so',
      'base/lib/arm64-v8a/libflutter.so',
    ]);
    final output = Directory('${root.path}/missing-output')..createSync();

    final result = extract(archive, output);

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('missing required libraries'));
    expect(output.listSync(), isEmpty);
  });

  test('rejects an ABI outside the exact expected set', () {
    final archive = _createArchive(root, zipWriter, 'foreign.aab', <String>[
      ..._requiredLibraries,
      'base/lib/x86_64/libapp.so',
    ]);
    final output = Directory('${root.path}/foreign-output')..createSync();

    final result = extract(archive, output);

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('unexpected native ABI x86_64'));
    expect(output.listSync(), isEmpty);
  });
}

const _requiredLibraries = <String>[
  'base/lib/arm64-v8a/libapp.so',
  'base/lib/arm64-v8a/libflutter.so',
  'base/lib/arm64-v8a/librgb_lightning_node.so',
];

File _createArchive(
  Directory root,
  File zipWriter,
  String name,
  List<String> entries,
) {
  final archive = File('${root.path}/$name');
  final result = Process.runSync('java', [
    zipWriter.path,
    archive.path,
    ...entries,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'fixture ZIP creation failed (${result.exitCode}):\n'
      '${result.stdout}\n${result.stderr}',
    );
  }
  return archive;
}
