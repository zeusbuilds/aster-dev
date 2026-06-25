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

    return Semantics(
      button: true,
      label: 'Enter address to send',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
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
    );
  }
}
