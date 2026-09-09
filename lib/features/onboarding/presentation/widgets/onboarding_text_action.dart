import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Keyboard-accessible secondary action for branded onboarding screens.
class OnboardingTextAction extends StatelessWidget {
  const OnboardingTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.enabled = true,
    this.hapticIntent = HapticIntent.lightImpact,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  /// Preserves the label's geometry and blocks activation during the operation.
  final bool loading;
  final bool enabled;
  final HapticIntent? hapticIntent;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && !loading;
    void activate() {
      if (hapticIntent case final intent?) {
        unawaited(context.haptics.trigger(intent));
      }
      onPressed();
    }

    return Semantics(
      button: true,
      enabled: interactive,
      label: label,
      value: loading ? 'Loading' : null,
      liveRegion: loading,
      excludeSemantics: true,
      onTap: interactive ? activate : null,
      child: TextButton(
        onPressed: interactive ? activate : null,
        style: TextButton.styleFrom(
          foregroundColor: context.appColors.onBrandArt,
          disabledForegroundColor: context.appColors.onBrandArt.withValues(
            alpha: context.stateLayers.disabled,
          ),
          minimumSize: Size.fromHeight(context.metrics.minTouchTarget),
          textStyle: context.type.brandAction,
          shape: const StadiumBorder(),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Visibility(
              visible: !loading,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon case final value?) ...[
                    Icon(value, size: context.icons.sm),
                    SizedBox(width: context.spacing.sm),
                  ],
                  Flexible(child: Text(label, textAlign: TextAlign.center)),
                ],
              ),
            ),
            if (loading)
              const GridLoader(colorStyle: GridLoaderColorStyle.white),
          ],
        ),
      ),
    );
  }
}
