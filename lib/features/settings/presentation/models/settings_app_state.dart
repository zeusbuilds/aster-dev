import 'package:flutter/foundation.dart';

import '../../../../core/core.dart';
import '../../domain/models/models.dart';

/// Independent state for installed-app metadata and public Settings actions.
@immutable
final class SettingsAppState {
  SettingsAppState({
    required Set<SettingsExternalLink> availableLinks,
    this.metadata,
    this.metadataFailure,
    this.metadataLoading = false,
    this.linkConfigurationFailure,
    this.openingLink,
    this.operationFailure,
  }) : availableLinks = Set.unmodifiable(availableLinks) {
    if (openingLink != null && !this.availableLinks.contains(openingLink)) {
      throw ArgumentError(
        'The active Settings link must be available in this build.',
      );
    }
  }

  /// Public actions configured for this exact build.
  final Set<SettingsExternalLink> availableLinks;

  /// Installed app version/build metadata when loading succeeded.
  final AppBuildMetadata? metadata;

  /// Bounded package-metadata failure, independent from link configuration.
  final AppFailure? metadataFailure;

  /// Whether a metadata retry is currently active.
  final bool metadataLoading;

  /// Invalid deployment-link configuration, retained for diagnostics.
  final AppFailure? linkConfigurationFailure;

  /// Link launch currently awaiting its platform result.
  final SettingsExternalLink? openingLink;

  /// Most recent transient link-launch failure.
  final AppFailure? operationFailure;

  /// Whether [link] is configured and eligible for activation.
  bool isAvailable(SettingsExternalLink link) => availableLinks.contains(link);

  /// Starts metadata loading while preserving any in-flight link operation.
  SettingsAppState beginMetadataLoad() {
    return SettingsAppState(
      availableLinks: availableLinks,
      metadata: metadata,
      linkConfigurationFailure: linkConfigurationFailure,
      metadataLoading: true,
      openingLink: openingLink,
      operationFailure: operationFailure,
    );
  }

  /// Commits freshly loaded metadata and clears its prior failure.
  SettingsAppState completeMetadata(AppBuildMetadata value) {
    return SettingsAppState(
      availableLinks: availableLinks,
      metadata: value,
      linkConfigurationFailure: linkConfigurationFailure,
      openingLink: openingLink,
      operationFailure: operationFailure,
    );
  }

  /// Retains a typed metadata failure without changing public-link state.
  SettingsAppState failMetadata(AppFailure failure) {
    return SettingsAppState(
      availableLinks: availableLinks,
      metadata: metadata,
      metadataFailure: failure,
      linkConfigurationFailure: linkConfigurationFailure,
      openingLink: openingLink,
      operationFailure: operationFailure,
    );
  }

  /// Starts one eligible link launch and clears its prior transient failure.
  SettingsAppState beginOpening(SettingsExternalLink link) {
    if (!isAvailable(link)) return this;
    return SettingsAppState(
      availableLinks: availableLinks,
      metadata: metadata,
      metadataFailure: metadataFailure,
      metadataLoading: metadataLoading,
      linkConfigurationFailure: linkConfigurationFailure,
      openingLink: link,
    );
  }

  /// Completes the active link launch with an optional failure.
  SettingsAppState completeOpening({AppFailure? failure}) {
    return SettingsAppState(
      availableLinks: availableLinks,
      metadata: metadata,
      metadataFailure: metadataFailure,
      metadataLoading: metadataLoading,
      linkConfigurationFailure: linkConfigurationFailure,
      operationFailure: failure,
    );
  }

  /// Clears a transient failure after presentation.
  SettingsAppState clearOperationFailure() {
    if (operationFailure == null) return this;
    return SettingsAppState(
      availableLinks: availableLinks,
      metadata: metadata,
      metadataFailure: metadataFailure,
      metadataLoading: metadataLoading,
      linkConfigurationFailure: linkConfigurationFailure,
      openingLink: openingLink,
    );
  }
}
