import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:reown_core/reown_core.dart';
import 'package:reown_sign/reown_sign.dart';

/// The only peer, chain and WebRGB protocol admitted by the Dev build.
abstract final class HostedBridgeProtocol {
  static const origin = 'https://dev.mint.utexo.com';
  static const projectId = 'f8087f367176ba407873e1c9e33051d7';
  static const chain = 'rgb:utexo';
  static const profile = 'webrgb:1';
  static const namespace = 'rgb';
  static const maxLinkLength = 2048;
  static const requiredMethods = {
    'rgb_enable',
    'rgb_getInfo',
    'rgb_getAddress',
    'rgb_blindReceive',
  };
  static const supportedMethods = {
    ...requiredMethods,
    'rgb_listAssets',
    'rgb_getAssetBalance',
    'rgb_listTransfers',
    'rgb_getTransferStatus',
    'rgb_decodeRgbInvoice',
    'rgb_burnAsset',
    'rgb_getConsignment',
  };
  static const consentMethods = {
    'rgb_blindReceive',
    'rgb_burnAsset',
    'rgb_getConsignment',
  };
  static const sessionProperties = {'webrgb': profile};

  static final topicPattern = RegExp(r'^[a-f0-9]{64}$');
  static final _pairingPattern = RegExp(r'^wc:([a-f0-9]{64})@2\?([^#\s]+)$');

  static Uri? pairingLink(String raw, {required int now}) {
    if (raw.length > maxLinkLength) return null;
    final link = raw.trim().replaceFirst(
      RegExp(r'^wc:', caseSensitive: false),
      'wc:',
    );
    final match = _pairingPattern.firstMatch(link);
    if (match == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    try {
      final pairs = uri.queryParametersAll;
      if (pairs.entries.any(
        (entry) =>
            entry.value.length != 1 ||
            !const {
              'relay-protocol',
              'relay-data',
              'symKey',
              'expiryTimestamp',
            }.contains(entry.key),
      )) {
        return null;
      }
      final query = uri.queryParameters;
      final expiry = query['expiryTimestamp'];
      if (query['relay-protocol'] != 'irn' ||
          !topicPattern.hasMatch(query['symKey'] ?? '') ||
          (expiry != null &&
              (!RegExp(r'^[0-9]{1,12}$').hasMatch(expiry) ||
                  int.parse(expiry) <= now))) {
        return null;
      }
      return uri;
    } on FormatException {
      return null;
    }
  }

  static bool matchesOrigin(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        uri.host == 'dev.mint.utexo.com' &&
        uri.port == 443;
  }

  static bool verified(VerifyContext? context) =>
      context != null &&
      context.validation == Validation.VALID &&
      context.isScam != true &&
      matchesOrigin(context.origin);

  // An already verified, topic-bound session may carry requests without new
  // attestation. Any affirmative negative or different origin closes it.
  static bool acceptsRequestVerification(VerifyContext context) =>
      verified(context) ||
      (context.validation == Validation.UNKNOWN &&
          context.isScam != true &&
          (context.origin.isEmpty || matchesOrigin(context.origin)));

  static Set<String>? negotiate(ProposalData proposal) {
    if (proposal.sessionProperties?['webrgb'] != profile ||
        !matchesOrigin(proposal.proposer.metadata.url) ||
        !topicPattern.hasMatch(proposal.proposer.publicKey) ||
        proposal.requests != null) {
      return null;
    }
    final mandatory = <String>{};
    final optional = <String>{};
    for (final entry in proposal.requiredNamespaces.entries) {
      if (!_namespaceForChain(entry.key, entry.value) ||
          entry.value.events.isNotEmpty ||
          !supportedMethods.containsAll(entry.value.methods)) {
        return null;
      }
      mandatory.addAll(entry.value.methods);
    }
    if (!mandatory.containsAll(requiredMethods)) return null;
    for (final entry in proposal.optionalNamespaces.entries) {
      if (_namespaceForChain(entry.key, entry.value)) {
        optional.addAll(entry.value.methods.where(supportedMethods.contains));
      }
    }
    return Set.unmodifiable({...mandatory, ...optional});
  }

  static bool _namespaceForChain(String key, RequiredNamespace value) =>
      (key == namespace || key == chain) &&
      (value.chains ?? (key == chain ? [chain] : const <String>[])).length ==
          1 &&
      (value.chains ?? [chain]).single == chain;

  static String? requestDigest(String chainId, String method, Object? params) {
    if (chainId != chain ||
        !supportedMethods.contains(method) ||
        params is! List<Object?>) {
      return null;
    }
    var remaining = 4096;
    Object? canonical(Object? value, int depth) {
      if (--remaining < 0 || depth > 12) throw const FormatException();
      if (value == null || value is bool || value is num) return value;
      if (value is String && value.length <= 65536) return value;
      if (value is List<Object?>) {
        return [for (final entry in value) canonical(entry, depth + 1)];
      }
      if (value is Map<String, Object?>) {
        final keys = value.keys.toList()..sort();
        return {for (final key in keys) key: canonical(value[key], depth + 1)};
      }
      throw const FormatException();
    }

    try {
      final bytes = utf8.encode(
        jsonEncode([chainId, method, canonical(params, 0)]),
      );
      return bytes.length <= 65536 ? sha256.convert(bytes).toString() : null;
    } on Object {
      return null;
    }
  }
}
