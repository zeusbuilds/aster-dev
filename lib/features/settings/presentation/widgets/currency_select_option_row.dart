import 'package:flutter/material.dart';

import 'package:circle_flags/circle_flags.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import 'package:aster/shared/shared.dart';

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
    final colors = context.colors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return GestureDetector(
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
          horizontal: spacing.spacing20,
          vertical: spacing.spacing16,
        ),
        child: Row(
          children: [
            // CountryFlag.fromCountryCode(
            //   currency.countryCode,
            //   theme: ImageTheme(
            //     shape: Circle(),
            //     height: spacing.spacing28,
            //     width: spacing.spacing28,
            //   ),
            // ),
            CircleFlag(currency.countryCode, size: spacing.spacing28),
            SizedBox(width: spacing.spacing16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currency.name,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.text1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // SizedBox(height: spacing.spacing4),
                  Text(
                    '${currency.symbol} ${currency.code}',
                    style: textTheme.bodySmall?.copyWith(color: colors.text2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.spacing32),
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
    );
  }
}
