import 'dart:async';

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

  /// Semantic tactile feedback emitted after an accepted activation.
  final HapticIntent hapticIntent;

  const SettingsOptionRow({
    super.key,
    required this.title,
    this.prefixIcon,
    this.details,
    this.suffixIcon,
    this.suffixIconColor,
    this.onTap,
    this.hapticIntent = HapticIntent.lightImpact,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final icons = context.icons;
    final type = context.type;

    void activate() {
      unawaited(context.haptics.trigger(hapticIntent));
      onTap?.call();
    }

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: details == null ? title : '$title, $details',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap == null ? null : activate,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.screenPadding,
            vertical: spacing.lg,
          ),
          child: Row(
            children: [
              if (prefixIcon != null) ...[
                Icon(prefixIcon, size: icons.sm, color: colors.textSecondary),
                SizedBox(width: spacing.md),
              ],
              Expanded(child: Text(title, style: type.rowTitle, maxLines: 1)),
              SizedBox(width: spacing.lg),
              if (details != null) ...[
                Flexible(
                  child: Text(
                    details!,
                    style: type.rowValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: spacing.sm),
              ],
              Icon(
                suffixIcon ?? RemixIcons.arrow_right_s_line,
                size: icons.sm,
                color: suffixIconColor ?? colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
