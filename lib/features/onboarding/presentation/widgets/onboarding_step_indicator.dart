import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Compact, non-interactive progress rail for a linear onboarding flow.
///
/// The active stage expands while the previous stage collapses, preserving a
/// stable overall footprint and avoiding the visual weight of pagination dots.
class OnboardingStepIndicator extends StatelessWidget {
  const OnboardingStepIndicator({
    super.key,
    required this.currentStep,
    required this.stepCount,
    this.onBrandArt = false,
  }) : assert(stepCount > 0),
       assert(currentStep >= 0 && currentStep < stepCount);

  /// Zero-based stage currently visible to the user.
  final int currentStep;

  /// Number of stages in the selected create or import flow.
  final int stepCount;

  /// Whether the rail is displayed over Aster's retained onboarding artwork.
  final bool onBrandArt;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    final activeColor = onBrandArt
        ? context.appColors.onBrandArt
        : context.colorScheme.primary;
    final inactiveColor = activeColor.withValues(
      alpha: context.effects.onboardingStepIndicatorInactiveOpacity,
    );
    final animationDuration = context.motionPolicy.duration(
      context.motion.onboardingStepIndicatorTransitionDuration,
    );

    return Semantics(
      container: true,
      label: 'Wallet setup step ${currentStep + 1} of $stepCount',
      excludeSemantics: true,
      child: Row(
        key: const ValueKey('onboarding-step-indicator'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < stepCount; index += 1) ...[
            AnimatedContainer(
              key: ValueKey('onboarding-step-indicator-$index'),
              duration: animationDuration,
              curve: context.motion.choreographyCurve,
              width: index == currentStep
                  ? metrics.onboardingStepIndicatorActiveWidth
                  : metrics.onboardingStepIndicatorInactiveWidth,
              height: metrics.onboardingStepIndicatorHeight,
              decoration: BoxDecoration(
                color: index == currentStep ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(
                  metrics.onboardingStepIndicatorHeight / 2,
                ),
              ),
            ),
            if (index < stepCount - 1)
              SizedBox(width: metrics.onboardingStepIndicatorGap),
          ],
        ],
      ),
    );
  }
}
