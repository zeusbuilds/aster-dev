import 'package:flutter/material.dart';

import '../theme/theme.dart';

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
  final VoidCallback? onTap;

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
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (prefixIcon != null) ...[
              Icon(
                prefixIcon,
                size: spacing.iconSm,
                color: prefixIconColor ?? colors.textTertiary,
              ),
              SizedBox(width: spacing.sm),
            ],
            Expanded(
              child: Text(
                title,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: titleColor ?? colors.textTertiary,
                ),
              ),
            ),
            if (suffixIcon != null) ...[
              SizedBox(width: spacing.sm),
              Icon(
                suffixIcon,
                size: spacing.xl,
                color: suffixIconColor ?? colors.textTertiary,
              ),
            ],
            SizedBox(width: spacing.sm),
            Text(
              value,
              style: textTheme.bodyMedium
                  ?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? context.colorScheme.onSurface,
                  )
                  .toNumeric(context),
            ),
          ],
        ),
      ),
    );
  }
}
