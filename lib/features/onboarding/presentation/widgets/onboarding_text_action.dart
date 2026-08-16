import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Keyboard-accessible secondary action for branded onboarding screens.
class OnboardingTextAction extends StatelessWidget {
  const OnboardingTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.hapticIntent = HapticIntent.lightImpact,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final HapticIntent? hapticIntent;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: enabled
          ? () {
              if (hapticIntent case final intent?) {
                unawaited(context.haptics.trigger(intent));
              }
              onPressed();
            }
          : null,
      style: TextButton.styleFrom(
        foregroundColor: context.appColors.onBrandArt,
        disabledForegroundColor: context.appColors.onBrandArt.withValues(
          alpha: context.stateLayers.disabled,
        ),
        minimumSize: Size.fromHeight(context.metrics.minTouchTarget),
        textStyle: context.type.brandAction,
        shape: const StadiumBorder(),
      ),
      child: Text(label),
    );
  }
}
