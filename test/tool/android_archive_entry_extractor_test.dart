import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory root;
  late File zipWriter;

  setUp(() {
    root = Directory.systemTemp.createTempSync('aster_archive_entry_');
    zipWriter = File('${root.path}/ZipFixtureWriter.java');
    zipWriter.writeAsStringSync(r'''
import java.io.FileOutputStream;
import java.util.Arrays;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public final class ZipFixtureWriter {
  public static void main(String[] arguments) throws Exception {
    try (ZipOutputStream output =
        new ZipOutputStream(new FileOutputStream(arguments[0]))) {
      for (int index = 1; index < arguments.length; index++) {
        int separator = arguments[index].lastIndexOf(':');
        String name = arguments[index].substring(0, separator);
        int size = Integer.parseInt(arguments[index].substring(separator + 1));
        byte[] contents = new byte[size];
        Arrays.fill(contents, (byte) 'x');
        output.putNextEntry(new ZipEntry(name));
        output.write(contents);
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

  Future<BoundedProcessResult> extract({
    required File archive,
    required String entry,
    required File output,
    int maximumBytes = 64,
  }) {
    return runTestProcess('java', [
      'scripts/AndroidArchiveEntryExtractor.java',
      archive.path,
      entry,
      output.path,
      '$maximumBytes',
    ], workingDirectory: Directory.current.path);
  }

  test('extracts exactly one validated entry', () async {
    final archive = await _createArchive(root, zipWriter, 'valid.aab', <String>[
      'BundleConfig.pb:7',
      'base/manifest/AndroidManifest.xml:11',
    ]);
    final output = File('${root.path}/output/BundleConfig.pb');
    output.parent.createSync();

    final result = await extract(
      archive: archive,
      entry: 'BundleConfig.pb',
      output: output,
    );

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, contains('EXTRACTED_ENTRY_BYTES=7'));
    expect(output.readAsBytesSync(), everyElement('x'.codeUnitAt(0)));
  });

  test('rejects a missing requested entry without creating output', () async {
    final archive = await _createArchive(
      root,
      zipWriter,
      'missing.aab',
      <String>['base/manifest/AndroidManifest.xml:11'],
    );
    final output = File('${root.path}/missing/BundleConfig.pb');
    output.parent.createSync();

    final result = await extract(
      archive: archive,
      entry: 'BundleConfig.pb',
      output: output,
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('requested archive entry is missing'));
    expect(output.existsSync(), isFalse);
  });

  test(
    'validates every archive path before writing the requested entry',
    () async {
      final archive = await _createArchive(
        root,
        zipWriter,
        'traversal.aab',
        <String>['BundleConfig.pb:7', 'base/../outside.pb:3'],
      );
      final output = File('${root.path}/traversal/BundleConfig.pb');
      output.parent.createSync();

      final result = await extract(
        archive: archive,
        entry: 'BundleConfig.pb',
        output: output,
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('unsafe path'));
      expect(output.existsSync(), isFalse);
      expect(File('${root.path}/outside.pb').existsSync(), isFalse);
    },
  );

  test('enforces the caller-specific expanded byte limit', () async {
    final archive = await _createArchive(
      root,
      zipWriter,
      'oversize.aab',
      <String>['BundleConfig.pb:9'],
    );
    final output = File('${root.path}/oversize/BundleConfig.pb');
    output.parent.createSync();

    final result = await extract(
      archive: archive,
      entry: 'BundleConfig.pb',
      output: output,
      maximumBytes: 8,
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('requested archive entry exceeds'));
    expect(output.existsSync(), isFalse);
  });

  test('rejects a symlinked archive', () async {
    final archive = await _createArchive(root, zipWriter, 'real.aab', <String>[
      'BundleConfig.pb:7',
    ]);
    final linkedArchive = Link('${root.path}/linked.aab')
      ..createSync(archive.path);
    final output = File('${root.path}/linked/BundleConfig.pb');
    output.parent.createSync();

    final result = await extract(
      archive: File(linkedArchive.path),
      entry: 'BundleConfig.pb',
      output: output,
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('not a regular file'));
    expect(output.existsSync(), isFalse);
  });

  test('rejects a symlinked output parent', () async {
    final archive = await _createArchive(
      root,
      zipWriter,
      'parent.aab',
      <String>['BundleConfig.pb:7'],
    );
    final realParent = Directory('${root.path}/real-output')..createSync();
    final linkedParent = Link('${root.path}/linked-output')
      ..createSync(realParent.path);
    final output = File('${linkedParent.path}/BundleConfig.pb');

    final result = await extract(
      archive: archive,
      entry: 'BundleConfig.pb',
      output: output,
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('non-symlink directory'));
    expect(realParent.listSync(), isEmpty);
  });

  test('never overwrites an existing output path', () async {
    final archive = await _createArchive(
      root,
      zipWriter,
      'existing.aab',
      <String>['BundleConfig.pb:7'],
    );
    final output = File('${root.path}/existing/BundleConfig.pb')
      ..createSync(recursive: true)
      ..writeAsStringSync('preserve');

    final result = await extract(
      archive: archive,
      entry: 'BundleConfig.pb',
      output: output,
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('must not already exist'));
    expect(output.readAsStringSync(), 'preserve');
  });
}

Future<File> _createArchive(
  Directory root,
  File zipWriter,
  String name,
  List<String> entries,
) async {
  final archive = File('${root.path}/$name');
  final result = await runTestProcess('java', [
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
