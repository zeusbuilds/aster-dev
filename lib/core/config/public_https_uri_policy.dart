import '../errors/app_failure.dart';

/// Shared fail-closed policy for deployment-owned public HTTPS destinations.
abstract final class PublicHttpsUriPolicy {
  /// Maximum accepted serialized URI length.
  static const maximumCharacters = 2048;

  /// Parses and validates one exact public HTTPS [raw] value.
  static Uri parse(String raw) {
    if (raw != raw.trim() ||
        raw.length > maximumCharacters ||
        raw.contains(RegExp(r'\s'))) {
      throw const AppConfigurationException();
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) throw const AppConfigurationException();
    validate(uri);
    return uri;
  }

  /// Validates a URI without accepting credentials or URL-carried state.
  static void validate(Uri uri) {
    final raw = uri.toString();
    if (raw.isEmpty ||
        raw != raw.trim() ||
        raw.length > maximumCharacters ||
        raw.contains(RegExp(r'\s')) ||
        uri.scheme.toLowerCase() != 'https' ||
        !_isPublicHost(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      throw const AppConfigurationException();
    }
  }

  static bool _isPublicHost(String value) {
    final host = value.toLowerCase();
    if (host.isEmpty ||
        host.length > 253 ||
        !host.contains('.') ||
        host.startsWith('.') ||
        host.endsWith('.') ||
        host.contains(':') ||
        _ipv4Literal.hasMatch(host)) {
      return false;
    }
    if (_nonPublicSuffixes.any(
      (suffix) => host == suffix || host.endsWith('.$suffix'),
    )) {
      return false;
    }
    return host.split('.').every(_isValidDnsLabel);
  }

  static bool _isValidDnsLabel(String label) =>
      label.isNotEmpty &&
      label.length <= 63 &&
      _dnsLabel.hasMatch(label) &&
      !label.startsWith('-') &&
      !label.endsWith('-');

  static final _ipv4Literal = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$');
  static final _dnsLabel = RegExp(r'^[a-z0-9-]+$');

  static const _nonPublicSuffixes = <String>{
    'example',
    'home',
    'internal',
    'invalid',
    'lan',
    'local',
    'localhost',
    'test',
  };
}
