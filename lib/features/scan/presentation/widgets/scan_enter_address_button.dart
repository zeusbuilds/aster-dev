import 'dart:async';

import 'package:flutter/material.dart';

import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';

/// Button to enter address manually
class ScanEnterAddressButton extends StatelessWidget {
  final VoidCallback onTap;

  const ScanEnterAddressButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final icons = context.icons;

    void activate() {
      unawaited(context.haptics.trigger(HapticIntent.lightImpact));
      onTap();
    }

    return Semantics(
      button: true,
      label: 'Enter address to send',
      excludeSemantics: true,
      child: Material(
        color: colors.transparentSurface,
        child: InkWell(
          onTap: activate,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: spacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Enter address to send',
                  style: context.type.scanCta.copyWith(
                    color: colors.onScan.withValues(
                      alpha: effects.brandContentMutedOpacity,
                    ),
                  ),
                ),
                SizedBox(width: spacing.xxs),
                Icon(
                  RemixIcons.arrow_right_s_line,
                  color: colors.onScan.withValues(
                    alpha: effects.brandContentMutedOpacity,
                  ),
                  size: icons.sm,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
