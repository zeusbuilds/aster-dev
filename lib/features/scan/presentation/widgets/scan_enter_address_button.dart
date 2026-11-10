import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';

/// Keyboard- and semantics-operable manual-entry command below Scan.
class ScanEnterAddressButton extends StatelessWidget {
  const ScanEnterAddressButton({
    super.key,
    required this.onTap,
    this.label = 'Enter payment details to send',
  });

  final VoidCallback? onTap;
  final String label;

  static const _labelMaxLines = 2;

  /// Reserves enough room beneath the scanner frame for wrapped labels.
  static double heightForWidth(
    BuildContext context, {
    required String label,
    required double width,
  }) {
    final spacing = context.spacing;
    final iconSize = context.icons.sm;
    final painter = TextPainter(
      text: TextSpan(text: label, style: context.type.scanCta),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: _labelMaxLines,
      ellipsis: '…',
    );
    try {
      painter.layout(maxWidth: math.max(0.0, width - iconSize - spacing.xxs));
      return math.max(
        context.metrics.minTouchTarget,
        math.max(painter.height, iconSize) + spacing.md * 2,
      );
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final icons = context.icons;
    final stateLayers = context.stateLayers;
    final enabled = onTap != null;

    void activate() => onTap?.call();

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? activate : null,
      excludeSemantics: true,
      child: Material(
        color: colors.transparentSurface,
        child: InkWell(
          onTap: enabled ? activate : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.metrics.minTouchTarget,
            ),
            child: Opacity(
              opacity: enabled ? stateLayers.visible : stateLayers.disabled,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: spacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: context.type.scanCta,
                        maxLines: _labelMaxLines,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(width: spacing.xxs),
                    Icon(
                      RemixIcons.arrow_right_s_line,
                      color: context.type.scanCta.color,
                      size: icons.sm,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
