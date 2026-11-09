import 'dart:async';

import 'package:reown_core/pairing/pairing.dart';
import 'package:reown_core/reown_core.dart';
import 'package:reown_core/store/i_store.dart';
import 'package:reown_sign/reown_sign.dart';

import 'hosted_bridge_protocol.dart';
import 'hosted_bridge_store.dart';

typedef HostedBridgeRawRequest = void Function(
  String topic,
  int id,
  String chain,
  String method,
  Object? params,
  Object? expiry,
);

/// Wraps the WalletConnect wallet-side Sign API. The pinned Flutter version drops
/// request expiry from its public event, so retain that field at the point
/// where the Core has decrypted the relay message, before SDK normalization.
final class HostedBridgeRelay {
  HostedBridgeRelay(HostedBridgeStore store)
    : _kit = ReownSignClient(
        core: _EncryptedCore(store),
        metadata: const PairingMetadata(
          name: 'Aster Dev',
          description: 'Aster Dev Signet wallet',
          url: 'https://utexo.com',
          icons: [],
        ),
      ) {
    if (!identical(_kit.core.storage, store) ||
        !identical(_kit.core.secureStorage, store)) {
      throw StateError('WalletConnect secure storage was not installed.');
    }
  }

  final ReownSignClient _kit;
  Future<void>? _start;
  bool _closed = false;
  void Function(SessionProposalEvent)? onProposal;
  void Function(SessionRequest)? onRequest;
  void Function()? onReconnect;
  void Function(String)? onRemoved;
  HostedBridgeRawRequest? onRawRequest;

  Future<void> start() => _start ??= _initialize();

  Future<void> _initialize() async {
    _kit.onSessionProposal.subscribe(_proposal);
    _kit.onSessionRequest.subscribe(_request);
    _kit.onSessionDelete.subscribe(_delete);
    _kit.onSessionExpire.subscribe(_expire);
    _kit.core.relayClient.onRelayClientConnect.subscribe(_connect);
    try {
      await _kit.init();
      if (_closed) return;
      final pairing = _kit.core.pairing;
      if (pairing is! Pairing) {
        throw StateError('Unsupported WalletConnect pairing.');
      }
      const key = MethodConstants.WC_SESSION_REQUEST;
      final original = pairing.routerMapRequest[key];
      if (original == null) {
        throw StateError('Missing WalletConnect request handler.');
      }
      pairing.routerMapRequest[key] = RegisteredFunction(
        method: original.method,
        type: original.type,
        function: (topic, payload, [attestation, type = TransportType.relay]) {
          final envelope = payload.params;
          if (!_closed && type == TransportType.relay && envelope is Map) {
            final body = envelope['request'];
            final chain = envelope['chainId'];
            if (body is Map && chain is String && body['method'] is String) {
              onRawRequest?.call(
                topic,
                payload.id,
                chain,
                body['method'] as String,
                body['params'],
                body['expiryTimestamp'],
              );
            }
          }
          return original.function(topic, payload, attestation, type);
        },
      );
    } on Object {
      await close();
      rethrow;
    }
  }

  void _proposal(SessionProposalEvent? event) {
    if (!_closed && event != null) onProposal?.call(event);
  }

  void _request(SessionRequestEvent? event) {
    if (_closed || event == null) return;
    final row = pending[event.id.toString()];
    if (row != null &&
        row.topic == event.topic &&
        row.method == event.method &&
        row.chainId == event.chainId &&
        row.transportType == TransportType.relay) {
      onRequest?.call(row);
    }
  }

  void _delete(SessionDelete? event) {
    if (!_closed && event != null) onRemoved?.call(event.topic);
  }

  void _expire(SessionExpire? event) {
    if (!_closed && event != null) onRemoved?.call(event.topic);
  }

  void _connect(Object? event) {
    if (!_closed) onReconnect?.call();
  }

  Map<String, SessionData> get sessions => _kit.getActiveSessions();
  Map<String, SessionRequest> get pending => _kit.getPendingSessionRequests();

  Future<void> pair(Uri link) async {
    await _kit.pair(uri: link);
  }

  Future<ApproveResponse> approve(
    int id,
    String account,
    Set<String> methods,
  ) => _kit.approve(
    id: id,
    namespaces: {
      HostedBridgeProtocol.namespace: Namespace(
        chains: const [HostedBridgeProtocol.chain],
        accounts: [account],
        methods: methods.toList(growable: false),
        events: const [],
      ),
    },
    sessionProperties: HostedBridgeProtocol.sessionProperties,
  );

  Future<void> reject(int id) => _kit.reject(
    id: id,
    reason: const ReownSignError(code: 5000, message: 'Connection declined.'),
  );

  Future<void> disconnect(String topic) => _kit.disconnect(
    topic: topic,
    reason: const ReownSignError(code: 6000, message: 'Wallet disconnected.'),
  );

  Future<void> respond(
    SessionRequest request,
    JsonRpcResponse<Object?> response,
  ) => _kit.respond(topic: request.topic, response: response);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _kit.onSessionProposal.unsubscribe(_proposal);
    _kit.onSessionRequest.unsubscribe(_request);
    _kit.onSessionDelete.unsubscribe(_delete);
    _kit.onSessionExpire.unsubscribe(_expire);
    _kit.core.relayClient.onRelayClientConnect.unsubscribe(_connect);
    _kit.core.heartbeat.stop();
    await _kit.core.relayClient.disconnect();
    await _kit.core.connectivity.dispose();
  }

  Future<void> resume() async {
    if (!_closed && !_kit.core.relayClient.isConnected) {
      await _kit.core.relayClient.connect();
    }
  }
}

/// Install storage before Core constructs the stores that retain references to
/// it. Both Core storage roles use the encrypted, fail-closed implementation.
final class _EncryptedCore extends ReownCore {
  _EncryptedCore(this._store)
    : super(projectId: HostedBridgeProtocol.projectId);

  final HostedBridgeStore _store;

  @override
  IStore<Map<String, dynamic>> get storage => _store;

  @override
  set storage(IStore<Map<String, dynamic>> _) {}

  @override
  IStore<Map<String, dynamic>> get secureStorage => _store;

  @override
  set secureStorage(IStore<Map<String, dynamic>> _) {}
}
