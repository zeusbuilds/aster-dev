import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import 'onboarding_choreography.dart';
import 'onboarding_text_action.dart';

/// Loading or failure state for wallet-setup surfaces.
class OnboardingStatusPanel extends StatelessWidget {
  const OnboardingStatusPanel.loading({
    super.key,
    this.message = 'Preparing wallet security...',
    this.onBrandArt = false,
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
    this.onBrandArt = false,
  }) : assert(
         (primaryLabel == null) == (onPrimary == null),
         'The primary action label and callback must be supplied together.',
       );

  final String? title;

  /// Loading announcements stay available to assistive technology without
  /// painting transient progress copy. Failure messages remain visible.
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;

  /// Adapts status copy and actions for the retained onboarding artwork.
  final bool onBrandArt;

  bool get _loading => title == null;

  @override
  Widget build(BuildContext context) {
    final statusLabel = title == null ? message : '$title. $message';
    final foreground = onBrandArt
        ? context.appColors.onBrandArt
        : context.colorScheme.onSurface;
    final secondary = onBrandArt
        ? foreground.withValues(
            alpha: context.effects.brandContentStrongOpacity,
          )
        : context.appColors.textSecondary;
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
                  OnboardingChoreographyItem(
                    id: 'onboarding-status-visual-motion',
                    visualIndex: 0,
                    child: _loading
                        ? GridLoader(
                            colorStyle: GridLoaderColorStyle.custom,
                            color: onBrandArt
                                ? foreground
                                : context.colorScheme.primary,
                          )
                        : Icon(
                            Icons.lock_outline,
                            color: foreground,
                            size: context.icons.xl,
                          ),
                  ),
                  if (!_loading) ...[
                    SizedBox(height: context.spacing.lg),
                    OnboardingChoreographyItem(
                      id: 'onboarding-status-copy-motion',
                      visualIndex: 1,
                      child: Column(
                        children: [
                          if (title case final title?) ...[
                            Text(
                              title,
                              style: context.type.brandTitle.copyWith(
                                color: foreground,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: context.spacing.sm),
                          ],
                          Text(
                            message,
                            style: context.type.brandBody.copyWith(
                              color: secondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (primaryLabel case final label? when onPrimary != null) ...[
              SizedBox(height: context.spacing.xxl),
              OnboardingChoreographyItem(
                id: 'onboarding-status-primary-motion',
                visualIndex: 2,
                child: CustomButton(
                  text: label,
                  variant: onBrandArt
                      ? ButtonVariant.translucent
                      : ButtonVariant.primary,
                  onTap: onPrimary,
                ),
              ),
            ],
            if (onBack case final action?) ...[
              SizedBox(height: context.spacing.sm),
              OnboardingChoreographyItem(
                id: 'onboarding-status-back-motion',
                visualIndex: 3,
                child: SizedBox(
                  width: double.infinity,
                  child: OnboardingTextAction(
                    label: 'Back',
                    onBrandArt: onBrandArt,
                    onPressed: action,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
