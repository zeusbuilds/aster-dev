import 'package:aster/shared/shared.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    final colors = context.colors;
    final spacing = context.spacing;
    final radius = context.radius;
    final textTheme = context.textTheme;

    return Column(
      children: [
        Squircle(
          border: BorderRadius.only(
            topLeft: Radius.circular(radius.radius24),
            topRight: Radius.circular(radius.radius24),
          ),
          padding: EdgeInsets.symmetric(
            vertical: spacing.spacing16,
            horizontal: spacing.spacing18,
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
                          color: colors.text1,
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
                ],
              ),
              SizedBox(height: spacing.spacing4),
              Row(
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
                ],
              ),
            ],
          ),
        ),
        Squircle(
          color: colors.fill2,
          borderColor: colors.fill2,
          border: BorderRadius.only(
            bottomLeft: Radius.circular(radius.radius24),
            bottomRight: Radius.circular(radius.radius24),
          ),
          padding: EdgeInsets.symmetric(
            vertical: spacing.spacing16,
            horizontal: spacing.spacing18,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: spacing.spacing24,
                height: spacing.spacing24,
                child: CountryFlag.fromCountryCode(
                  'US',
                  theme: const ImageTheme(shape: Circle()),
                ),
              ),
              SizedBox(width: spacing.spacing8),
              Text(
                fiatCurrency,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.text1,
                ),
              ),
              const Spacer(),
              Squircle(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.spacing12,
                  vertical: spacing.spacing4,
                ),
                borderRadius: radius.radius8,
                borderColor: colors.text1,
                color: colors.text1,
                child: Text(
                  'Send max',
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.fill1, // Inverse color (background)
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
