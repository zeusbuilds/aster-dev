import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';

/// Widget displaying a single swap pair (from or to asset)
///
/// Shows asset icon, name, amount, balance, and market price
class SwapPair extends StatelessWidget {
  /// Whether this is the "from" pair (true) or "to" pair (false)
  final bool from;

  /// Asset model to display
  final AssetModel asset;

  /// Amount to swap
  final String amount;

  /// Current market price
  final String marketPrice;

  /// Current wallet balance
  final String balance;

  /// Callback when asset is tapped to change selection
  final VoidCallback? onAssetTap;
  const SwapPair({
    super.key,
    required this.from,
    this.asset = AssetModel.bitcoin,
    required this.amount,
    required this.marketPrice,
    required this.balance,
    this.onAssetTap,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final radius = context.radii;
    final icons = context.icons;
    final type = context.type;

    void selectAsset() {
      unawaited(context.haptics.trigger(HapticIntent.selection));
      onAssetTap?.call();
    }

    return Squircle(
      padding: EdgeInsets.zero,
      borderColor: colors.transparentSurface,
      border: from
          ? null
          : BorderRadius.only(
              bottomLeft: Radius.circular(radius.card),
              bottomRight: Radius.circular(radius.card),
            ),
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: spacing.md,
          horizontal: spacing.lg,
        ),
        color: from ? colors.transparentSurface : colors.surfaceSubtle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              enabled: onAssetTap != null,
              label: 'Select ${asset.token}',
              excludeSemantics: true,
              child: Material(
                color: colors.transparentSurface,
                child: InkWell(
                  onTap: onAssetTap == null ? null : selectAsset,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      NumericText(
                        marketPrice,
                        style: type.rowMetaStrong.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      SvgPicture.asset(
                        asset.icon,
                        width: icons.lg,
                        height: icons.lg,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.circle,
                          size: icons.lg,
                          color: AssetDisplay.colorOf(context, asset),
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      Text(asset.token, style: type.title),
                      SizedBox(width: spacing.xs),
                      Icon(
                        RemixIcons.arrow_right_s_line,
                        size: icons.sm,
                        color: colors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                NumericText(amount, style: type.amountLarge),
                const Spacer(),
                AmountText(
                  'Bal: $balance',
                  style: type.rowMetaStrong.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (from) ...[
                  SizedBox(width: spacing.sm),
                  Squircle(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.md,
                      vertical: spacing.xs,
                    ),
                    borderRadius: radius.badge,
                    borderColor: colors.surfaceSubtle,
                    color: colors.surfaceSubtle,
                    child: Text('Max', style: type.badgeLabel),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
