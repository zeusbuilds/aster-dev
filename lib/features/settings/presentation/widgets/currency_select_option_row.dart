import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';

/// Widget representing a single currency option in the currency selection list
///
/// Shows currency flag, name, symbol, code, and selection indicator
class CurrencySelectOptionRow extends StatelessWidget {
  /// The currency model to display
  final FiatCurrency currency;

  /// Callback when the row is tapped
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
    final effectiveOnTap = selected ? null : onTap;

    return Semantics(
      button: true,
      enabled: effectiveOnTap != null,
      selected: selected,
      label: '${currency.name}, ${currency.symbol} ${currency.code}',
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
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: CustomRadio(
                      option: true,
                      selected: selected,
                      onChanged: (_) {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
