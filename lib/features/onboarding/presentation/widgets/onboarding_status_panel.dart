import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import 'onboarding_text_action.dart';

/// Loading or failure state on the white wallet-setup pages.
class OnboardingStatusPanel extends StatelessWidget {
  const OnboardingStatusPanel.loading({
    super.key,
    this.message = 'Preparing wallet security...',
  }) : title = null,
       primaryLabel = null,
       onPrimary = null,
       onBack = null;

  const OnboardingStatusPanel.failure({
    super.key,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
    required this.onBack,
  }) : assert(
         (primaryLabel == null) == (onPrimary == null),
         'The primary action label and callback must be supplied together.',
       );

  final String? title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;

  bool get _loading => title == null;

  @override
  Widget build(BuildContext context) {
    final statusLabel = title == null ? message : '$title. $message';
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.spacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              label: statusLabel,
              excludeSemantics: true,
              child: Column(
                children: [
                  if (_loading)
                    GridLoader(
                      colorStyle: GridLoaderColorStyle.custom,
                      color: context.colorScheme.primary,
                    )
                  else
                    Icon(
                      Icons.lock_outline,
                      color: context.colorScheme.onSurface,
                      size: context.icons.xl,
                    ),
                  SizedBox(height: context.spacing.lg),
                  if (title case final title?) ...[
                    Text(
                      title,
                      style: context.type.brandTitle.copyWith(
                        color: context.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: context.spacing.sm),
                  ],
                  Text(
                    message,
                    style: context.type.brandBody.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            if (primaryLabel case final label? when onPrimary != null) ...[
              SizedBox(height: context.spacing.xxl),
              CustomButton(
                text: label,
                variant: ButtonVariant.primary,
                onTap: onPrimary,
              ),
            ],
            if (onBack case final action?) ...[
              SizedBox(height: context.spacing.sm),
              OnboardingTextAction(label: 'Back', onPressed: action),
            ],
          ],
        ),
      ),
    );
  }
}
