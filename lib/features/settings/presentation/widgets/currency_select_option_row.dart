import 'package:flutter/material.dart';

import 'package:circle_flags/circle_flags.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../../shared/shared.dart';

/// Widget representing a single currency option in the currency selection list
///
/// Shows currency flag, name, symbol, code, and selection indicator
class CurrencySelectOptionRow extends StatelessWidget {
  /// The currency model to display
  final CurrencyModel currency;

  /// Callback when the row is tapped
  final VoidCallback? onTap;

  /// Selection state (-1 for unselected, 0 for selected)
  final int selected;

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

    return Semantics(
      button: onTap != null,
      selected: selected == 0,
      label: '${currency.name}, ${currency.symbol} ${currency.code}',
      child: GestureDetector(
        onTapDown: onTap != null
            ? (_) async {
                final canVibrate = await Haptics.canVibrate();
                if (canVibrate) {
                  await Haptics.vibrate(HapticsType.selection);
                }
              }
            : null,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
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
              CustomRadio(
                option: 0,
                selected: selected,
                onChanged: (value) {
                  onTap?.call();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
