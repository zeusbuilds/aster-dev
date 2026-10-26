import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layout/layout.dart';
import '../theme/theme.dart';
import 'custom_button.dart';

/// Shared confirmation geometry for deliberate, consequential actions.
class AsterConfirmationDialog extends StatelessWidget {
  const AsterConfirmationDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmText,
    this.confirmVariant = ButtonVariant.primary,
  });

  final String title;
  final Widget content;
  final String confirmText;
  final ButtonVariant confirmVariant;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildDialog);

  Widget _buildDialog(BuildContext context, BoxConstraints constraints) {
    const innerPadding = 22.0;
    final spacing = context.spacing;
    final theme = Theme.of(context);
    final dialogTheme = DialogTheme.of(context);
    final inset =
        dialogTheme.insetPadding ??
        EdgeInsets.symmetric(horizontal: spacing.xxl, vertical: spacing.xxl);
    final dialogWidth = math.max(
      0.0,
      math.min(
        constraints.maxWidth -
            inset.horizontal -
            MediaQuery.viewInsetsOf(context).horizontal,
        dialogTheme.constraints?.maxWidth ?? double.infinity,
      ),
    );
    final actionWidth = math.max(0.0, dialogWidth - innerPadding * 2);
    final cancelSize = unwrappedSpanSize(
      context,
      TextSpan(text: 'Cancel', style: context.type.buttonLabel),
    );
    final confirmSize = unwrappedSpanSize(
      context,
      TextSpan(text: confirmText, style: context.type.buttonLabel),
    );
    final longestLabel = math.max(cancelSize.width, confirmSize.width);
    final minimumActionWidth =
        2 * (longestLabel + spacing.xxl * 2) + spacing.md;
    final stacked = actionWidth < minimumActionWidth;
    final cancel = CustomButton(
      text: 'Cancel',
      variant: ButtonVariant.tonal,
      onTap: () => Navigator.of(context).pop(false),
    );
    final confirm = CustomButton(
      text: confirmText,
      variant: confirmVariant,
      onTap: () => Navigator.of(context).pop(true),
    );
    final actionLayout = stacked
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              cancel,
              SizedBox(height: spacing.md),
              confirm,
            ],
          )
        : Row(
            children: [
              Expanded(child: cancel),
              SizedBox(width: spacing.md),
              Expanded(child: confirm),
            ],
          );
    final buttonHeight = math.max(
      context.metrics.buttonHeight,
      math.max(cancelSize.height, confirmSize.height) + spacing.sm * 2,
    );
    final buttonWidth = stacked ? actionWidth : (actionWidth - spacing.md) / 2;
    final buttonSidePadding = math.min(
      spacing.xxl,
      math.max(0.0, (buttonWidth - longestLabel) / 2),
    );
    return AlertDialog(
      insetPadding: inset,
      constraints: BoxConstraints.tightFor(width: dialogWidth),
      scrollable: true,
      title: Text(title),
      titlePadding: const EdgeInsets.fromLTRB(
        innerPadding,
        innerPadding,
        innerPadding,
        0,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        innerPadding,
        spacing.sm,
        innerPadding,
        spacing.xxxl + spacing.sm,
      ),
      content: content,
      actionsPadding: const EdgeInsets.fromLTRB(
        innerPadding,
        0,
        innerPadding,
        innerPadding,
      ),
      buttonPadding: EdgeInsets.zero,
      actions: [
        // Measure the available space outside AlertDialog's intrinsic layout.
        // Inside it, standard buttons have finite geometry at every text size.
        SizedBox(
          width: actionWidth,
          child: Theme(
            data: theme.copyWith(
              extensions: [
                ...theme.extensions.values.where(
                  (extension) =>
                      extension is! AsterComponentMetrics &&
                      extension is! AsterSpacing,
                ),
                context.metrics.copyWith(buttonHeight: buttonHeight),
                spacing.copyWith(xxl: buttonSidePadding),
              ],
            ),
            child: actionLayout,
          ),
        ),
      ],
    );
  }
}
