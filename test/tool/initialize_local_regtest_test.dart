import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../../tool/initialize_local_regtest.dart';

void main() {
  test(
    'new local state is private, independent and cannot be overwritten',
    () async {
      final root = Directory.systemTemp.createTempSync('aster-regtest-init-');
      addTearDown(() => root.deleteSync(recursive: true));
      final compose = File('${root.path}/ops/regtest/compose.yaml');
      compose.parent.createSync(recursive: true);
      compose.writeAsStringSync('name: aster-app-regtest\n');

      await initializeLocalRegtest(root);
      final state = Directory('${root.path}/.local/aster-regtest');
      final envFile = File('${state.path}/compose.env');
      final original = envFile.readAsStringSync();
      final entries = <String, String>{};
      for (final line in const LineSplitter().convert(original)) {
        final match = RegExp("^([A-Z_]+)='([^']*)'\$").firstMatch(line)!;
        entries[match[1]!] = match[2]!;
      }
      final password = entries['ASTER_REGTEST_RPC_PASSWORD']!;
      expect(password, matches(RegExp(r'^[0-9a-f]{64}$')));
      final auth = entries['ASTER_REGTEST_RPC_AUTH']!;
      final salt = auth.split(':')[1].split(r'$')[0];
      final digest = Hmac(
        sha256,
        utf8.encode(salt),
      ).convert(utf8.encode(password));
      expect(auth, 'aster:$salt\$$digest');
      final config = File('${root.path}/config/regtest.ios.local.json')
          .readAsStringSync();
      expect(config.contains(password), isFalse);
      expect(jsonDecode(config), {
        'ASTER_DAEMON_PORT': '19735',
        'ASTER_INDEXER_URL': '127.0.0.1:51001',
        'ASTER_LDK_PEER_PORT': '19736',
        'ASTER_NETWORK': 'regtest',
        'ASTER_RGB_PROXY_URL': 'rpc://127.0.0.1:3100/json-rpc',
      });
      expect(state.statSync().mode & 0x1ff, 448);
      expect(envFile.statSync().mode & 0x1ff, 384);
      expect(
        File('${state.path}/rpc-client.conf').statSync().mode & 0x1ff,
        384,
      );
      await expectLater(initializeLocalRegtest(root), throwsFormatException);
      expect(envFile.readAsStringSync(), original);
    },
    skip: !Platform.isMacOS && !Platform.isLinux,
  );

  test('a symbolic local root cannot redirect credential creation', () async {
    final root = Directory.systemTemp.createTempSync('aster-regtest-link-');
    final outside = Directory.systemTemp.createTempSync(
      'aster-regtest-outside-',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    addTearDown(() => outside.deleteSync(recursive: true));
    final compose = File('${root.path}/ops/regtest/compose.yaml');
    compose.parent.createSync(recursive: true);
    compose.writeAsStringSync('name: aster-app-regtest\n');
    Link('${root.path}/.local').createSync(outside.path);
    await expectLater(initializeLocalRegtest(root), throwsFormatException);
    expect(outside.listSync(), isEmpty);
  }, skip: !Platform.isMacOS && !Platform.isLinux);

  test(
    'a symbolic config root is rejected before credentials are created',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'aster-regtest-config-link-',
      );
      final outside = Directory.systemTemp.createTempSync(
        'aster-regtest-config-outside-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      addTearDown(() => outside.deleteSync(recursive: true));
      final compose = File('${root.path}/ops/regtest/compose.yaml');
      compose.parent.createSync(recursive: true);
      compose.writeAsStringSync('name: aster-app-regtest\n');
      Link('${root.path}/config').createSync(outside.path);
      await expectLater(initializeLocalRegtest(root), throwsFormatException);
      expect(outside.listSync(), isEmpty);
      expect(
        Directory('${root.path}/.local/aster-regtest').existsSync(),
        isFalse,
      );
    },
    skip: !Platform.isMacOS && !Platform.isLinux,
  );

  test(
    'Compose owns its ports, data, pinned images and bounded health checks',
    () {
      final doc = loadYaml(
        File('ops/regtest/compose.yaml').readAsStringSync(),
      ) as YamlMap;
      expect(doc['name'], 'aster-app-regtest');
      final services = doc['services'] as YamlMap;
      expect(services.keys.toSet(), {'bitcoind', 'electrs', 'proxy', 'miner'});
      final publishedPorts = <int>{};
      for (final service in services.values.cast<YamlMap>()) {
        expect(service['image'], matches(RegExp(r'@sha256:[0-9a-f]{64}$')));
        expect((service['labels'] as YamlMap)['com.aster.owner'], 'aster-dev');
        expect((service['healthcheck'] as YamlMap)['timeout'], isNotNull);
        for (final volume in service['volumes'] as YamlList) {
          expect(volume as String, startsWith('../../.local/aster-regtest/'));
        }
        for (final port in (service['ports'] as YamlList?) ?? []) {
          final parts = (port as String).split(':');
          expect(parts.first, '127.0.0.1');
          expect(publishedPorts.add(int.parse(parts[1])), isTrue);
        }
      }
      expect(publishedPorts, {19443, 51001, 3100});
      expect(
        publishedPorts.intersection({18443, 50001, 3000, 18444, 50002, 3013}),
        isEmpty,
      );
      final miner = services['miner'] as YamlMap;
      final bitcoin = services['bitcoind'] as YamlMap;
      expect(bitcoin['command'], containsAll(['-connect=0', '-listen=1']));
      expect((bitcoin['environment'] as YamlMap).containsKey('MYGID'), isFalse);
      final command = (miner['command'] as YamlList).single as String;
      expect(command, contains('-rpcconnect=bitcoind'));
      expect(command, contains('-rpcclienttimeout=30'));
      expect(command, contains('-regtest'));
    },
  );
}
