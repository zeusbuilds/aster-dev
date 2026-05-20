import 'package:flutter/material.dart';

import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';

/// Reusable row widget for settings options
///
/// Displays title, optional icon, details, and navigation indicator
class SettingsOptionRow extends StatelessWidget {
  /// Title text to display
  final String title;

  /// Optional prefix icon
  final IconData? prefixIcon;

  /// Optional details text (displayed on the right)
  final String? details;

  /// Optional suffix icon (defaults to right arrow)
  final IconData? suffixIcon;

  /// Color for suffix icon
  final Color? suffixIconColor;

  /// Callback when row is tapped
  final VoidCallback? onTap;

  const SettingsOptionRow({
    super.key,
    required this.title,
    this.prefixIcon,
    this.details,
    this.suffixIcon,
    this.suffixIconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.screenPadding,
          vertical: spacing.lg,
        ),
        child: Row(
          children: [
            if (prefixIcon != null) ...[
              Icon(
                prefixIcon,
                size: spacing.iconSm,
                color: colors.textSecondary,
              ),
              SizedBox(width: spacing.md),
            ],
            Expanded(
              child: Text(
                title,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: context.colorScheme.onSurface,
                ),
                maxLines: 1,
              ),
            ),
            SizedBox(width: spacing.lg),
            if (details != null) ...[
              Text(
                details!,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.colorScheme.onSurface,
                ),
              ),
              SizedBox(width: spacing.sm),
            ],
            Icon(
              suffixIcon ?? RemixIcons.arrow_right_s_line,
              size: spacing.xl,
              color: suffixIconColor ?? colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
