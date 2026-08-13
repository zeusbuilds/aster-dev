import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';

/// Accessible single-choice row for one supported region.
class CountrySelectOptionRow extends StatelessWidget {
  final Region country;

  final VoidCallback? onTap;

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
    final available = onTap != null;
    final effectiveOnTap = available && !selected ? onTap : null;

    return Semantics(
      button: true,
      enabled: available,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: country.name,
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
                CircleFlag(country.code, size: metrics.flagSize),
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
                AsterSelectionIndicator(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
