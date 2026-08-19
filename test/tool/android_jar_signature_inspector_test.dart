import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/bounded_test_process.dart';

void main() {
  late Directory root;
  late File keystore;
  late String inspector;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('utexo_jar_signatures_');
    keystore = File('${root.path}/signing.p12');
    inspector =
        '${Directory.current.path}/scripts/'
        'AndroidJarSignatureInspector.java';
    await _createSigner(keystore, 'first');
    await _createSigner(keystore, 'second');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('distinguishes unsigned and completely signed archives', () async {
    final archive = await _createArchive(root, 'complete.aab');

    final unsigned = await _inspect(inspector, archive);

    expect(unsigned.exitCode, 0, reason: unsigned.stderr);
    expect(unsigned.stdout.trim(), 'UNSIGNED');

    await _sign(archive, keystore, 'first');
    final signed = await _inspect(inspector, archive);
    final approved = await _certificateDigest(keystore, 'first');

    expect(signed.exitCode, 0, reason: signed.stderr);
    expect(signed.stdout.trim(), 'SIGNED_SHA256=$approved');
  });

  test('rejects unsigned or modified content in a signed archive', () async {
    final partiallySigned = await _createArchive(root, 'partial.aab');
    await _sign(partiallySigned, keystore, 'first');
    final appended = File('${root.path}/unsigned.txt')
      ..writeAsStringSync('unsigned');
    await _runRequired('jar', [
      '--update',
      '--file',
      partiallySigned.path,
      '-C',
      appended.parent.path,
      appended.uri.pathSegments.last,
    ]);

    final partial = await _inspect(inspector, partiallySigned);

    expect(partial.exitCode, isNot(0));
    expect(partial.stderr, contains('unsigned content entry'));

    final modified = await _createArchive(root, 'modified.aab');
    await _sign(modified, keystore, 'first');
    final replacement = File('${root.path}/replacement/payload.txt');
    replacement.parent.createSync(recursive: true);
    replacement.writeAsStringSync('modified');
    await _runRequired('jar', [
      '--update',
      '--file',
      modified.path,
      '-C',
      replacement.parent.path,
      'payload.txt',
    ]);

    final corrupt = await _inspect(inspector, modified);

    expect(corrupt.exitCode, isNot(0));
    expect(corrupt.stderr, contains('signature verification failed'));
  });

  test('rejects content carrying more than one signer', () async {
    final archive = await _createArchive(root, 'multiple.aab');
    await _sign(archive, keystore, 'first');
    await _sign(archive, keystore, 'second');

    final result = await _inspect(inspector, archive);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('2 signers'));
  });
}

Future<File> _createArchive(Directory root, String name) async {
  final content = Directory('${root.path}/$name-content')..createSync();
  File('${content.path}/payload.txt').writeAsStringSync('reviewed payload');
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

Future<void> _createSigner(File keystore, String alias) async {
  await _runRequired('keytool', [
    '-genkeypair',
    '-alias',
    alias,
    '-keyalg',
    'RSA',
    '-keysize',
    '2048',
    '-validity',
    '3650',
    '-dname',
    'CN=UTEXO Test $alias',
    '-keystore',
    keystore.path,
    '-storetype',
    'PKCS12',
    '-storepass',
    'test-password',
    '-keypass',
    'test-password',
    '-noprompt',
  ]);
}

Future<void> _sign(File archive, File keystore, String alias) async {
  await _runRequired('jarsigner', [
    '-keystore',
    keystore.path,
    '-storepass',
    'test-password',
    '-keypass',
    'test-password',
    archive.path,
    alias,
  ]);
}

Future<String> _certificateDigest(File keystore, String alias) async {
  final result = await _runRequired('keytool', [
    '-list',
    '-v',
    '-alias',
    alias,
    '-keystore',
    keystore.path,
    '-storepass',
    'test-password',
  ]);
  final match = RegExp(
    r'^\s*SHA256:\s*(.+)$',
    multiLine: true,
  ).firstMatch(result.stdout);
  if (match == null) {
    throw StateError('Could not read fixture certificate SHA-256.');
  }
  return match.group(1)!.replaceAll(':', '').toLowerCase();
}

Future<BoundedProcessResult> _inspect(String inspector, File archive) {
  return runTestProcess('java', [inspector, archive.path]);
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
