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
    final type = context.type;
    final metrics = context.metrics;

    return Column(
      children: [
        SizedBox(height: spacing.xxxl),
        Container(
          width: metrics.walletAvatarSize,
          height: metrics.walletAvatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colorScheme.surface.withValues(
              alpha: effects.scanAvatarSurfaceOpacity,
            ),
          ),
        ),
        SizedBox(height: spacing.md),
        Text(walletName, style: type.scanHeaderTitle),
        SizedBox(height: spacing.sm),
        Text(
          walletId,
          style: type.scanWalletId.copyWith(color: colors.textDisabled),
        ),
      ],
    );
  }
}
