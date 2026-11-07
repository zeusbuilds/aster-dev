import 'dart:async';

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../feedback/feedback.dart';
import '../layout/layout.dart';
import '../theme/theme.dart';
import 'amount_text.dart';

/// Accessible full-width action row for grouped option surfaces.
class AsterOptionRow extends StatelessWidget {
  const AsterOptionRow({
    super.key,
    required this.title,
    this.prefixIcon,
    this.details,
    this.amountDetails,
    this.suffixIcon,
    this.suffixIconColor,
    this.onTap,
    this.hapticIntent = HapticIntent.lightImpact,
  }) : toggleValue = null,
       onChanged = null,
       assert(details == null || amountDetails == null);

  /// A switch row using the same label geometry as ordinary option rows.
  /// The adaptive switch keeps its natural size and is not vertically padded.
  const AsterOptionRow.toggle({
    super.key,
    required this.title,
    required bool value,
    this.prefixIcon,
    this.onChanged,
    this.hapticIntent,
  }) : toggleValue = value,
       details = null,
       amountDetails = null,
       suffixIcon = null,
       suffixIconColor = null,
       onTap = null;

  final String title;
  final IconData? prefixIcon;
  final String? details;

  /// Formatted monetary detail. Only numeric spans use the numeric family.
  /// Mutually exclusive with ordinary [details] such as labels/identifiers.
  final String? amountDetails;
  final IconData? suffixIcon;
  final Color? suffixIconColor;
  final VoidCallback? onTap;
  final bool? toggleValue;
  final ValueChanged<bool>? onChanged;

  /// Tactile feedback emitted only after an enabled activation.
  final HapticIntent? hapticIntent;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final value = details ?? amountDetails;
    final isToggle = toggleValue != null;
    final enabled = isToggle ? onChanged != null : onTap != null;

    void activate() {
      if (hapticIntent case final intent?) {
        unawaited(context.haptics.trigger(intent));
      }
      if (isToggle) {
        onChanged?.call(!toggleValue!);
      } else {
        onTap?.call();
      }
    }

    return Semantics(
      button: !isToggle,
      toggled: toggleValue,
      enabled: enabled,
      label: value == null ? title : '$title, $value',
      onTap: enabled ? activate : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? activate : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: context.metrics.minTouchTarget,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: spacing.lg),
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
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final valueNeedsStack =
                                  value != null &&
                                  (unwrappedTextWidth(
                                            context,
                                            title,
                                            context.type.rowTitle,
                                          ) +
                                          unwrappedSpanWidth(
                                            context,
                                            TextSpan(
                                              style: context.type.rowValue,
                                              text: amountDetails == null
                                                  ? value
                                                  : null,
                                              children: amountDetails == null
                                                  ? null
                                                  : NumericTextSpans.build(
                                                      context,
                                                      value,
                                                      context.type.rowValue,
                                                    ),
                                            ),
                                          ) +
                                          spacing.lg >
                                      constraints.maxWidth);
                              final titleWidget = Text(
                                title,
                                style: context.type.rowTitle,
                              );
                              final valueWidget = value == null
                                  ? null
                                  : amountDetails != null
                                  ? AmountText(
                                      value,
                                      style: context.type.rowValue,
                                      textAlign: TextAlign.end,
                                    )
                                  : Text(
                                      value,
                                      style: context.type.rowValue,
                                      textAlign: TextAlign.end,
                                    );
                              return valueNeedsStack
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
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
                                    );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isToggle) ...[
                  SizedBox(width: spacing.sm),
                  // One keyboard/accessibility target for the full row; native
                  // pointer handling still supports both tapping and dragging.
                  ExcludeFocus(
                    child: Switch.adaptive(
                      value: toggleValue!,
                      onChanged: enabled ? (_) => activate() : null,
                    ),
                  ),
                ] else if (suffixIcon != null || onTap != null) ...[
                  SizedBox(width: spacing.sm),
                  Icon(
                    suffixIcon ?? RemixIcons.arrow_right_s_line,
                    size: context.icons.sm,
                    color: suffixIconColor ?? colors.textTertiary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
