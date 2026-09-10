import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'bounded_process.dart';

/// Creates new, private Aster-only regtest credentials and public app defines.
///
/// Existing state is never overwritten or reset. This is a macOS/Linux local
/// development operation, not a release configuration or a migration command.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty || (!Platform.isMacOS && !Platform.isLinux)) {
    stderr.writeln(
      'Run without arguments on macOS or Linux from the app root.',
    );
    exitCode = 64;
    return;
  }
  try {
    await initializeLocalRegtest(Directory.current);
    stdout.writeln('Aster regtest initialized. Credentials were not printed.');
    stdout.writeln('Compose environment: .local/aster-regtest/compose.env');
    stdout.writeln('iOS app configuration: config/regtest.ios.local.json');
  } on Object {
    // OS/native diagnostics can include credential-bearing arguments or paths.
    stderr.writeln(
      'Initialization refused or failed. Existing local state is preserved. '
      'Check the app root, permissions, and whether regtest is already initialized.',
    );
    exitCode = 1;
  }
}

/// Initializes an unused [root] without changing another workspace or stack.
///
/// The destination must not exist. `mkdir` provides exclusive creation and
/// private directory permissions before any secret is written. Partial state
/// on an IO failure is retained for explicit inspection, never silently reset.
Future<void> initializeLocalRegtest(Directory root) async {
  final canonicalRoot = Directory(await root.resolveSymbolicLinks());
  final compose = File('${canonicalRoot.path}/ops/regtest/compose.yaml');
  if (!await compose.exists()) throw const FormatException('Missing compose');
  final local = Directory('${canonicalRoot.path}/.local');
  final localType = await FileSystemEntity.type(local.path, followLinks: false);
  if (localType != FileSystemEntityType.notFound &&
      localType != FileSystemEntityType.directory) {
    throw const FormatException('Invalid local directory');
  }
  await local.create();
  final state = Directory('${local.path}/aster-regtest');
  final config = File('${canonicalRoot.path}/config/regtest.ios.local.json');
  final configType = await FileSystemEntity.type(
    config.parent.path,
    followLinks: false,
  );
  if (configType != FileSystemEntityType.notFound &&
      configType != FileSystemEntityType.directory) {
    throw const FormatException('Invalid config directory');
  }
  if (await FileSystemEntity.type(state.path, followLinks: false) !=
          FileSystemEntityType.notFound ||
      await FileSystemEntity.type(config.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
    throw const FormatException('Already initialized');
  }
  final uid = await _command('/usr/bin/id', ['-u']);
  if (!RegExp(r'^\d+$').hasMatch(uid)) {
    throw const FormatException('Invalid account identity');
  }
  await _command('/bin/mkdir', ['-m', '700', state.path]);
  final random = Random.secure();
  String hex(int bytes) => List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final password = hex(32);
  final salt = hex(16);
  final digest = Hmac(sha256, utf8.encode(salt)).convert(utf8.encode(password));
  final environment = File('${state.path}/compose.env');
  final client = File('${state.path}/rpc-client.conf');
  await environment.writeAsString(
    "ASTER_LOCAL_UID='$uid'\n"
    "ASTER_REGTEST_RPC_AUTH='aster:$salt\$$digest'\n"
    "ASTER_REGTEST_RPC_PASSWORD='$password'\n",
    flush: true,
  );
  await client.writeAsString(
    'rpcuser=aster\nrpcpassword=$password\n',
    flush: true,
  );
  await _command('/bin/chmod', ['600', environment.path, client.path]);
  for (final name in ['bitcoind', 'electrs', 'proxy']) {
    await Directory('${state.path}/$name').create();
  }
  await File('${state.path}/owner.json').writeAsString(
    jsonEncode({'project': 'aster-app-regtest', 'schema': 1}),
    flush: true,
  );
  await config.parent.create(recursive: true);
  await config.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'ASTER_DAEMON_PORT': '19735', 'ASTER_INDEXER_URL': '127.0.0.1:51001', 'ASTER_LDK_PEER_PORT': '19736', 'ASTER_NETWORK': 'regtest', 'ASTER_RGB_PROXY_URL': 'rpc://127.0.0.1:3100/json-rpc'})}\n',
    flush: true,
  );
}

Future<String> _command(String executable, List<String> arguments) async {
  final result = await runBoundedProcess(
    executable,
    arguments,
    timeout: const Duration(seconds: 30),
    maxStdoutBytes: 8192,
    maxStderrBytes: 8192,
  );
  if (result.exitCode != 0) throw const FileSystemException('Setup failed');
  return result.stdout.trim();
}
