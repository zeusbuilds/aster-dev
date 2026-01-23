import 'package:flutter/material.dart';

import 'package:aster/shared/shared.dart';

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
    final colors = context.colors;
    final textTheme = context.textTheme;

    return Column(
      children: [
        SizedBox(height: spacing.spacing32),
        Container(
          width: spacing.spacing64,
          height: spacing.spacing64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.fill1.withValues(alpha: 0.25),
          ),
        ),
        SizedBox(height: spacing.spacing12),
        Text(
          walletName,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.text5,
            height: 1.0,
          ),
        ),
        SizedBox(height: spacing.spacing8),
        Text(
          walletId,
          style: textTheme.bodySmall?.copyWith(
            color: colors.text4,
            letterSpacing: 0.5,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
