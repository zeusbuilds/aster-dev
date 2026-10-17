import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';

/// Installed app version with independent loading, failure, and retry state.
class SettingsVersionFooter extends StatelessWidget {
  const SettingsVersionFooter({
    super.key,
    required this.appInfo,
    required this.onRetry,
  });

  /// Independent package-metadata state.
  final AsyncValue<SettingsAppState> appInfo;

  /// Retries only package metadata loading.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final state = appInfo.value;
    final metadata = state?.metadata;
    final loading = appInfo.isLoading || (state?.metadataLoading ?? false);
    final failure =
        state?.metadataFailure ??
        (appInfo.hasError
            ? FailureMapper.from(
                appInfo.error!,
                appInfo.stackTrace ?? StackTrace.current,
              )
            : null);
    final version = metadata == null
        ? '${AppConstants.appName} • Version unavailable'
        : '${AppConstants.appName} • Version ${metadata.version}'
              '${metadata.buildNumber.isEmpty ? '' : ' (${metadata.buildNumber})'}';

    return Semantics(
      liveRegion: failure != null,
      label: loading ? 'Loading app version' : null,
      excludeSemantics: loading,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            AppSkeletonizer(
              enabled: loading,
              child: NumericText(
                loading ? '${AppConstants.appName} • Version loading' : version,
                key: const ValueKey('settings-version-label'),
                style: context.type.versionLabel,
                textAlign: TextAlign.center,
              ),
            ),
            if (!loading && failure?.retryable == true) ...[
              SizedBox(height: context.spacing.sm),
              CustomButton.compact(
                text: 'Retry version',
                variant: ButtonVariant.secondary,
                onTap: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
