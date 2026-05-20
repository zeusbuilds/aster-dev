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
    final colors = context.appColors;
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
          horizontal: spacing.screenPadding,
          vertical: spacing.lg,
        ),
        child: Row(
          children: [
            // CountryFlag.fromCountryCode(
            //   currency.countryCode,
            //   theme: ImageTheme(
            //     shape: Circle(),
            //     height: spacing.xxxl,
            //     width: spacing.xxxl,
            //   ),
            // ),
            CircleFlag(currency.countryCode, size: spacing.xxxl),
            SizedBox(width: spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currency.name,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: context.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // SizedBox(height: spacing.xs),
                  Text(
                    '${currency.symbol} ${currency.code}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
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
    );
  }
}
