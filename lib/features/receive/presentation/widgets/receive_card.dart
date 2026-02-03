import 'package:flutter/material.dart';

import 'package:country_flags/country_flags.dart';
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
    final colors = context.colors;
    final textTheme = context.textTheme;
    final radius = context.radius;

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
                  Icon(
                    UniconsLine.bitcoin,
                    size: spacing.spacing36,
                    color: Colors.orange,
                  ),
                  SizedBox(width: spacing.spacing8),
                  Text(
                    asset,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.text1,
                    ),
                  ),
                ],
              ),
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
                    color: colors.fill1,
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
