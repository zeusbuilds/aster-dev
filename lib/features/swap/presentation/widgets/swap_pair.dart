import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:remixicon/remixicon.dart';

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
    final colors = context.colors;
    final textTheme = context.textTheme;
    final radius = context.radius;

    return Squircle(
      padding: EdgeInsets.zero,
      borderColor: Colors.transparent,
      border: from
          ? null
          : BorderRadius.only(
              bottomLeft: Radius.circular(radius.radius24),
              bottomRight: Radius.circular(radius.radius24),
            ),
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: spacing.spacing12,
          horizontal: spacing.spacing16,
        ),
        color: from ? Colors.transparent : colors.fill2,
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
                          color: colors.text3,
                        )
                        .toNumeric(context),
                  ),
                  const Spacer(),
                  SvgPicture.asset(
                    asset.icon,
                    width: spacing.spacing36,
                    height: spacing.spacing36,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.circle,
                      size: spacing.spacing36,
                      color: Color(asset.color),
                    ),
                  ),
                  SizedBox(width: spacing.spacing8),
                  Text(
                    asset.token,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.text1,
                    ),
                  ),
                  SizedBox(width: spacing.spacing4),
                  Icon(
                    RemixIcons.arrow_right_s_line,
                    size: spacing.spacing20,
                    color: colors.text3,
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
                        color: colors.text1,
                      )
                      .toNumeric(context),
                ),
                const Spacer(),
                Text.rich(
                  TextSpan(
                    text: 'Bal: ',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.text3,
                    ),
                    children: [
                      TextSpan(
                        text: balance,
                        style: textTheme.bodyMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.text3,
                            )
                            .toNumeric(context),
                      ),
                    ],
                  ),
                ),
                if (from) ...[
                  SizedBox(width: spacing.spacing8),
                  Squircle(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.spacing12,
                      vertical: spacing.spacing4,
                    ),
                    borderRadius: radius.radius8,
                    borderColor: colors.fill2,
                    color: colors.fill2,
                    child: Text(
                      'Max',
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.text1,
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
