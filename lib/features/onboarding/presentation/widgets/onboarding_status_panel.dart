import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import 'onboarding_text_action.dart';

/// Branded loading or recoverable-error state used by onboarding routes.
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
    required this.primaryLabel,
    required this.onPrimary,
    required this.onBack,
  });

  final String? title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;

  bool get _loading => title == null;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.spacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              GridLoader(
                colorStyle: GridLoaderColorStyle.custom,
                color: context.appColors.onBrandArt,
              )
            else
              Icon(
                Icons.lock_outline,
                color: context.appColors.onBrandArt,
                size: context.icons.xl,
              ),
            SizedBox(height: context.spacing.lg),
            if (title case final title?) ...[
              Text(
                title,
                style: context.type.brandTitle,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: context.spacing.sm),
            ],
            Text(
              message,
              style: context.type.brandBody,
              textAlign: TextAlign.center,
            ),
            if (onPrimary case final action?) ...[
              SizedBox(height: context.spacing.xxl),
              CustomButton(
                text: primaryLabel!,
                variant: ButtonVariant.translucent,
                onTap: action,
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
