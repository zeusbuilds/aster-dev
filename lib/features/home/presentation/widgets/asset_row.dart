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
    final icons = context.icons;
    final type = context.type;
    final metrics = context.metrics;

    return Semantics(
      button: true,
      label: '$name, $fiatBalance, $assetBalance',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async => context.push(RoutePaths.transactionList),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: metrics.minTouchTarget),
          child: Row(
            children: [
              Center(
                child: Icon(
                  icon,
                  color: iconColor ?? context.colorScheme.onSurface,
                  size: icons.xl,
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
                        Expanded(child: Text(name, style: type.assetTitle)),
                        AppSkeletonizer(
                          enabled: isLoading,
                          child: NumericText(
                            fiatBalance,
                            style: type.assetValue,
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
                            style: type.assetMeta.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                        AppSkeletonizer(
                          enabled: isLoading,
                          child: AmountText(
                            assetBalance,
                            style: type.assetMeta.copyWith(
                              color: colors.textTertiary,
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
        ),
      ),
    );
  }
}
