import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';

/// Truthful active-wallet identity shown above the camera frame.
class ScanWalletHeader extends StatelessWidget {
  const ScanWalletHeader({
    super.key,
    this.walletName,
    this.walletId,
    this.loading = false,
    this.failureMessage,
    this.onRetry,
  }) : assert(failureMessage != null || onRetry == null);

  final String? walletName;
  final String? walletId;
  final bool loading;
  final String? failureMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final type = context.type;

    final failure = failureMessage;
    final hasFailure = failure != null;
    final name = walletName ?? 'Wallet unavailable';
    final visibleWalletId = hasFailure ? null : walletId;
    final semanticLabel = loading
        ? 'Loading active wallet'
        : hasFailure
        ? 'Active wallet unavailable, $failure'
        : walletName == null
        ? name
        : walletId == null
        ? 'Active wallet, $name'
        : 'Active wallet, $name, ID $walletId';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: AppSkeletonizer(
        enabled: loading,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Semantics(
                    liveRegion: loading || hasFailure,
                    label: semanticLabel,
                    excludeSemantics: true,
                    child: Text(
                      loading ? 'Loading wallet' : failure ?? name,
                      style: type.scanHeaderTitle,
                      maxLines: hasFailure ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                if (onRetry case final retry?) ...[
                  SizedBox(width: spacing.xs),
                  AsterIconButton(
                    icon: RemixIcons.refresh_line,
                    tooltip: 'Retry active wallet',
                    color: context.colorScheme.surface,
                    onPressed: retry,
                  ),
                ],
              ],
            ),
            if (visibleWalletId case final id?) ...[
              SizedBox(height: spacing.sm),
              ExcludeSemantics(
                child: Text(
                  id,
                  style: type.scanWalletId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
