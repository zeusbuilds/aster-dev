import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Wallet header displaying avatar, name, and ID
class ScanWalletHeader extends StatelessWidget {
  final String walletName;
  final String walletId;

  const ScanWalletHeader({
    super.key,
    required this.walletName,
    required this.walletId,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final textTheme = context.textTheme;

    return Column(
      children: [
        SizedBox(height: spacing.xxxl),
        Container(
          width: spacing.giant,
          height: spacing.giant,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colorScheme.surface.withValues(
              alpha: effects.scanAvatarSurfaceOpacity,
            ),
          ),
        ),
        SizedBox(height: spacing.md),
        Text(
          walletName,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.onScan,
          ),
        ),
        SizedBox(height: spacing.sm),
        Text(
          walletId,
          style: textTheme.bodySmall?.copyWith(color: colors.textDisabled),
        ),
      ],
    );
  }
}
