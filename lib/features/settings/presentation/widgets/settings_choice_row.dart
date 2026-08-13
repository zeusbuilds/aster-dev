import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Accessible single-choice settings row with app-standard radio treatment.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final effectiveOnTap = selected ? null : onTap;
    return Semantics(
      button: true,
      enabled: effectiveOnTap != null,
      selected: selected,
      label: '$title, $subtitle',
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.type.rowTitle),
                      Text(subtitle, style: context.type.supportingMeta),
                    ],
                  ),
                ),
                SizedBox(width: spacing.xxl),
                AsterSelectionIndicator(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
