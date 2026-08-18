import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File keystore;
  late String inspector;

  setUp(() {
    root = Directory.systemTemp.createTempSync('utexo_jar_signatures_');
    keystore = File('${root.path}/signing.p12');
    inspector =
        '${Directory.current.path}/scripts/'
        'AndroidJarSignatureInspector.java';
    _createSigner(keystore, 'first');
    _createSigner(keystore, 'second');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('distinguishes unsigned and completely signed archives', () {
    final archive = _createArchive(root, 'complete.aab');

    final unsigned = _inspect(inspector, archive);

    expect(unsigned.exitCode, 0, reason: '${unsigned.stderr}');
    expect((unsigned.stdout as String).trim(), 'UNSIGNED');

    _sign(archive, keystore, 'first');
    final signed = _inspect(inspector, archive);
    final approved = _certificateDigest(keystore, 'first');

    expect(signed.exitCode, 0, reason: '${signed.stderr}');
    expect((signed.stdout as String).trim(), 'SIGNED_SHA256=$approved');
  });

  test('rejects unsigned or modified content in a signed archive', () {
    final partiallySigned = _createArchive(root, 'partial.aab');
    _sign(partiallySigned, keystore, 'first');
    final appended = File('${root.path}/unsigned.txt')
      ..writeAsStringSync('unsigned');
    _runRequired('jar', [
      '--update',
      '--file',
      partiallySigned.path,
      '-C',
      appended.parent.path,
      appended.uri.pathSegments.last,
    ]);

    final partial = _inspect(inspector, partiallySigned);

    expect(partial.exitCode, isNot(0));
    expect('${partial.stderr}', contains('unsigned content entry'));

    final modified = _createArchive(root, 'modified.aab');
    _sign(modified, keystore, 'first');
    final replacement = File('${root.path}/replacement/payload.txt');
    replacement.parent.createSync(recursive: true);
    replacement.writeAsStringSync('modified');
    _runRequired('jar', [
      '--update',
      '--file',
      modified.path,
      '-C',
      replacement.parent.path,
      'payload.txt',
    ]);

    final corrupt = _inspect(inspector, modified);

    expect(corrupt.exitCode, isNot(0));
    expect('${corrupt.stderr}', contains('signature verification failed'));
  });

  test('rejects content carrying more than one signer', () {
    final archive = _createArchive(root, 'multiple.aab');
    _sign(archive, keystore, 'first');
    _sign(archive, keystore, 'second');

    final result = _inspect(inspector, archive);

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('2 signers'));
  });
}

File _createArchive(Directory root, String name) {
  final content = Directory('${root.path}/$name-content')..createSync();
  File('${content.path}/payload.txt').writeAsStringSync('reviewed payload');
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

void _createSigner(File keystore, String alias) {
  _runRequired('keytool', [
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

void _sign(File archive, File keystore, String alias) {
  _runRequired('jarsigner', [
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

String _certificateDigest(File keystore, String alias) {
  final result = _runRequired('keytool', [
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
  ).firstMatch(result.stdout as String);
  if (match == null) {
    throw StateError('Could not read fixture certificate SHA-256.');
  }
  return match.group(1)!.replaceAll(':', '').toLowerCase();
}

ProcessResult _inspect(String inspector, File archive) {
  return Process.runSync('java', [inspector, archive.path]);
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
