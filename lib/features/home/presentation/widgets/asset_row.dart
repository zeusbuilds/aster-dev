import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';

/// Widget displaying a single asset row with name, balance, and icon
///
/// Navigates to transaction list when tapped
class AssetRow extends StatelessWidget {
  /// Asset name (e.g., "BTC", "LBTC")
  final String name;

  /// Denomination unit (e.g., "sats")
  final String denomination;

  /// Fiat currency balance display
  final String fiatBalance;

  /// Asset balance display
  final String assetBalance;

  /// Icon to display for the asset
  final IconData icon;

  /// Color of the asset icon
  final Color? iconColor;

  /// Whether to show skeleton loading for balances
  final bool isLoading;

  const AssetRow({
    super.key,
    required this.name,
    required this.denomination,
    required this.fiatBalance,
    required this.assetBalance,
    required this.icon,
    this.iconColor,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return GestureDetector(
      onTap: () {
        context.push(RoutePaths.transactionList);
      },
      child: Row(
        children: [
          Center(
            child: Icon(
              icon,
              color: iconColor ?? context.colorScheme.onSurface,
              size: spacing.iconXl,
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    AppSkeletonizer(
                      enabled: isLoading,
                      child: Text(
                        fiatBalance,
                        style: textTheme.bodyLarge
                            ?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: context.colorScheme.onSurface,
                            )
                            .toNumeric(context),
                      ),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        denomination,
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                    AppSkeletonizer(
                      enabled: isLoading,
                      child: RichText(
                        text: TextSpan(
                          children: _buildBalanceSpans(
                            context,
                            assetBalance,
                            textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds text spans for balance display with proper numeric formatting
  ///
  /// Separates numeric value from currency unit for styling
  List<TextSpan> _buildBalanceSpans(
    BuildContext context,
    String balance,
    TextStyle? baseTextStyle,
  ) {
    final colors = context.appColors;
    final baseStyle = baseTextStyle?.copyWith(
      fontWeight: FontWeight.w500,
      color: colors.textTertiary,
    );

    // Split at first space to separate numeric value from currency
    final parts = balance.split(' ');

    if (parts.length >= 2) {
      final numericPart = parts[0];
      final currencyPart = parts.sublist(1).join(' ');

      return [
        TextSpan(text: numericPart, style: baseStyle?.toNumeric(context)),
        TextSpan(text: ' $currencyPart', style: baseStyle),
      ];
    } else {
      // No space found, treat entire string as numeric
      return [TextSpan(text: balance, style: baseStyle?.toNumeric(context))];
    }
  }
}
