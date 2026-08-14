import 'package:flutter/material.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';

/// Centered Settings load failure that preserves the typed retry contract.
final class SettingsLoadFailure extends StatelessWidget {
  const SettingsLoadFailure({
    super.key,
    required this.failure,
    required this.onRetry,
  });

  /// Redacted failure safe for presentation.
  final AppFailure failure;

  /// Repeats the owned load when [AppFailure.retryable] allows it.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.spacing.screenPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  failure.userMessage,
                  style: context.type.errorMessage,
                  textAlign: TextAlign.center,
                ),
              ),
              if (failure.retryable) ...[
                SizedBox(height: context.spacing.xxl),
                CustomButton(text: 'Retry', onTap: onRetry),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One accessible progress owner for the serialized preference mutation.
final class SettingsSavingIndicator extends StatelessWidget {
  const SettingsSavingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Saving preference',
      child: const ExcludeSemantics(child: LinearProgressIndicator()),
    );
  }
}
