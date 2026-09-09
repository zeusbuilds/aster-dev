import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../feedback/feedback.dart';
import '../layout/layout.dart';
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trailingIcon = suffixIcon != null || onTap != null;
                final availableWidth =
                    constraints.maxWidth -
                    (prefixIcon == null ? 0 : context.icons.sm + spacing.md) -
                    (trailingIcon ? context.icons.sm + spacing.sm : 0);
                final value = details;
                final valueNeedsStack =
                    value != null &&
                    (unwrappedTextWidth(context, title, context.type.rowTitle) +
                            unwrappedTextWidth(
                              context,
                              value,
                              context.type.rowValue,
                            ) +
                            spacing.lg >
                        availableWidth);
                final titleWidget = Text(title, style: context.type.rowTitle);
                final valueWidget = value == null
                    ? null
                    : Text(
                        value,
                        style: context.type.rowValue,
                        textAlign: TextAlign.end,
                      );
                return Row(
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
                      child: valueNeedsStack
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                titleWidget,
                                SizedBox(height: spacing.xs),
                                valueWidget!,
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: titleWidget),
                                if (valueWidget != null) ...[
                                  SizedBox(width: spacing.lg),
                                  valueWidget,
                                ],
                              ],
                            ),
                    ),
                    if (trailingIcon) ...[
                      SizedBox(width: spacing.sm),
                      Icon(
                        suffixIcon ?? RemixIcons.arrow_right_s_line,
                        size: context.icons.sm,
                        color: suffixIconColor ?? colors.textTertiary,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
