import '../errors/app_failure.dart';
import 'host_address_policy.dart';

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
    final decoded = _decode(raw);
    if (raw.isEmpty ||
        raw != raw.trim() ||
        raw.length > maximumCharacters ||
        raw.contains(RegExp(r'\s')) ||
        _unsafeDecodedCharacters.hasMatch(decoded) ||
        uri.scheme.toLowerCase() != 'https' ||
        !_isPublicHost(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      throw const AppConfigurationException();
    }
  }

  static String _decode(String value) {
    try {
      return Uri.decodeFull(value);
    } on FormatException {
      throw const AppConfigurationException();
    }
  }

  static bool _isPublicHost(String value) {
    final host = value.toLowerCase();
    if (!HostAddressPolicy.isCanonicalDnsName(host)) {
      return false;
    }
    if (_nonPublicSuffixes.any(
      (suffix) => host == suffix || host.endsWith('.$suffix'),
    )) {
      return false;
    }
    return true;
  }

  static final _unsafeDecodedCharacters = RegExp(
    r'[\u0000-\u0020\u007f-\u009f\u202a-\u202e\u2066-\u2069]',
  );

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
