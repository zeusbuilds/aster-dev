import 'package:flutter/foundation.dart';

import '../../../../core/config/app_environment.dart';
import '../validation/validation.dart';

/// Validated app-owned node and chain status.
@immutable
final class WalletNetworkStatus {
  WalletNetworkStatus({
    required this.environment,
    required this.blockHeight,
    required this.nodePublicKey,
    required this.channelCount,
    required this.usableChannelCount,
    required this.peerCount,
    this.walletIdentity,
  }) {
    if ((blockHeight != null && blockHeight! < 0) ||
        (channelCount != null && channelCount! < 0) ||
        (usableChannelCount != null && usableChannelCount! < 0) ||
        (usableChannelCount != null &&
            channelCount != null &&
            usableChannelCount! > channelCount!) ||
        (peerCount != null && peerCount! < 0)) {
      throw ArgumentError('Wallet network counters are invalid.');
    }
    if (nodePublicKey != null &&
        !RegExp(r'^(02|03)[0-9a-fA-F]{64}$').hasMatch(nodePublicKey!)) {
      throw ArgumentError.value(
        nodePublicKey,
        'nodePublicKey',
        'Must be a compressed secp256k1 public key.',
      );
    }
    if (walletIdentity != null &&
        !WalletProtocolText.isIdentifier(
          walletIdentity!,
          maximumCharacters: 512,
        )) {
      throw ArgumentError('Native wallet identity is invalid.');
    }
    if (nodePublicKey == null && walletIdentity == null) {
      throw ArgumentError('A native wallet identity is required.');
    }
  }

  final BlockchainEnvironment environment;

  /// Absent until the backend has authoritatively observed a chain tip.
  final int? blockHeight;

  /// Lightning-only observations are absent for the on-chain backend.
  final String? nodePublicKey;
  final int? channelCount;
  final int? usableChannelCount;
  final int? peerCount;

  /// Stable native profile identity for a backend without a Lightning node.
  final String? walletIdentity;

  /// Stable identity for comparisons and diagnostics across either backend.
  String get publicIdentity => walletIdentity ?? nodePublicKey!;

  @override
  bool operator ==(Object other) =>
      other is WalletNetworkStatus &&
      other.environment == environment &&
      other.blockHeight == blockHeight &&
      other.nodePublicKey == nodePublicKey &&
      other.channelCount == channelCount &&
      other.usableChannelCount == usableChannelCount &&
      other.peerCount == peerCount &&
      other.walletIdentity == walletIdentity;

  @override
  int get hashCode => Object.hash(
    environment,
    blockHeight,
    nodePublicKey,
    channelCount,
    usableChannelCount,
    peerCount,
    walletIdentity,
  );
}

/// Public account keys that may be exported from an authenticated settings flow.
@immutable
final class WalletPublicKeys {
  WalletPublicKeys({required this.bitcoin, required this.rgb}) {
    if (!_isValidPublicKey(bitcoin) || !_isValidPublicKey(rgb)) {
      throw ArgumentError('Wallet account public keys have an invalid shape.');
    }
  }

  static bool _isValidPublicKey(String value) =>
      WalletProtocolText.isIdentifier(value, maximumCharacters: 512);

  final String bitcoin;
  final String rgb;

  @override
  bool operator ==(Object other) =>
      other is WalletPublicKeys && other.bitcoin == bitcoin && other.rgb == rgb;

  @override
  int get hashCode => Object.hash(bitcoin, rgb);
}
