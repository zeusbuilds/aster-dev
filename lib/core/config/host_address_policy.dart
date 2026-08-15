import 'dart:io';

/// Canonical host syntax and loopback classification for mobile endpoints.
///
/// Parsing is local-only: [InternetAddress.tryParse] does not perform DNS
/// resolution. Requiring canonical IPv4 text prevents platform resolvers from
/// reinterpreting legacy forms such as `127.1` or `0x7f.0.0.1`.
abstract final class HostAddressPolicy {
  /// Whether [value] is a canonical multi-label public DNS name.
  static bool isCanonicalDnsName(String value) {
    final host = value.toLowerCase();
    if (host.isEmpty ||
        host.length > 253 ||
        !host.contains('.') ||
        host.startsWith('.') ||
        host.endsWith('.') ||
        host.contains(':')) {
      return false;
    }
    final labels = host.split('.');
    return labels.every(_isValidDnsLabel) && _asciiLetter.hasMatch(labels.last);
  }

  /// Whether [value] is valid for a configured service endpoint.
  ///
  /// Service endpoints may use a canonical DNS name, canonical IPv4 or IPv6,
  /// or the exact `localhost` development alias.
  static bool isCanonicalEndpointHost(String value) {
    final host = value.toLowerCase();
    if (host == 'localhost') return true;
    final address = InternetAddress.tryParse(host);
    if (address != null) {
      return address.type == InternetAddressType.IPv4
          ? _isCanonicalIpv4(host)
          : !host.contains('%');
    }
    return isCanonicalDnsName(host);
  }

  /// Whether canonical endpoint [value] addresses the local device.
  ///
  /// IPv4-compatible and IPv4-mapped IPv6 loopback forms are included so they
  /// cannot bypass development-port ownership checks.
  static bool isLoopback(String value) {
    final host = value.toLowerCase();
    if (host == 'localhost') return true;
    if (!isCanonicalEndpointHost(host)) return false;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    if (address.isLoopback) return true;

    final bytes = address.rawAddress;
    if (bytes.length != 16 || bytes[12] != 127) return false;
    final compatiblePrefix = bytes.take(12).every((byte) => byte == 0);
    final mappedPrefix =
        bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    return compatiblePrefix || mappedPrefix;
  }

  static bool _isCanonicalIpv4(String value) {
    final components = value.split('.');
    if (components.length != 4) return false;
    for (final component in components) {
      if (!_decimalComponent.hasMatch(component) ||
          (component.length > 1 && component.startsWith('0'))) {
        return false;
      }
      final parsed = int.tryParse(component);
      if (parsed == null || parsed > 255) return false;
    }
    return true;
  }

  static bool _isValidDnsLabel(String label) =>
      label.isNotEmpty &&
      label.length <= 63 &&
      _dnsLabel.hasMatch(label) &&
      !label.startsWith('-') &&
      !label.endsWith('-');

  static final _decimalComponent = RegExp(r'^[0-9]+$');
  static final _dnsLabel = RegExp(r'^[a-z0-9-]+$');
  static final _asciiLetter = RegExp('[a-z]');
}
