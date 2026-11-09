import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reown_core/reown_core.dart';
import 'package:reown_sign/reown_sign.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter_webrgb.dart';

import '../../../../core/core.dart';
import '../../../wallet/domain/models/models.dart';
import '../../data/hosted_bridge_protocol.dart';
import '../../data/hosted_bridge_relay.dart';
import '../../data/hosted_bridge_store.dart';

final hostedBridgeControllerProvider = Provider<HostedBridgeController?>((ref) {
  const requested = bool.fromEnvironment(UtexoDevSignetPolicy.buildFlag);
  if (!kDebugMode ||
      !requested ||
      !ref.read(walletServiceConfigurationProvider).devBridgeEnabled) {
    return null;
  }
  final controller = HostedBridgeController(<T>(
    walletId,
    operation,
    authorize,
    allowMutation,
  ) async {
    final repository = await ref.read(walletRepositoryProvider.future);
    final result = await repository.withHostedBridgeLease<T>(
      walletId,
      (engine) => engine.withHostedBridgeWallet(operation),
      authorize,
      allowMutation: allowMutation,
    );
    return switch (result) {
      AppSuccess<T>(:final value) => value,
      AppFailureResult<T>(:final failure) => throw AppFailureException(failure),
    };
  }, clock: ref.read(utcClockProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

final hostedBridgeSetupActionsProvider = Provider(HostedBridgeSetupActions.new);

final class HostedBridgeSetupActions {
  HostedBridgeSetupActions(this._ref);

  final Ref _ref;

  Future<AppResult<RgbWalletSetupStatus>> status() async =>
      (await _ref.read(walletRepositoryProvider.future)).rgbWalletSetupStatus();

  Future<AppResult<RgbWalletSetupReview>> prepare() async =>
      (await _ref.read(walletRepositoryProvider.future))
          .prepareRgbWalletSetup();

  Future<AppResult<RgbWalletSetupStatus>> confirm(
    RgbWalletSetupReview review,
  ) async =>
      (await _ref.read(walletRepositoryProvider.future))
          .confirmRgbWalletSetup(review);

  Future<void> cancel(RgbWalletSetupReview review) async =>
      (await _ref.read(walletRepositoryProvider.future))
          .cancelRgbWalletSetup(review);
}

typedef HostedBridgeWalletLease = Future<T> Function<T>(
  String walletId,
  Future<T> Function(RgbLibWallet wallet) operation,
  void Function() authorize,
  bool allowMutation,
);

final class HostedBridgeOutputsRequired implements Exception {
  const HostedBridgeOutputsRequired();
}

/// Consent is shown by the app root while this exact request has authority.
final class HostedBridgeApproval {
  HostedBridgeApproval._(this.operation, this.expiry);

  final WebRgbApproval? operation;
  final int expiry;
  final _answer = Completer<bool>();

  void resolve(bool approved) {
    if (!_answer.isCompleted) _answer.complete(approved);
  }
}

/// Wallet-owned admission and response delivery for the pinned Dev peer.
final class HostedBridgeController extends ChangeNotifier {
  HostedBridgeController(
    this._lease, {
    HostedBridgeStore? store,
    DateTime Function()? clock,
  }) : _store = store ?? HostedBridgeStore(),
       _clock = clock ?? DateTime.now;

  final HostedBridgeWalletLease _lease;
  final HostedBridgeStore _store;
  final DateTime Function() _clock;
  static const maxLinkLength = HostedBridgeProtocol.maxLinkLength;
  static const _grantKey = 'aster.bridge.grant';
  static const _requestKey = 'aster.bridge.requests';
  static const _burnCommandsPrefix = 'aster.bridge.burns.';
  static const _trustedTopicsPrefix = 'aster.bridge.topics.';
  static const _maxRequests = 128;
  static const _requestLifetime = 300;

  HostedBridgeRelay? _relay;
  Future<void>? _starting;
  bool _relayReady = false;
  bool _disposed = false;
  bool _proposing = false;
  bool _revoking = false;
  bool _bridgeAvailable = false;
  bool _storageFailed = false;
  bool _restoring = false;
  Timer? _burnCleanup;
  String? _walletId;
  Object? _securityGeneration;
  var _epoch = 0;
  var _queue = Future<void>.value();
  ({String topic, int expiry})? _pairing;
  Completer<bool>? _pairCompletion;
  ({String pairingTopic, String peerKey, Set<String> methods})? _settling;
  _BridgeGrant? _grant;
  RgbLibWallet? _routerWallet;
  WebRgbWalletConnectSession? _router;
  HostedBridgeApproval? _approval;
  final _raw = <String, _BridgeRequestIdentity>{};
  final _queued = <String>{};
  final _responses =
      <
        String,
        ({_BridgeRequestIdentity identity, JsonRpcResponse<Object?> response})
      >{};

  bool get available => _bridgeAvailable && !_storageFailed;
  bool get connected => _grant != null;
  HostedBridgeApproval? get approval => _approval;
  int get _now => _clock().millisecondsSinceEpoch ~/ 1000;

  Future<List<HostedBridgeBurn>> savedBurns() async {
    final epoch = _epoch;
    _assertOwner(epoch);
    if (!available) throw StateError('Bridge wallet is unavailable.');
    final topics =
        _store.get('$_trustedTopicsPrefix$_walletId')?.keys ??
        const Iterable<String>.empty();
    return _withWallet(epoch, (wallet) async {
      final byTxid = <String, HostedBridgeBurn>{};
      for (final topic in topics) {
        if (!HostedBridgeProtocol.topicPattern.hasMatch(topic)) continue;
        final burns = await WebRgbWalletConnectSession.listHostedDevBridgeBurns(
          wallet: wallet,
          topic: topic,
          assertAuthorized: () => _assertOwner(epoch),
        );
        for (final burn in burns) {
          if (burn.txid case final String txid) {
            byTxid.putIfAbsent(
              txid,
              () =>
                  HostedBridgeBurn._(topic, txid, burn.amountBaseUnits, epoch),
            );
          }
        }
      }
      _assertOwner(epoch);
      return List.unmodifiable(byTxid.values);
    });
  }

  Future<HostedBridgeBurnExport?> exportBurn(
    HostedBridgeBurn burn,
    SecurityController security,
  ) async {
    _assertOwner(burn._epoch);
    final walletId = _walletId!;
    const purpose = SecurityPurpose.exportBurnProof;
    final grant = await security.authorize(purpose, walletId: walletId);
    if (grant == null) return null;
    if (_walletId != walletId ||
        !security.consume(grant, purpose, walletId: walletId)) {
      return null;
    }
    final epoch = _epoch;
    final package = await _withWallet(epoch, (wallet) async {
      return WebRgbWalletConnectSession.exportHostedDevBridgeBurn(
        wallet: wallet,
        topic: burn._topic,
        txid: burn.txid,
        assertAuthorized: () => _assertOwner(epoch),
      );
    });
    _assertOwner(epoch);
    return HostedBridgeBurnExport._(burn.txid, package, epoch);
  }

  bool canShare(HostedBridgeBurnExport export) =>
      !_disposed && _walletId != null && export._epoch == _epoch;

  bool ownsBurn(HostedBridgeBurn burn) =>
      available && _walletId != null && burn._epoch == _epoch;

  void updateOwner({required String? walletId, required Object generation}) {
    if (_disposed ||
        (_walletId == walletId && _securityGeneration == generation)) {
      return;
    }
    _epoch++;
    _burnCleanup?.cancel();
    _walletId = walletId;
    _securityGeneration = generation;
    _bridgeAvailable = false;
    _grant = null;
    _pairing = null;
    _settling = null;
    _finishPair(false);
    _raw.clear();
    _responses.clear();
    _approval?.resolve(false);
    _closeRouter();
    notifyListeners();
    if (walletId != null) unawaited(_restore(_epoch));
  }

  Future<void> _restore(int epoch) async {
    if (_restoring) return;
    _restoring = true;
    try {
      final binding = await _withWallet(
        epoch,
        (wallet) async => (
          supported: wallet.supportsHostedDevBridge,
          account: 'rgb:utexo:${(await wallet.getWalletIdentity()).id}',
        ),
      );
      _assertOwner(epoch);
      _bridgeAvailable = binding.supported;
      if (!_bridgeAvailable) return;
      await _initializeStore();
      final saved = _readGrant();
      if (saved == null ||
          saved.expiry <= _now ||
          saved.walletId != _walletId ||
          saved.account != binding.account) {
        await _recoverUnsubmittedBurns(epoch);
        return;
      }
      await _startRelay();
      await _relay!.resume();
      _assertOwner(epoch);
      if (_validSession(saved) != null) {
        _grant = saved;
        await _recoverUnsubmittedBurns(epoch);
        _assertOwner(epoch);
        _drain();
      } else {
        await _deleteGrant();
        await _recoverUnsubmittedBurns(epoch);
      }
    } on Object {
      // The Bridge screen can retry an explicit connection. No startup toast
      // or restored request can authorize a wallet operation after failure.
    } finally {
      _restoring = false;
      if (!_disposed) {
        notifyListeners();
        if (epoch != _epoch && _walletId != null) unawaited(_restore(_epoch));
      }
    }
  }

  Future<void> _initializeStore() async {
    try {
      await _store.init();
    } on Object {
      _storageFailed = true;
      rethrow;
    }
  }

  _BridgeGrant? _readGrant() {
    final raw = _store.get(_grantKey);
    if (raw == null) return null;
    final grant = _BridgeGrant.parse(raw);
    if (grant == null) {
      _storageFailed = true;
      throw const FormatException('Invalid bridge grant.');
    }
    return grant;
  }

  Future<void> _startRelay() async {
    await _initializeStore();
    await (_starting ??= _openRelay());
  }

  Future<void> _openRelay() async {
    final relay = HostedBridgeRelay(_store)
      ..onProposal = ((event) => unawaited(_onProposal(event)))
      ..onRequest = _enqueue
      ..onRawRequest = _captureRequest
      ..onReconnect = _drain
      ..onRemoved = ((topic) => unawaited(_removed(topic)));
    _relay = relay;
    try {
      await relay.start();
      if (!_disposed) _relayReady = true;
    } on Object {
      _starting = null;
      rethrow;
    }
  }

  /// A QR/clipboard link opens only the proposal route. Consent is separate.
  Future<void> pair(String input) async {
    final epoch = _epoch;
    _assertOwner(epoch);
    if (!available ||
        _grant != null ||
        _proposing ||
        (_pairing?.expiry ?? 0) > _now) {
      throw StateError('Bridge connection is busy.');
    }
    final link = HostedBridgeProtocol.pairingLink(input, now: _now);
    if (link == null) {
      throw const FormatException('Invalid WalletConnect link.');
    }
    final topic = link.path.split('@').first;
    final linkExpiry = int.tryParse(
      link.queryParameters['expiryTimestamp'] ?? '',
    );
    _pairing = (
      topic: topic,
      expiry: math.min(
        linkExpiry ?? _now + _requestLifetime,
        _now + _requestLifetime,
      ),
    );
    final completion = Completer<bool>();
    _pairCompletion = completion;
    try {
      if (!await _withWallet(
        epoch,
        (wallet) => wallet.hostedDevBridgeBlindReceiveReady(),
      )) {
        throw const HostedBridgeOutputsRequired();
      }
      await _startRelay();
      await _relay!.resume();
      _assertOwner(epoch);
      // Allow only one relay principal. Discard any stale or unowned SDK
      // session before pairing so a colliding JSON-RPC id cannot be routed.
      for (final activeTopic in _relay!.sessions.keys.toList()) {
        await _relay!.disconnect(activeTopic);
        _assertOwner(epoch);
      }
      if (_readGrant() != null) await _deleteGrant();
      await _recoverUnsubmittedBurns(epoch);
      _assertOwner(epoch);
      await _relay!.pair(link);
      _assertOwner(epoch);
      if (!await completion.future.timeout(
        const Duration(seconds: 75),
        onTimeout: () => false,
      )) {
        throw StateError('Dev Bridge did not complete the connection.');
      }
    } finally {
      if (identical(_pairCompletion, completion)) {
        _pairCompletion = null;
        _pairing = null;
        if (_grant == null) _approval?.resolve(false);
      }
    }
  }

  void _finishPair(bool accepted) {
    final completion = _pairCompletion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(accepted);
    }
  }

  Future<void> _onProposal(SessionProposalEvent event) async {
    final epoch = _epoch;
    final proposal = event.params;
    final pairing = _pairing;
    final methods = HostedBridgeProtocol.negotiate(proposal);
    final relay = _relay!;
    if (pairing == null ||
        pairing.topic != proposal.pairingTopic ||
        _proposing ||
        connected ||
        !available ||
        event.id != proposal.id ||
        methods == null ||
        !HostedBridgeProtocol.verified(event.verifyContext) ||
        proposal.expiry <= _now ||
        pairing.expiry <= _now) {
      await _ignore(() => relay.reject(event.id));
      if (!_proposing && pairing?.topic == proposal.pairingTopic) {
        _finishPair(false);
      }
      return;
    }
    _proposing = true;
    _pairing = null;
    String? approvedTopic;
    final completion = _pairCompletion;
    var accepted = false;
    try {
      final account = await _withWallet(epoch, (wallet) async {
        if (!await wallet.hostedDevBridgeBlindReceiveReady()) {
          throw StateError('Prepare a confirmed RGB output before connecting.');
        }
        return 'rgb:utexo:${(await wallet.getWalletIdentity()).id}';
      });
      final expiry = math.min(pairing.expiry, proposal.expiry);
      if (!await _confirm(epoch, null, expiry)) {
        await _ignore(() => relay.reject(event.id));
        return;
      }
      _assertOwner(epoch);
      _settling = (
        pairingTopic: pairing.topic,
        peerKey: proposal.proposer.publicKey,
        methods: methods,
      );
      final approved = await relay.approve(event.id, account, methods);
      approvedTopic = approved.topic;
      final session = approved.session ?? relay.sessions[approved.topic];
      _assertOwner(epoch);
      if (!identical(_pairCompletion, completion) || expiry <= _now) {
        throw StateError('Bridge proposal expired.');
      }
      if (session == null) throw StateError('Bridge session is missing.');
      final grant = _BridgeGrant(
        topic: approved.topic,
        walletId: _walletId!,
        account: account,
        peerKey: proposal.proposer.publicKey,
        pairingTopic: proposal.pairingTopic,
        expiry: session.expiry,
        methods: methods,
      );
      if (_validSession(grant) == null) {
        throw StateError('Bridge session changed.');
      }
      final historyKey = '$_trustedTopicsPrefix${grant.walletId}';
      final topics = _store.get(historyKey) ?? <String, dynamic>{};
      if (!topics.containsKey(grant.topic) && topics.length >= _maxRequests) {
        throw StateError('Bridge connection history is full.');
      }
      topics[grant.topic] = true;
      await _store.set(historyKey, topics);
      _assertOwner(epoch);
      await _store.set(_grantKey, grant.toJson());
      _assertOwner(epoch);
      if (!identical(_pairCompletion, completion) || expiry <= _now) {
        throw StateError('Bridge proposal expired.');
      }
      _grant = grant;
      accepted = true;
      notifyListeners();
      _drain();
    } on Object {
      if (approvedTopic != null) {
        final topic = approvedTopic;
        if (_store.get(_grantKey)?['topic'] == topic) {
          await _ignore(_deleteGrant);
        }
        await _ignore(() => relay.disconnect(topic));
      } else {
        await _ignore(() => relay.reject(event.id));
      }
    } finally {
      _proposing = false;
      _settling = null;
      if (identical(_pairCompletion, completion)) _finishPair(accepted);
    }
  }

  void _captureRequest(
    String topic,
    int id,
    String chain,
    String method,
    Object? params,
    Object? expiry,
  ) {
    final grant = _grant;
    final settling = _settling;
    final session = settling != null ? _relay?.sessions[topic] : null;
    final scoped = grant != null
        ? topic == grant.topic && grant.methods.contains(method)
        : settling != null &&
              session != null &&
              session.pairingTopic == settling.pairingTopic &&
              session.peer.publicKey == settling.peerKey &&
              settling.methods.contains(method);
    if (!scoped ||
        id < 0 ||
        id > 9007199254740991 ||
        (expiry != null && expiry is! int)) {
      return;
    }
    final digest = HostedBridgeProtocol.requestDigest(chain, method, params);
    if (digest == null) return;
    final now = _now;
    _raw.removeWhere((_, value) => value.expiry <= now);
    final key = '$topic:$id';
    final deadline = math.min(
      expiry is int ? expiry : now + _requestLifetime,
      now + _requestLifetime,
    );
    if (deadline <= now ||
        (_raw.length >= _maxRequests && !_raw.containsKey(key))) {
      return;
    }
    final previous = _raw[key];
    if (previous != null && previous.digest != digest) {
      _raw[key] = _BridgeRequestIdentity('', previous.expiry);
      return;
    }
    _raw[key] = _BridgeRequestIdentity(
      digest,
      math.min(previous?.expiry ?? deadline, deadline),
    );
  }

  void _drain() {
    if (!_relayReady || _disposed || _grant == null) return;
    for (final request in _relay!.pending.values) {
      _enqueue(request);
    }
  }

  void _enqueue(SessionRequest request) {
    if (_disposed || !_relayReady || (_proposing && _grant == null)) return;
    final key = '${request.topic}:${request.id}';
    if (_queued.length >= 24 || !_queued.add(key)) return;
    final epoch = _epoch;
    _queue = _queue
        .then((_) => _dispatch(request, key, epoch))
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _queued.remove(key));
  }

  Future<void> _dispatch(SessionRequest request, String key, int epoch) async {
    final grant = _grant;
    final digest = HostedBridgeProtocol.requestDigest(
      request.chainId,
      request.method,
      request.params,
    );
    if (grant == null ||
        digest == null ||
        request.topic != grant.topic ||
        !grant.methods.contains(request.method) ||
        request.transportType != TransportType.relay ||
        !HostedBridgeProtocol.acceptsRequestVerification(
          request.verifyContext,
        ) ||
        _validSession(grant) == null) {
      await _deny(request);
      return;
    }
    try {
      _assertOwner(epoch);
      final seen = _raw[key];
      final protected = HostedBridgeProtocol.consentMethods.contains(
        request.method,
      );
      final document = _store.get(_requestKey) ?? <String, dynamic>{};
      document.removeWhere(
        (_, value) =>
            value is Map &&
            value['expiry'] is int &&
            (value['expiry'] as int) <= _now,
      );
      final storedValue = document[key];
      final prior = _BridgeRequestIdentity.parse(storedValue);
      if ((storedValue != null && prior == null) ||
          (prior != null && prior.digest != digest) ||
          (seen != null && seen.digest != digest)) {
        await _deny(request, code: -32602);
        return;
      }
      final identity = prior ?? seen;
      if (identity == null || identity.expiry <= _now) {
        await _deny(request);
        return;
      }
      void authorize() {
        _assertOwner(epoch);
        if (!identical(grant, _grant) ||
            identity.expiry <= _now ||
            _validSession(grant) == null ||
            !_pendingMatches(request, digest)) {
          throw StateError('Bridge request is no longer authorized.');
        }
      }

      final cached = _responses[key];
      if (cached != null && cached.identity.digest == digest) {
        authorize();
        await _relay!.respond(request, cached.response);
        _responses.remove(key);
        return;
      }
      authorize();
      if (protected && prior == null) {
        if (document.length >= _maxRequests) {
          await _deny(request);
          return;
        }
        document[key] = identity.toJson();
        if (request.method == 'rgb_burnAsset') {
          final commandsKey = '$_burnCommandsPrefix${grant.walletId}';
          final commands = _store.get(commandsKey) ?? <String, dynamic>{};
          if (!commands.containsKey(key) && commands.length >= _maxRequests) {
            await _deny(request);
            return;
          }
          commands[key] = <String, Object?>{
            'expiry': identity.expiry,
            'params': request.params,
            'digest': digest,
          };
          await _store.set(commandsKey, commands);
          authorize();
          _scheduleBurnCleanup(epoch);
        }
        await _store.set(_requestKey, document);
        authorize();
      }
      final result = await _withWallet(
        epoch,
        (wallet) async {
          authorize();
          final account = 'rgb:utexo:${(await wallet.getWalletIdentity()).id}';
          if (account != grant.account) {
            throw StateError('Bridge wallet identity changed.');
          }
          if (!identical(wallet, _routerWallet)) {
            _closeRouter();
            _routerWallet = wallet;
            _router = WebRgbWalletConnectSession.hostedDev(
              wallet: wallet,
              grant: grant.sdkGrant,
              currentGrant: () {
                try {
                  _authorizeRequest?.call();
                  return _grant == grant &&
                          _walletId == grant.walletId &&
                          _validSession(grant) != null
                      ? grant.sdkGrant
                      : null;
                } on Object {
                  return null;
                }
              },
              confirm: (operation) =>
                  _confirm(_epoch, operation, identity.expiry),
            );
          }
          // The confirmation closure belongs to the currently executing frame.
          _approvalDeadline = identity.expiry;
          _authorizeRequest = authorize;
          try {
            return await _router!.handle(
              id: request.id,
              topic: request.topic,
              chainId: request.chainId,
              method: request.method,
              params: request.params as List<Object?>,
              expiry: identity.expiry,
              recoveryOnly: protected && prior != null,
            );
          } finally {
            _authorizeRequest = null;
            _approvalDeadline = null;
          }
        },
        authorize,
        prior == null &&
            const {
              'rgb_blindReceive',
              'rgb_burnAsset',
            }.contains(request.method),
      );
      authorize();
      if (request.method == 'rgb_burnAsset' && result.containsKey('result')) {
        await _forgetBurnCommand(grant.walletId, key);
        authorize();
      }
      final response = _wireResponse(request.id, result);
      _responses.removeWhere((_, value) => value.identity.expiry <= _now);
      if (_responses.length < 24) {
        _responses[key] = (identity: identity, response: response);
      }
      await _relay!.respond(request, response);
      _responses.remove(key);
    } on Object {
      // A write may already have happened. Keep its durable envelope for a
      // read-only recovery, and never manufacture a success or retry a send.
      if (!_responses.containsKey(key)) await _deny(request);
    }
  }

  int? _approvalDeadline;
  void Function()? _authorizeRequest;

  Future<bool> _confirm(
    int epoch,
    WebRgbApproval? operation,
    int deadline,
  ) async {
    _assertOwner(epoch);
    if (operation != null) {
      _authorizeRequest?.call();
      deadline = _approvalDeadline ?? 0;
    }
    final seconds = math.min(45, deadline - _now);
    if (_approval != null || seconds <= 0) return false;
    final prompt = HostedBridgeApproval._(operation, _now + seconds);
    _approval = prompt;
    notifyListeners();
    try {
      final approved = await prompt._answer.future.timeout(
        Duration(seconds: seconds),
        onTimeout: () => false,
      );
      _assertOwner(epoch);
      if (operation != null) _authorizeRequest?.call();
      return approved && prompt.expiry > _now;
    } finally {
      if (identical(_approval, prompt)) {
        _approval = null;
        if (!_disposed) notifyListeners();
      }
    }
  }

  SessionData? _validSession(_BridgeGrant grant) {
    if (!_relayReady || grant.expiry <= _now || _relay!.sessions.length != 1) {
      return null;
    }
    final session = _relay!.sessions[grant.topic];
    final namespace = session?.namespaces[HostedBridgeProtocol.namespace];
    if (session == null ||
        namespace == null ||
        session.transportType != TransportType.relay ||
        session.expiry != grant.expiry ||
        session.pairingTopic != grant.pairingTopic ||
        session.sessionProperties?['webrgb'] != HostedBridgeProtocol.profile ||
        session.peer.publicKey != grant.peerKey ||
        !HostedBridgeProtocol.matchesOrigin(session.peer.metadata.url) ||
        session.namespaces.length != 1 ||
        namespace.accounts.length != 1 ||
        namespace.accounts.single != grant.account ||
        namespace.events.isNotEmpty ||
        namespace.methods.length != grant.methods.length ||
        !grant.methods.containsAll(namespace.methods)) {
      return null;
    }
    return session;
  }

  bool _pendingMatches(SessionRequest request, String? digest) {
    final pending = _relay?.pending[request.id.toString()];
    return pending != null &&
        pending.topic == request.topic &&
        pending.method == request.method &&
        pending.chainId == request.chainId &&
        HostedBridgeProtocol.requestDigest(
              pending.chainId,
              pending.method,
              pending.params,
            ) ==
            digest;
  }

  Future<void> _deny(SessionRequest request, {int code = 3001}) async {
    final digest = HostedBridgeProtocol.requestDigest(
      request.chainId,
      request.method,
      request.params,
    );
    if (!_pendingMatches(request, digest)) return;
    await _ignore(
      () => _relay!.respond(
        request,
        JsonRpcResponse<Object?>(
          id: request.id,
          error: JsonRpcError(
            code: code,
            message: 'Bridge request could not be authorized.',
          ),
        ),
      ),
    );
  }

  JsonRpcResponse<Object?> _wireResponse(int id, Map<String, Object?> result) {
    if (result.containsKey('result')) {
      // Reown's wallet API branches on non-null results. WebRGB's enable
      // handshake ignores the result body, so acknowledge it explicitly.
      return JsonRpcResponse(id: id, result: result['result'] ?? true);
    }
    final error = result['error'];
    final code = error is Map && error['code'] is int
        ? error['code'] as int
        : -32000;
    final message = error is Map && error['message'] is String
        ? error['message'] as String
        : 'Wallet request failed.';
    return JsonRpcResponse(
      id: id,
      error: JsonRpcError(code: code, message: message),
    );
  }

  Future<void> disconnect() async {
    final grant = _grant;
    if (grant == null || _revoking) return;
    _revoking = true;
    _grant = null;
    _approval?.resolve(false);
    _closeRouter();
    notifyListeners();
    try {
      await _deleteGrant();
      await _relay!.disconnect(grant.topic);
    } finally {
      _revoking = false;
      if (!_disposed && _walletId != null) {
        await _ignore(() => _recoverUnsubmittedBurns(_epoch));
      }
    }
  }

  Future<void> _removed(String topic) async {
    if (_grant?.topic == topic) {
      _grant = null;
      _approval?.resolve(false);
      _closeRouter();
      if (!_disposed) notifyListeners();
    }
    if (_store.get(_grantKey)?['topic'] == topic) await _ignore(_deleteGrant);
    if (!_disposed && _walletId != null && !_revoking) {
      await _ignore(() => _recoverUnsubmittedBurns(_epoch));
    }
  }

  Future<void> _forgetBurnCommand(String walletId, String command) async {
    final storageKey = '$_burnCommandsPrefix$walletId';
    final entries = _store.get(storageKey);
    if (entries != null && entries.remove(command) != null) {
      await _store.set(storageKey, entries);
    }
  }

  /// The native receipt decides whether rollback is safe. An expired relay
  /// request, a revoked grant, or a new peer can never authorize a broadcast.
  Future<void> _recoverUnsubmittedBurns(int epoch) async {
    _assertOwner(epoch);
    final walletId = _walletId!;
    final storageKey = '$_burnCommandsPrefix$walletId';
    final entries = _store.get(storageKey);
    if (entries == null || entries.isEmpty) return;
    try {
      await _withWallet(epoch, (wallet) async {
        for (final entry in entries.entries) {
          _assertOwner(epoch);
          final fields = entry.key.split(':');
          final id = fields.length == 2 ? int.tryParse(fields[1]) : null;
          final command = entry.value;
          if (id == null ||
              !HostedBridgeProtocol.topicPattern.hasMatch(fields.first) ||
              command is! Map ||
              command['params'] is! List ||
              command['expiry'] is! int) {
            continue;
          }
          final topic = fields.first;
          final expiry = command['expiry'] as int;
          final params = (command['params'] as List).cast<Object?>();
          if ((_grant?.topic == topic && expiry > _now) ||
              HostedBridgeProtocol.requestDigest(
                    HostedBridgeProtocol.chain,
                    'rgb_burnAsset',
                    params,
                  ) !=
                  command['digest']) {
            continue;
          }
          if (await WebRgbWalletConnectSession.cancelUnsubmittedHostedDevBurn(
            wallet: wallet,
            topic: topic,
            id: id,
            expiry: expiry,
            params: params,
            assertAuthorized: () => _assertOwner(epoch),
          )) {
            _assertOwner(epoch);
            await _forgetBurnCommand(walletId, entry.key);
          }
        }
      });
    } finally {
      if (!_disposed && epoch == _epoch) _scheduleBurnCleanup(epoch);
    }
  }

  void _scheduleBurnCleanup(int epoch) {
    _burnCleanup?.cancel();
    final entries = _store.get('$_burnCommandsPrefix$_walletId');
    if (entries == null) return;
    final now = _now;
    final next = entries.values
        .whereType<Map<Object?, Object?>>()
        .map((command) => command['expiry'])
        .whereType<int>()
        .where((expiry) => expiry > now)
        .fold<int?>(
          null,
          (next, expiry) => next == null ? expiry : math.min(next, expiry),
        );
    if (next != null) {
      _burnCleanup = Timer(Duration(seconds: next - now + 1), () {
        unawaited(_ignore(() => _recoverUnsubmittedBurns(epoch)));
      });
    }
  }

  Future<void> _deleteGrant() async {
    try {
      await _store.delete(_grantKey);
    } on Object {
      _storageFailed = true;
      rethrow;
    }
  }

  Future<T> _withWallet<T>(
    int epoch,
    Future<T> Function(RgbLibWallet) operation, [
    void Function()? authorize,
    bool allowMutation = false,
  ]) {
    _assertOwner(epoch);
    return _lease(
      _walletId!,
      operation,
      authorize ?? () => _assertOwner(epoch),
      allowMutation,
    );
  }

  void _assertOwner(int epoch) {
    if (_disposed ||
        _storageFailed ||
        _revoking ||
        epoch != _epoch ||
        _walletId == null) {
      throw StateError('Bridge wallet is unavailable.');
    }
  }

  void _closeRouter() {
    _router?.dispose();
    _router = null;
    _routerWallet = null;
  }

  static Future<void> _ignore(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object {
      // A failed relay response or cleanup never extends local authority.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _burnCleanup?.cancel();
    _epoch++;
    _grant = null;
    _finishPair(false);
    _approval?.resolve(false);
    _closeRouter();
    final relay = _relay;
    if (relay != null) unawaited(_ignore(relay.close));
    super.dispose();
  }
}

final class _BridgeRequestIdentity {
  const _BridgeRequestIdentity(this.digest, this.expiry);

  final String digest;
  final int expiry;

  Map<String, Object?> toJson() => {'digest': digest, 'expiry': expiry};

  static _BridgeRequestIdentity? parse(Object? json) {
    if (json is! Map || json['digest'] is! String || json['expiry'] is! int) {
      return null;
    }
    final digest = json['digest'] as String;
    if (!HostedBridgeProtocol.topicPattern.hasMatch(digest)) return null;
    return _BridgeRequestIdentity(digest, json['expiry'] as int);
  }
}

final class HostedBridgeBurn {
  const HostedBridgeBurn._(
    this._topic,
    this.txid,
    this.amountBaseUnits,
    this._epoch,
  );

  final String _topic;
  final String txid;
  final String? amountBaseUnits;
  final int _epoch;
}

final class HostedBridgeBurnExport {
  const HostedBridgeBurnExport._(this.txid, this.package, this._epoch);

  final String txid;
  final Map<String, Object?> package;
  final int _epoch;
}

final class _BridgeGrant {
  const _BridgeGrant({
    required this.topic,
    required this.walletId,
    required this.account,
    required this.peerKey,
    required this.pairingTopic,
    required this.expiry,
    required this.methods,
  });

  final String topic;
  final String walletId;
  final String account;
  final String peerKey;
  final String pairingTopic;
  final int expiry;
  final Set<String> methods;

  WebRgbWalletConnectGrant get sdkGrant => WebRgbWalletConnectGrant(
    topic: topic,
    origin: HostedBridgeProtocol.origin,
    network: 'utexo',
    account: account,
    expiry: expiry,
    methods: methods,
  );

  Map<String, Object?> toJson() => {
    'topic': topic,
    'walletId': walletId,
    'account': account,
    'peerKey': peerKey,
    'pairingTopic': pairingTopic,
    'expiry': expiry,
    'methods': methods.toList(),
  };

  static _BridgeGrant? parse(Map<String, Object?> json) {
    if (json['topic'] is! String ||
        json['walletId'] is! String ||
        json['account'] is! String ||
        json['peerKey'] is! String ||
        json['pairingTopic'] is! String ||
        json['expiry'] is! int ||
        json['methods'] is! List) {
      return null;
    }
    final methods = json['methods']! as List;
    final topic = json['topic']! as String;
    final peerKey = json['peerKey']! as String;
    final pairing = json['pairingTopic']! as String;
    final account = json['account']! as String;
    final walletId = json['walletId']! as String;
    if (![
          topic,
          peerKey,
          pairing,
        ].every(HostedBridgeProtocol.topicPattern.hasMatch) ||
        !RegExp(r'^rgb:utexo:[a-f0-9]{64}$').hasMatch(account) ||
        !RegExp(r'^[a-zA-Z0-9._:-]{1,128}$').hasMatch(walletId) ||
        methods.any(
          (value) => !HostedBridgeProtocol.supportedMethods.contains(value),
        ) ||
        !methods.toSet().containsAll(HostedBridgeProtocol.requiredMethods)) {
      return null;
    }
    return _BridgeGrant(
      topic: topic,
      walletId: walletId,
      account: account,
      peerKey: peerKey,
      pairingTopic: pairing,
      expiry: json['expiry']! as int,
      methods: Set.unmodifiable(methods.cast<String>()),
    );
  }
}
