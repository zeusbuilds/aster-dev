import 'dart:async';
import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const configured = WalletServiceConfiguration(
    environment: BlockchainEnvironment.mainnet,
    sdkNetwork: 'mainnet',
    ethRpcUrl: 'https://rpc.aster-wallet.com',
    ethChainId: '42161',
    usdtAsset: RgbAssetConfiguration(
      contractId: 'rgb:deployment-owned-contract',
      precision: 6,
    ),
  );

  test('validates chain identity with a bounded read-only RPC', () async {
    var requests = 0;
    final validator = HttpEvmChainValidator(
      clientFactory: () => MockClient((request) async {
        requests += 1;
        expect(request.url.toString(), configured.ethRpcUrl);
        expect(request.method, 'POST');
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(jsonDecode(request.body), {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'eth_chainId',
          'params': <Object>[],
        });
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '0xa4b1'}),
          200,
        );
      }),
    );
    await validator.verify(configured);
    expect(requests, 1);
  });

  test(
    'unconfigured BTC-only wallet does not contact any EVM service',
    () async {
      var clients = 0;
      final validator = HttpEvmChainValidator(
        clientFactory: () {
          clients += 1;
          throw StateError('No EVM RPC is permitted');
        },
      );
      await validator.verify(
        const WalletServiceConfiguration(
          environment: BlockchainEnvironment.mainnet,
          sdkNetwork: 'mainnet',
        ),
      );
      expect(clients, 0);
    },
  );

  test(
    'rejects wrong chains, RPC errors, malformed or ambiguous replies',
    () async {
      for (final response in <Object?>[
        {'jsonrpc': '2.0', 'id': 1, 'result': '0x1'},
        {'jsonrpc': '2.0', 'id': 1, 'result': '0x0a4b1'},
        {'jsonrpc': '2.0', 'id': 1, 'result': '42161'},
        {'jsonrpc': '2.0', 'id': 1, 'result': 42161},
        {'jsonrpc': '2.0', 'id': 1, 'result': '0x${'f' * 65}'},
        {'jsonrpc': '1.0', 'id': 1, 'result': '0xa4b1'},
        {'jsonrpc': '2.0', 'id': 2, 'result': '0xa4b1'},
        {'jsonrpc': '2.0', 'id': '1', 'result': '0xa4b1'},
        {'jsonrpc': '2.0', 'id': 1, 'result': '0xa4b1', 'error': null},
        {
          'jsonrpc': '2.0',
          'id': 1,
          'error': {'code': -32601},
        },
        [
          {'jsonrpc': '2.0', 'id': 1, 'result': '0xa4b1'},
        ],
        null,
      ]) {
        final validator = HttpEvmChainValidator(
          clientFactory: () =>
              MockClient((_) async => http.Response(jsonEncode(response), 200)),
        );
        await expectLater(
          validator.verify(configured),
          throwsA(isA<AppConfigurationException>()),
        );
      }
    },
  );

  test(
    'rejects redirects, unavailable services, oversized and malformed bodies',
    () async {
      for (final response in [
        http.Response(
          '',
          302,
          headers: {'location': 'https://another.aster-wallet.com'},
        ),
        http.Response('', 503),
        http.Response(
          'x' * (HttpEvmChainValidator.maximumResponseBytes + 1),
          200,
        ),
        http.Response('not json', 200),
        http.Response.bytes([0xff], 200),
      ]) {
        final validator = HttpEvmChainValidator(
          clientFactory: () => MockClient((_) async => response),
        );
        await expectLater(
          validator.verify(configured),
          throwsA(isA<AppConfigurationException>()),
        );
      }
    },
  );

  test(
    'caps chunked RPC bodies without trusting a content-length header',
    () async {
      final validator = HttpEvmChainValidator(
        clientFactory: () => MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              List<int>.filled(2048, 0x20),
              List<int>.filled(2049, 0x20),
            ]),
            200,
          ),
        ),
      );
      await expectLater(
        validator.verify(configured),
        throwsA(isA<AppConfigurationException>()),
      );
    },
  );

  testWidgets('chain verification deadline closes an unresponsive transport', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final client = _TrackedClient((_) => response.future);
    Object? failure;
    final operation = HttpEvmChainValidator(clientFactory: () => client)
        .verify(configured)
        .catchError((Object error) {
          failure = error;
        });
    await tester.pump();
    await tester.pump(HttpEvmChainValidator.requestTimeout);
    await operation;
    expect(failure, isA<TimeoutException>());
    expect(client.closed, isTrue);
    response.complete(http.Response('', 503));
    await tester.pump();
  });
}

final class _TrackedClient extends MockClient {
  _TrackedClient(super.handler);
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}
