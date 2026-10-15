import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../config/evm_chain_validator.dart';
import '../errors/app_failure.dart';

/// One credential-free, read-only JSON-RPC request with bounded I/O.
///
/// This validates chain identity; it does not authenticate a BFA contract or
/// establish that a configured RGB contract is the approved mainnet asset.
final class HttpEvmChainValidator implements EvmChainValidator {
  const HttpEvmChainValidator({this._clientFactory});

  static const requestTimeout = Duration(seconds: 15);
  static const maximumResponseBytes = 4096;
  final http.Client Function()? _clientFactory;

  @override
  Future<void> verify(WalletServiceConfiguration services) async {
    services.validate();
    final expected = services.ethChainId;
    if (expected == null) return;
    final client = (_clientFactory ?? http.Client.new)();
    try {
      await _verify(
        client,
        services.ethRpcUrl!,
        expected,
      ).timeout(requestTimeout);
    } finally {
      client.close();
    }
  }

  Future<void> _verify(
    http.Client client,
    String endpoint,
    String expected,
  ) async {
    final request = http.Request('POST', Uri.parse(endpoint))
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(const {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'eth_chainId',
        'params': <Object>[],
      });
    final response = await client.send(request);
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > maximumResponseBytes) {
      throw const AppConfigurationException();
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maximumResponseBytes) {
        throw const AppConfigurationException();
      }
      bytes.addAll(chunk);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const AppConfigurationException();
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['jsonrpc'] != '2.0' ||
        decoded['id'] != 1 ||
        decoded.containsKey('error')) {
      throw const AppConfigurationException();
    }
    final result = decoded['result'];
    if (result is! String ||
        result.length > 66 ||
        !RegExp(r'^0x[1-9a-fA-F][0-9a-fA-F]*$').hasMatch(result)) {
      throw const AppConfigurationException();
    }
    final actualChain = BigInt.tryParse(result.substring(2), radix: 16);
    if (actualChain == null || actualChain != BigInt.parse(expected)) {
      throw const AppConfigurationException();
    }
  }
}
