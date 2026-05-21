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
    final textTheme = context.textTheme;
    final radius = context.radii;

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
            GestureDetector(
              onTap: onAssetTap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    marketPrice,
                    style: textTheme.bodyMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textTertiary,
                        )
                        .toNumeric(context),
                  ),
                  const Spacer(),
                  SvgPicture.asset(
                    asset.icon,
                    width: spacing.iconLg,
                    height: spacing.iconLg,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.circle,
                      size: spacing.iconLg,
                      color: asset.themedColor(context),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Text(
                    asset.token,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(width: spacing.xs),
                  Icon(
                    RemixIcons.arrow_right_s_line,
                    size: spacing.screenPadding,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  amount,
                  style: textTheme.headlineSmall
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.colorScheme.onSurface,
                      )
                      .toNumeric(context),
                ),
                const Spacer(),
                Text.rich(
                  TextSpan(
                    text: 'Bal: ',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textTertiary,
                    ),
                    children: [
                      TextSpan(
                        text: balance,
                        style: textTheme.bodyMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.textTertiary,
                            )
                            .toNumeric(context),
                      ),
                    ],
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
                    child: Text(
                      'Max',
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: context.colorScheme.onSurface,
                      ),
                    ),
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
