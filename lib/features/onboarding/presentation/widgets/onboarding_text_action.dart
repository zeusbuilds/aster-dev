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
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: enabled
          ? () {
              unawaited(context.haptics.trigger(HapticIntent.lightImpact));
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
