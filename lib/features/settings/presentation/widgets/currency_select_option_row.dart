import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';

/// Accessible single-choice row for one supported fiat currency.
class CurrencySelectOptionRow extends StatelessWidget {
  final FiatCurrency currency;

  final VoidCallback? onTap;

  /// Whether this currency is currently selected.
  final bool selected;

  const CurrencySelectOptionRow({
    super.key,
    required this.currency,
    this.onTap,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final metrics = context.metrics;
    final type = context.type;
    final available = onTap != null;
    final effectiveOnTap = available && !selected ? onTap : null;

    return Semantics(
      button: true,
      enabled: available,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${currency.name}, ${currency.symbol} ${currency.code}',
      onTap: effectiveOnTap,
      excludeSemantics: true,
      child: Material(
        color: context.appColors.transparentSurface,
        child: InkWell(
          onTap: effectiveOnTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.screenPadding,
              vertical: spacing.lg,
            ),
            child: Row(
              children: [
                CircleFlag(currency.countryCode, size: metrics.flagSize),
                SizedBox(width: spacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currency.name,
                        style: type.rowTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${currency.symbol} ${currency.code}',
                        style: type.supportingMeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: spacing.xxxl),
                AsterSelectionIndicator(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
