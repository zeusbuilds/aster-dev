import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';

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
    final colors = context.colors;
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
                size: spacing.spacing22,
                color: prefixIconColor ?? colors.text3,
              ),
              SizedBox(width: spacing.spacing8),
            ],
            Expanded(
              child: Text(
                title,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: titleColor ?? colors.text3,
                ),
              ),
            ),
            if (suffixIcon != null) ...[
              SizedBox(width: spacing.spacing8),
              Icon(
                suffixIcon,
                size: spacing.spacing18,
                color: suffixIconColor ?? colors.text3,
              ),
            ],
            SizedBox(width: spacing.spacing8),
            Text(
              value,
              style: textTheme.bodyMedium
                  ?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? colors.text1,
                  )
                  .toNumeric(context),
            ),
          ],
        ),
      ),
    );
  }
}
