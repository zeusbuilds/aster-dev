import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/app_environment.dart';
import '../config/host_address_policy.dart';

/// Safe, bounded reasons why a configured local service cannot be contacted.
enum LocalNetworkAccessFailure { denied, unavailable }

/// Contains no endpoint, wallet data, or platform exception text.
final class LocalNetworkAccessException implements Exception {
  const LocalNetworkAccessException(this.reason);

  final LocalNetworkAccessFailure reason;

  @override
  String toString() => 'LocalNetworkAccessException(${reason.name})';
}

/// Obtains platform consent before opening a wallet against local services.
abstract interface class LocalNetworkAccess {
  Future<void> ensureFor(WalletServiceConfiguration services);
}

typedef LocalNetworkPermissionRequest = Future<bool> Function();

/// Android 17 protects local sockets in both Dart and the native SDK.
///
/// The platform checks the OS version and current grant on every wallet open,
/// so revocation is respected. Public service profiles never request access.
final class PlatformLocalNetworkAccess implements LocalNetworkAccess {
  PlatformLocalNetworkAccess({
    LocalNetworkPermissionRequest? requestPermission,
    bool Function()? isAndroid,
  }) : _requestPermission = requestPermission ?? _requestFromPlatform,
       _isAndroid = isAndroid ?? _onAndroid;

  static const _channel = MethodChannel('com.aster.wallet/local_network');
  static const _requestTimeout = Duration(seconds: 100);

  final LocalNetworkPermissionRequest _requestPermission;
  final bool Function() _isAndroid;
  Future<void>? _pending;

  @override
  Future<void> ensureFor(WalletServiceConfiguration services) async {
    if (!_isAndroid() || !requiresLocalNetwork(services)) return;
    final current = _pending;
    if (current != null) return current;
    final pending = _ensurePermission();
    _pending = pending;
    try {
      await pending;
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<void> _ensurePermission() async {
    try {
      if (!await _requestPermission().timeout(_requestTimeout)) {
        throw const LocalNetworkAccessException(
          LocalNetworkAccessFailure.denied,
        );
      }
    } on LocalNetworkAccessException {
      rethrow;
    } catch (_) {
      throw const LocalNetworkAccessException(
        LocalNetworkAccessFailure.unavailable,
      );
    }
  }

  static bool _onAndroid() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> _requestFromPlatform() async {
    final granted = await _channel.invokeMethod<bool>('ensureAccess');
    if (granted == null) {
      throw const LocalNetworkAccessException(
        LocalNetworkAccessFailure.unavailable,
      );
    }
    return granted;
  }

  /// Classifies configured hosts locally, without DNS or network activity.
  ///
  /// Includes private IPv4, local IPv6, and mDNS names. IPv4-mapped addresses
  /// retain the corresponding IPv4 policy. Endpoint validation remains owned
  /// by [WalletServiceConfiguration]; this check never weakens transport rules.
  static bool requiresLocalNetwork(WalletServiceConfiguration services) =>
      [
        services.indexerUrl,
        services.rgbTransportProxy,
        services.lspBaseUrl,
        services.vssUrl,
        services.ethRpcUrl,
      ].whereType<String>().any((endpoint) {
        final canonicalEndpoint = endpoint.contains('://')
            ? endpoint
            : 'tcp://$endpoint';
        final host = Uri.tryParse(canonicalEndpoint)?.host.toLowerCase();
        if (host == null || !HostAddressPolicy.isCanonicalEndpointHost(host)) {
          return false;
        }
        if (HostAddressPolicy.isLoopback(host) || host.endsWith('.local')) {
          return true;
        }
        final address = InternetAddress.tryParse(host);
        if (address == null) return false;
        final bytes = address.rawAddress;
        if (bytes.length == 4) return _isLocalIpv4(bytes);
        if (bytes.length != 16) return false;
        if ((bytes[0] & 0xfe) == 0xfc ||
            (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80)) {
          return true;
        }
        final mapped =
            bytes.take(10).every((byte) => byte == 0) &&
            bytes[10] == 0xff &&
            bytes[11] == 0xff;
        final compatible = bytes.take(12).every((byte) => byte == 0);
        return (mapped || compatible) && _isLocalIpv4(bytes.sublist(12));
      });

  static bool _isLocalIpv4(List<int> bytes) =>
      bytes[0] == 10 ||
      bytes[0] == 127 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 169 && bytes[1] == 254);
}
