import 'package:flutter/material.dart';

import 'package:country_flags/country_flags.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';

/// Card widget displaying send amount information
///
/// Shows amount, asset, market price, balance, and fiat currency selector
class SendCard extends StatelessWidget {
  /// Amount to send
  final String amount;

  /// Asset model to send
  final AssetModel asset;

  /// Current market price
  final String marketPrice;

  /// Current wallet balance
  final String balance;

  /// Fiat currency code (default: "USD")
  final String fiatCurrency;
  const SendCard({
    super.key,
    required this.amount,
    this.asset = AssetModel.bitcoin,
    required this.marketPrice,
    required this.balance,
    this.fiatCurrency = 'USD',
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final radius = context.radii;
    final textTheme = context.textTheme;

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
                ],
              ),
              SizedBox(height: spacing.xs),
              Row(
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
                width: spacing.xxl,
                height: spacing.xxl,
                child: CountryFlag.fromCountryCode(
                  'US',
                  theme: const ImageTheme(shape: Circle()),
                ),
              ),
              SizedBox(width: spacing.sm),
              Text(
                fiatCurrency,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.colorScheme.onSurface,
                ),
              ),
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
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context
                        .colorScheme
                        .surface, // Inverse color (background)
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
