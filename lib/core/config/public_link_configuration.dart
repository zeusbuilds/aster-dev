import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';

/// Deployment-owned public destinations exposed from the application.
enum PublicLinkDestination {
  /// Product support destination.
  contactSupport,

  /// Published terms governing use of the application.
  termsOfService,

  /// Published privacy policy.
  privacyPolicy,

  /// Official Twitter profile.
  twitter,

  /// Official Telegram destination.
  telegram,

  /// Official Instagram profile.
  instagram,
}

/// Optional public links supplied by the release environment.
///
/// A missing value means that the corresponding UI action must stay disabled.
/// Configured values are restricted to bounded HTTPS destinations without
/// embedded credentials, queries, or fragments.
@immutable
final class PublicLinkConfiguration {
  const PublicLinkConfiguration({
    this.contactSupport,
    this.termsOfService,
    this.privacyPolicy,
    this.twitter,
    this.telegram,
    this.instagram,
  });

  /// Reads optional public destinations from compile-time environment values.
  factory PublicLinkConfiguration.fromEnvironment() {
    return PublicLinkConfiguration(
      contactSupport: _parseOptionalPublicUri(
        const String.fromEnvironment('UTEXO_SUPPORT_URL'),
      ),
      termsOfService: _parseOptionalPublicUri(
        const String.fromEnvironment('UTEXO_TERMS_URL'),
      ),
      privacyPolicy: _parseOptionalPublicUri(
        const String.fromEnvironment('UTEXO_PRIVACY_URL'),
      ),
      twitter: _parseOptionalPublicUri(
        const String.fromEnvironment('UTEXO_TWITTER_URL'),
      ),
      telegram: _parseOptionalPublicUri(
        const String.fromEnvironment('UTEXO_TELEGRAM_URL'),
      ),
      instagram: _parseOptionalPublicUri(
        const String.fromEnvironment('UTEXO_INSTAGRAM_URL'),
      ),
    );
  }

  static const maximumUriCharacters = 2048;

  /// Contact Support URL, or `null` when omitted from this build.
  final Uri? contactSupport;

  /// Terms of Service URL, or `null` when omitted from this build.
  final Uri? termsOfService;

  /// Privacy Policy URL, or `null` when omitted from this build.
  final Uri? privacyPolicy;

  /// Official Twitter URL, or `null` when omitted from this build.
  final Uri? twitter;

  /// Official Telegram URL, or `null` when omitted from this build.
  final Uri? telegram;

  /// Official Instagram URL, or `null` when omitted from this build.
  final Uri? instagram;

  /// Validates explicitly constructed configurations before presentation.
  void validate() {
    for (final destination in PublicLinkDestination.values) {
      final uri = uriFor(destination);
      if (uri != null) _validatePublicUri(uri);
    }
  }

  /// Returns the validated destination, or `null` when this build omits it.
  Uri? uriFor(PublicLinkDestination destination) {
    return switch (destination) {
      PublicLinkDestination.contactSupport => contactSupport,
      PublicLinkDestination.termsOfService => termsOfService,
      PublicLinkDestination.privacyPolicy => privacyPolicy,
      PublicLinkDestination.twitter => twitter,
      PublicLinkDestination.telegram => telegram,
      PublicLinkDestination.instagram => instagram,
    };
  }
}

Uri? _parseOptionalPublicUri(String raw) {
  if (raw.isEmpty) return null;
  if (raw != raw.trim() ||
      raw.length > PublicLinkConfiguration.maximumUriCharacters ||
      raw.contains(RegExp(r'\s'))) {
    throw const AppConfigurationException();
  }
  final uri = Uri.tryParse(raw);
  if (uri == null) throw const AppConfigurationException();
  _validatePublicUri(uri);
  return uri;
}

void _validatePublicUri(Uri uri) {
  final raw = uri.toString();
  if (raw.isEmpty ||
      raw != raw.trim() ||
      raw.length > PublicLinkConfiguration.maximumUriCharacters ||
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

bool _isPublicHost(String value) {
  final host = value.toLowerCase();
  if (host.isEmpty ||
      !host.contains('.') ||
      host.startsWith('.') ||
      host.endsWith('.') ||
      host.contains(':') ||
      _ipv4Literal.hasMatch(host)) {
    return false;
  }
  return !_nonPublicSuffixes.any(
    (suffix) => host == suffix || host.endsWith('.$suffix'),
  );
}

final _ipv4Literal = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$');

const _nonPublicSuffixes = <String>{
  'example',
  'home',
  'internal',
  'invalid',
  'lan',
  'local',
  'localhost',
  'test',
};
