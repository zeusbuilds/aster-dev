import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../../shared/shared.dart';

/// Widget representing a single country option in the country selection list
///
/// Shows country flag, name, and selection indicator
class CountrySelectOptionRow extends StatelessWidget {
  /// The country model to display
  final CountryModel country;

  /// Callback when the row is tapped
  final VoidCallback? onTap;

  /// Whether this country is currently selected
  final bool selected;

  const CountrySelectOptionRow({
    super.key,
    required this.country,
    this.onTap,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final type = context.type;
    final metrics = context.metrics;

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: country.name,
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
              CountryFlag.fromCountryCode(
                country.code,
                theme: ImageTheme(
                  shape: Circle(),
                  height: metrics.flagSize,
                  width: metrics.flagSize,
                ),
              ),
              SizedBox(width: spacing.lg),
              Expanded(
                child: Text(
                  country.name,
                  style: type.rowTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: spacing.xxxl),
              CustomRadio(
                option: 1,
                selected: selected ? 1 : 0,
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
