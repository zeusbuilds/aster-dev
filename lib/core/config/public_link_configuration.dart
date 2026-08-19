import 'package:flutter/foundation.dart';

import 'public_https_uri_policy.dart';

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
        const String.fromEnvironment('ASTER_SUPPORT_URL'),
      ),
      termsOfService: _parseOptionalPublicUri(
        const String.fromEnvironment('ASTER_TERMS_URL'),
      ),
      privacyPolicy: _parseOptionalPublicUri(
        const String.fromEnvironment('ASTER_PRIVACY_URL'),
      ),
      twitter: _parseOptionalPublicUri(
        const String.fromEnvironment('ASTER_TWITTER_URL'),
      ),
      telegram: _parseOptionalPublicUri(
        const String.fromEnvironment('ASTER_TELEGRAM_URL'),
      ),
      instagram: _parseOptionalPublicUri(
        const String.fromEnvironment('ASTER_INSTAGRAM_URL'),
      ),
    );
  }

  static const maximumUriCharacters = PublicHttpsUriPolicy.maximumCharacters;

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
      if (uri != null) PublicHttpsUriPolicy.validate(uri);
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
  return PublicHttpsUriPolicy.parse(raw);
}
