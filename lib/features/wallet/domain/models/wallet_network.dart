import 'package:flutter/foundation.dart';

import '../../../../core/config/app_environment.dart';

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
  }) {
    if (blockHeight < 0 ||
        channelCount < 0 ||
        usableChannelCount < 0 ||
        usableChannelCount > channelCount ||
        peerCount < 0) {
      throw ArgumentError('Wallet network counters are invalid.');
    }
    if (!RegExp(r'^(02|03)[0-9a-fA-F]{64}$').hasMatch(nodePublicKey)) {
      throw ArgumentError.value(
        nodePublicKey,
        'nodePublicKey',
        'Must be a compressed secp256k1 public key.',
      );
    }
  }

  final BlockchainEnvironment environment;
  final int blockHeight;
  final String nodePublicKey;
  final int channelCount;
  final int usableChannelCount;
  final int peerCount;

  @override
  bool operator ==(Object other) =>
      other is WalletNetworkStatus &&
      other.environment == environment &&
      other.blockHeight == blockHeight &&
      other.nodePublicKey == nodePublicKey &&
      other.channelCount == channelCount &&
      other.usableChannelCount == usableChannelCount &&
      other.peerCount == peerCount;

  @override
  int get hashCode => Object.hash(
    environment,
    blockHeight,
    nodePublicKey,
    channelCount,
    usableChannelCount,
    peerCount,
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
      value.isNotEmpty &&
      value.length <= 512 &&
      value == value.trim() &&
      !value.contains(RegExp(r'\s'));

  final String bitcoin;
  final String rgb;

  @override
  bool operator ==(Object other) =>
      other is WalletPublicKeys && other.bitcoin == bitcoin && other.rgb == rgb;

  @override
  int get hashCode => Object.hash(bitcoin, rgb);
}
