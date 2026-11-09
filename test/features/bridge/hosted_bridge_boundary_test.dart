import 'package:aster/core/storage/secure_storage_service.dart';
import 'package:aster/features/bridge/data/hosted_bridge_protocol.dart';
import 'package:aster/features/bridge/data/hosted_bridge_relay.dart';
import 'package:aster/features/bridge/data/hosted_bridge_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reown_core/reown_core.dart';
import 'package:reown_sign/reown_sign.dart';

void main() {
  final topic = 'a' * 64;
  final key = 'b' * 64;
  final link =
      'wc:$topic@2?relay-protocol=irn&symKey=$key&expiryTimestamp=1100';

  test('pairs only current bounded v2 IRN connection links', () {
    expect(HostedBridgeProtocol.pairingLink(link, now: 1000)?.path, '$topic@2');
    for (final value in [
      '$link&symKey=$key',
      '$link&relay-protocol=irn',
      '$link&unrecognized=true',
      '$link#ref',
      link.replaceFirst('irn', 'other'),
      link.replaceFirst('@2', '@1'),
      link.replaceFirst('1100', '1000'),
    ]) {
      expect(HostedBridgeProtocol.pairingLink(value, now: 1000), isNull);
    }
  });

  test('requires a verified exact Dev origin for new grants', () {
    VerifyContext verify(String origin, Validation value, {bool? scam}) =>
        VerifyContext(
          origin: origin,
          validation: value,
          verifyUrl: '',
          isScam: scam,
        );
    const origin = HostedBridgeProtocol.origin;
    expect(
      HostedBridgeProtocol.verified(verify(origin, Validation.VALID)),
      isTrue,
    );
    expect(
      HostedBridgeProtocol.verified(verify(origin, Validation.UNKNOWN)),
      isFalse,
    );
    expect(
      HostedBridgeProtocol.verified(
        verify(origin, Validation.VALID, scam: true),
      ),
      isFalse,
    );
    expect(
      HostedBridgeProtocol.verified(
        verify('$origin.example.org', Validation.VALID),
      ),
      isFalse,
    );
    expect(
      HostedBridgeProtocol.acceptsRequestVerification(
        verify('', Validation.UNKNOWN),
      ),
      isTrue,
    );
    expect(
      HostedBridgeProtocol.acceptsRequestVerification(
        verify('https://example.org', Validation.UNKNOWN),
      ),
      isFalse,
    );
  });

  test('negotiates only the pinned WebRGB profile and method ceiling', () {
    final proposal = ProposalData(
      id: 1,
      expiry: 1100,
      relays: [Relay('irn')],
      proposer: ConnectionMetadata(
        publicKey: key,
        metadata: const PairingMetadata(
          name: 'Dev Bridge',
          description: '',
          url: HostedBridgeProtocol.origin,
          icons: [],
        ),
      ),
      pairingTopic: topic,
      requiredNamespaces: {
        'rgb': RequiredNamespace(
          chains: const [HostedBridgeProtocol.chain],
          methods: HostedBridgeProtocol.requiredMethods.toList(),
          events: const [],
        ),
      },
      optionalNamespaces: const {
        'rgb': RequiredNamespace(
          chains: [HostedBridgeProtocol.chain],
          methods: ['rgb_burnAsset', 'eth_sendTransaction'],
          events: [],
        ),
      },
      sessionProperties: HostedBridgeProtocol.sessionProperties,
    );
    expect(HostedBridgeProtocol.negotiate(proposal), {
      ...HostedBridgeProtocol.requiredMethods,
      'rgb_burnAsset',
    });
    expect(
      HostedBridgeProtocol.negotiate(proposal.copyWith(sessionProperties: {})),
      isNull,
    );
    expect(
      HostedBridgeProtocol.negotiate(
        proposal.copyWith(
          requiredNamespaces: {
            'eip155': const RequiredNamespace(
              chains: ['eip155:42161'],
              methods: ['eth_sendTransaction'],
              events: [],
            ),
          },
        ),
      ),
      isNull,
    );
  });

  test('request digest binds exact network, method and canonical params', () {
    String? digest(Object? args, {String chain = HostedBridgeProtocol.chain}) =>
        HostedBridgeProtocol.requestDigest(chain, 'rgb_burnAsset', args);
    expect(
      digest([
        {'amount': '12', 'address': 'a'},
      ]),
      digest([
        {'address': 'a', 'amount': '12'},
      ]),
    );
    expect(
      digest([
        {'amount': '12', 'address': 'a'},
      ]),
      isNot(
        digest([
          {'amount': '13', 'address': 'a'},
        ]),
      ),
    );
    expect(digest([], chain: 'rgb:signet'), isNull);
    expect(digest(['x' * 65537]), isNull);
  });

  test('relay construction binds both Reown stores to the protected owner', () {
    expect(
      HostedBridgeRelay(HostedBridgeStore(storage: _MemorySecrets())),
      isA<HostedBridgeRelay>(),
    );
  });

  test(
    'encrypted-store state reopens without sharing mutable values',
    () async {
      final secret = _MemorySecrets();
      final store = HostedBridgeStore(storage: secret);
      final value = {
        'request': {'expiry': 1100},
      };
      await store.set('relay', value);
      value['request']!['expiry'] = 1200;
      final reopened = HostedBridgeStore(storage: secret);
      await reopened.init();
      expect(reopened.get('relay'), {
        'request': {'expiry': 1100},
      });
      secret.failWrite = true;
      await expectLater(reopened.set('relay', value), throwsStateError);
      expect(reopened.get('relay'), {
        'request': {'expiry': 1100},
      });
    },
  );
}

final class _MemorySecrets implements SecureKeyValueStore {
  final _data = <String, String>{};
  bool failWrite = false;

  @override
  Future<bool> containsKey({required String key}) async =>
      _data.containsKey(key);
  @override
  Future<void> delete({required String key}) async => _data.remove(key);
  @override
  Future<Set<String>> keys() async => _data.keys.toSet();
  @override
  Future<String?> read({required String key}) async => _data[key];
  @override
  Future<void> write({required String key, required String value}) async {
    if (failWrite) throw StateError('write refused');
    _data[key] = value;
  }
}
