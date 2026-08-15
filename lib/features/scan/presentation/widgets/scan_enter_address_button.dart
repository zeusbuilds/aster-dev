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
                      maxLines: 2,
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
    );
  }
}
