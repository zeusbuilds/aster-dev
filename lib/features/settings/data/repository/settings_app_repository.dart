import '../../../../core/core.dart';
import '../../domain/models/models.dart';

/// Owns installed-app metadata and deployment-configured public Settings links.
final class SettingsAppRepository {
  SettingsAppRepository(this._metadata, this._externalUris);

  final AppMetadataService _metadata;
  final ExternalUriService _externalUris;

  /// Loads bounded package metadata without coupling Settings to a plugin.
  Future<AppResult<AppBuildMetadata>> loadMetadata() => _metadata.load();

  /// Public destinations configured for this exact application build.
  Set<SettingsExternalLink> availableLinks(
    PublicLinkConfiguration configuration,
  ) {
    configuration.validate();
    return Set.unmodifiable(
      SettingsExternalLink.values.where(
        (link) => configuration.uriFor(_destinationFor(link)) != null,
      ),
    );
  }

  /// Opens a configured destination through the bounded platform adapter.
  Future<AppResult<void>> openLink(
    SettingsExternalLink link,
    PublicLinkConfiguration configuration,
  ) {
    configuration.validate();
    final uri = configuration.uriFor(_destinationFor(link));
    if (uri == null) return Future.value(AppResult.failure(_unavailableLink));
    return _externalUris.open(uri);
  }

  static const _unavailableLink = AppFailure(
    code: 'settings_link_unavailable',
    kind: AppFailureKind.configuration,
    userMessage: 'This link is unavailable in this build.',
    retryable: false,
  );
}

PublicLinkDestination _destinationFor(SettingsExternalLink link) {
  return switch (link) {
    SettingsExternalLink.contactSupport => PublicLinkDestination.contactSupport,
    SettingsExternalLink.termsOfService => PublicLinkDestination.termsOfService,
    SettingsExternalLink.privacyPolicy => PublicLinkDestination.privacyPolicy,
    SettingsExternalLink.twitter => PublicLinkDestination.twitter,
    SettingsExternalLink.telegram => PublicLinkDestination.telegram,
    SettingsExternalLink.instagram => PublicLinkDestination.instagram,
  };
}
