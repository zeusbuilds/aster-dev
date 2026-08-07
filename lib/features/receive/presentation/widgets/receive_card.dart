import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:unicons/unicons.dart';

import '../../../../shared/shared.dart';

/// Card widget displaying receive amount information
///
/// Shows amount, asset, market price, balance, and fiat currency selector
class ReceiveCard extends StatelessWidget {
  /// Amount to receive
  final String amount;

  /// Asset symbol (e.g., "BTC")
  final String asset;

  /// Current market price
  final String marketPrice;

  /// Current wallet balance
  final String balance;

  /// Fiat currency code (default: "USD")
  final String fiatCurrency;
  const ReceiveCard({
    super.key,
    required this.amount,
    required this.asset,
    required this.marketPrice,
    required this.balance,
    this.fiatCurrency = 'USD',
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final radius = context.radii;
    final icons = context.icons;
    final type = context.type;
    final metrics = context.metrics;

    return Column(
      children: [
        Squircle(
          border: BorderRadius.only(
            topLeft: Radius.circular(radius.card),
            topRight: Radius.circular(radius.card),
          ),
          padding: EdgeInsets.symmetric(
            vertical: spacing.lg,
            horizontal: spacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  NumericText(amount, style: type.amountLarge),
                  const Spacer(),
                  Icon(
                    UniconsLine.bitcoin,
                    size: icons.lg,
                    color: colors.bitcoin,
                  ),
                  SizedBox(width: spacing.sm),
                  Text(asset, style: type.title),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  NumericText(
                    marketPrice,
                    style: type.rowMetaStrong.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  AmountText(
                    'Bal: $balance',
                    style: type.rowMetaStrong.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Squircle(
          color: colors.surfaceSubtle,
          borderColor: colors.surfaceSubtle,
          border: BorderRadius.only(
            bottomLeft: Radius.circular(radius.card),
            bottomRight: Radius.circular(radius.card),
          ),
          padding: EdgeInsets.symmetric(
            vertical: spacing.lg,
            horizontal: spacing.xl,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: metrics.compactFlagSize,
                height: metrics.compactFlagSize,
                child: CountryFlag.fromCountryCode(
                  'US',
                  theme: const ImageTheme(shape: Circle()),
                ),
              ),
              SizedBox(width: spacing.sm),
              Text(fiatCurrency, style: type.rowTitleStrong),
              const Spacer(),
              Squircle(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.md,
                  vertical: spacing.xs,
                ),
                borderRadius: radius.badge,
                borderColor: context.colorScheme.onSurface,
                color: context.colorScheme.onSurface,
                child: Text(
                  'Send max',
                  style: type.badgeLabel.copyWith(
                    color: context.colorScheme.surface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
