import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WalletServiceConfiguration services(String host) =>
      WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        indexerUrl: 'https://$host/indexer',
        rgbTransportProxy: 'rpcs://proxy.example.com/json-rpc',
      );

  test('classifies local hosts without resolving public DNS', () {
    for (final host in [
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.2',
      '169.254.1.2',
      '[::1]',
      '[fd12::1]',
      '[fe80::1]',
      '[::ffff:192.168.1.2]',
      'indexer.local',
    ]) {
      expect(
        PlatformLocalNetworkAccess.requiresLocalNetwork(services(host)),
        isTrue,
        reason: host,
      );
    }
    for (final host in [
      'indexer.example.com',
      'localhost.example.com',
      '172.15.255.255',
      '172.32.0.0',
      '192.169.0.1',
      '8.8.8.8',
      '[2001:4860:4860::8888]',
      '[::ffff:8.8.8.8]',
    ]) {
      expect(
        PlatformLocalNetworkAccess.requiresLocalNetwork(services(host)),
        isFalse,
        reason: host,
      );
    }
  });

  test('includes every native service endpoint in permission policy', () {
    const remote = 'https://indexer.example.com';
    for (final configuration in [
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        indexerUrl: remote,
        rgbTransportProxy: 'rpc://10.0.2.2:28090/json-rpc',
      ),
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        indexerUrl: remote,
        lspBaseUrl: 'https://192.168.1.1',
      ),
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        indexerUrl: remote,
        vssUrl: 'https://192.168.1.1',
      ),
      const WalletServiceConfiguration(
        environment: BlockchainEnvironment.regtest,
        sdkNetwork: 'regtest',
        indexerUrl: remote,
        ethRpcUrl: 'http://10.0.2.2:18555',
      ),
    ]) {
      expect(
        PlatformLocalNetworkAccess.requiresLocalNetwork(configuration),
        isTrue,
      );
    }
  });

  test('bare Electrum hosts retain the local network permission policy', () {
    for (final host in ['10.0.2.2:18001', '127.0.0.1:18001', '[::1]:18001']) {
      expect(
        PlatformLocalNetworkAccess.requiresLocalNetwork(
          WalletServiceConfiguration(
            environment: BlockchainEnvironment.regtest,
            sdkNetwork: 'regtest',
            indexerUrl: host,
          ),
        ),
        isTrue,
      );
    }
  });

  test(
    'public profiles and non-Android hosts never request permission',
    () async {
      var requests = 0;
      final android = PlatformLocalNetworkAccess(
        isAndroid: () => true,
        requestPermission: () async {
          requests++;
          return true;
        },
      );
      final other = PlatformLocalNetworkAccess(
        isAndroid: () => false,
        requestPermission: () async {
          requests++;
          return true;
        },
      );

      await android.ensureFor(services('indexer.example.com'));
      await other.ensureFor(services('10.0.2.2'));
      expect(requests, 0);
    },
  );

  test(
    'coalesces pending consent and rechecks access after each open',
    () async {
      final grant = Completer<bool>();
      var requests = 0;
      final access = PlatformLocalNetworkAccess(
        isAndroid: () => true,
        requestPermission: () {
          requests++;
          return grant.future;
        },
      );
      final first = access.ensureFor(services('10.0.2.2'));
      final concurrent = access.ensureFor(services('10.0.2.2'));
      expect(requests, 1);
      grant.complete(true);
      await Future.wait([first, concurrent]);
      await access.ensureFor(services('10.0.2.2'));
      expect(requests, 2);
    },
  );

  test('denial is typed and can be retried after a grant', () async {
    var granted = false;
    final access = PlatformLocalNetworkAccess(
      isAndroid: () => true,
      requestPermission: () async => granted,
    );
    await expectLater(
      access.ensureFor(services('10.0.2.2')),
      throwsA(
        isA<LocalNetworkAccessException>().having(
          (error) => error.reason,
          'reason',
          LocalNetworkAccessFailure.denied,
        ),
      ),
    );
    granted = true;
    await access.ensureFor(services('10.0.2.2'));
  });

  test('platform failures retain no private exception text', () async {
    final access = PlatformLocalNetworkAccess(
      isAndroid: () => true,
      requestPermission: () async => throw PlatformException(
        code: 'private-endpoint',
        message: 'private wallet data',
      ),
    );
    await expectLater(
      access.ensureFor(services('10.0.2.2')),
      throwsA(
        isA<LocalNetworkAccessException>()
            .having(
              (error) => error.reason,
              'reason',
              LocalNetworkAccessFailure.unavailable,
            )
            .having(
              (error) => error.toString(),
              'redacted text',
              isNot(contains('private')),
            ),
      ),
    );
  });

  test('platform channel requires an explicit boolean result', () async {
    const channel = MethodChannel('com.aster.wallet/local_network');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ensureAccess');
      expect(call.arguments, isNull);
      calls++;
      return calls == 1 ? true : null;
    });
    final access = PlatformLocalNetworkAccess(isAndroid: () => true);
    await access.ensureFor(services('10.0.2.2'));
    await expectLater(
      access.ensureFor(services('10.0.2.2')),
      throwsA(
        isA<LocalNetworkAccessException>().having(
          (error) => error.reason,
          'reason',
          LocalNetworkAccessFailure.unavailable,
        ),
      ),
    );
  });
}
