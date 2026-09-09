import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../theme/theme.dart';
import 'aster_icon_button.dart';
import 'aster_pill.dart';

/// Shared handle, aligned title, and optional close command for app sheets.
class AsterSheetHeader extends StatelessWidget {
  const AsterSheetHeader({
    super.key,
    required this.title,
    this.closeLabel,
    this.onClose,
  });

  final String title;
  final String? closeLabel;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: context.spacing.md),
        SizedBox(
          width: context.metrics.sheetHandleWidth,
          height: context.metrics.sheetHandleHeight,
          child: AsterPill(
            color: context.colorScheme.surfaceContainerHigh,
            child: const SizedBox.expand(),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            context.spacing.screenPadding,
            context.spacing.sm,
            context.spacing.sm,
            context.spacing.sm,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.metrics.minTouchTarget,
            ),
            child: Row(
              children: [
                Expanded(child: Text(title, style: context.type.title)),
                if (closeLabel case final label?)
                  AsterIconButton(
                    icon: RemixIcons.close_line,
                    tooltip: label,
                    onPressed: onClose,
                    hapticIntent: null,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
