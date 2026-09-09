import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../feedback/feedback.dart';
import '../theme/theme.dart';

/// Accessible full-width action row for grouped option surfaces.
class AsterOptionRow extends StatelessWidget {
  const AsterOptionRow({
    super.key,
    required this.title,
    this.prefixIcon,
    this.details,
    this.suffixIcon,
    this.suffixIconColor,
    this.onTap,
    this.hapticIntent = HapticIntent.lightImpact,
  });

  final String title;
  final IconData? prefixIcon;
  final String? details;
  final IconData? suffixIcon;
  final Color? suffixIconColor;
  final VoidCallback? onTap;

  /// Tactile feedback emitted only after an enabled activation.
  final HapticIntent? hapticIntent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;

    void activate() {
      if (hapticIntent case final intent?) {
        unawaited(context.haptics.trigger(intent));
      }
      onTap?.call();
    }

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: details == null ? title : '$title, $details',
      onTap: onTap == null ? null : activate,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap == null ? null : activate,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: context.metrics.minTouchTarget,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.screenPadding,
              vertical: spacing.lg,
            ),
            child: Row(
              children: [
                if (prefixIcon case final icon?) ...[
                  Icon(
                    icon,
                    size: context.icons.sm,
                    color: colors.textSecondary,
                  ),
                  SizedBox(width: spacing.md),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: context.type.rowTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (details != null || suffixIcon != null || onTap != null)
                  SizedBox(width: spacing.lg),
                if (details case final value?) ...[
                  Expanded(
                    child: Text(
                      value,
                      style: context.type.rowValue,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                ],
                if (suffixIcon != null || onTap != null)
                  Icon(
                    suffixIcon ?? RemixIcons.arrow_right_s_line,
                    size: context.icons.sm,
                    color: suffixIconColor ?? colors.textTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
