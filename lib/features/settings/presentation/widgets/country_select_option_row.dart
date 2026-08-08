import 'dart:async';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

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
    final effectiveOnTap = selected ? null : onTap;

    void select() {
      unawaited(context.haptics.trigger(HapticIntent.selection));
      effectiveOnTap?.call();
    }

    return Semantics(
      button: true,
      enabled: effectiveOnTap != null,
      selected: selected,
      label: country.name,
      excludeSemantics: true,
      child: Material(
        color: context.appColors.transparentSurface,
        child: InkWell(
          onTap: effectiveOnTap == null ? null : select,
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
