import 'package:flutter/material.dart';

import 'package:aster/shared/shared.dart';
import 'package:remixicon/remixicon.dart';

/// Button to enter address manually
class ScanEnterAddressButton extends StatelessWidget {
  final VoidCallback onTap;

  const ScanEnterAddressButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;
    final textTheme = context.textTheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Enter address to send',
            style: textTheme.bodyMedium?.copyWith(
              color: colors.text5.withValues(alpha: 0.75),
            ),
          ),
          SizedBox(width: spacing.spacing2),
          Icon(
            RemixIcons.arrow_right_s_line,
            color: colors.text5.withValues(alpha: 0.75),
            size: spacing.spacing20,
          ),
        ],
      ),
    );
  }
}
