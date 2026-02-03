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
    final colors = context.colors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.spacing20,
          vertical: spacing.spacing16,
        ),
        child: Row(
          children: [
            if (prefixIcon != null) ...[
              Icon(prefixIcon, size: spacing.spacing22, color: colors.text2),
              SizedBox(width: spacing.spacing10),
            ],
            Expanded(
              child: Text(
                title,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.text1,
                ),
                maxLines: 1,
              ),
            ),
            SizedBox(width: spacing.spacing16),
            if (details != null) ...[
              Text(
                details!,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.text1,
                ),
              ),
              SizedBox(width: spacing.spacing8),
            ],
            Icon(
              suffixIcon ?? RemixIcons.arrow_right_s_line,
              size: spacing.spacing18,
              color: suffixIconColor ?? colors.text3,
            ),
          ],
        ),
      ),
    );
  }
}
