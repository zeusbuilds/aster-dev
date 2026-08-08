import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'amount_text.dart';

/// Reusable row widget for displaying key-value pairs with optional icons
///
/// Displays a title and value with optional prefix/suffix icons.
class DetailRow extends StatelessWidget {
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final Color? prefixIconColor;
  final Color? suffixIconColor;
  final Color? titleColor;
  final Color? valueColor;
  final String title;
  final String value;
  final EdgeInsets padding;

  const DetailRow({
    super.key,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixIconColor,
    this.suffixIconColor,
    this.titleColor,
    this.valueColor,
    required this.title,
    this.value = '',
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final icons = context.icons;
    final type = context.type;

    return Semantics(
      label: value.isEmpty ? title : '$title, $value',
      excludeSemantics: true,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (prefixIcon != null) ...[
              Icon(
                prefixIcon,
                size: icons.sm,
                color: prefixIconColor ?? colors.textTertiary,
              ),
              SizedBox(width: spacing.sm),
            ],
            Expanded(
              child: Text(
                title,
                style: type.rowMeta.copyWith(
                  color: titleColor ?? colors.textSecondary,
                ),
              ),
            ),
            if (suffixIcon != null) ...[
              SizedBox(width: spacing.sm),
              Icon(
                suffixIcon,
                size: icons.sm,
                color: suffixIconColor ?? colors.textTertiary,
              ),
            ],
            SizedBox(width: spacing.sm),
            AmountText(
              value,
              style: type.rowValue.copyWith(
                color: valueColor ?? context.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
