import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Truthful active-wallet identity shown above the camera frame.
class ScanWalletHeader extends StatelessWidget {
  const ScanWalletHeader({
    super.key,
    this.walletName,
    this.walletId,
    this.loading = false,
  });

  final String? walletName;
  final String? walletId;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final effects = context.effects;
    final type = context.type;
    final metrics = context.metrics;

    final name = walletName ?? 'Wallet unavailable';
    final semanticLabel = loading
        ? 'Loading active wallet'
        : walletName == null
        ? name
        : walletId == null
        ? 'Active wallet, $name'
        : 'Active wallet, $name, ID $walletId';
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: AppSkeletonizer(
        enabled: loading,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
            Text(
              loading ? 'Loading wallet' : name,
              style: type.scanHeaderTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (walletId case final id?) ...[
              SizedBox(height: spacing.sm),
              Text(
                id,
                style: type.scanWalletId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
