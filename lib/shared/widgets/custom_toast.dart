import 'package:flutter/material.dart';

import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../feedback/toast_message.dart';
import '../theme/theme.dart';
import 'aster_icon_button.dart';
import 'squircle.dart';

/// Accessible visual presentation for one transient toast message.
class CustomToast extends StatelessWidget {
  const CustomToast({
    super.key,
    required this.title,
    required this.variant,
    required this.onDismiss,
    this.message,
  });

  final String title;
  final String? message;
  final ToastVariant variant;
  final VoidCallback onDismiss;

  IconData get _icon => switch (variant) {
    ToastVariant.success => MingCuteIcons.mgc_check_circle_fill,
    ToastVariant.failure => MingCuteIcons.mgc_close_circle_fill,
    ToastVariant.warning => MingCuteIcons.mgc_alert_fill,
    ToastVariant.info => MingCuteIcons.mgc_information_fill,
  };

  String get _semanticKind => switch (variant) {
    ToastVariant.success => 'Success',
    ToastVariant.failure => 'Error',
    ToastVariant.warning => 'Warning',
    ToastVariant.info => 'Information',
  };

  Color _iconColor(BuildContext context) => switch (variant) {
    ToastVariant.success => context.appColors.success,
    ToastVariant.failure => context.appColors.danger,
    ToastVariant.warning => context.appColors.warning,
    ToastVariant.info => context.colorScheme.primary,
  };

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final semanticLabel = [
      _semanticKind,
      title,
      if (message case final message? when message.isNotEmpty) message,
    ].join('. ');

    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: spacing.lg),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          liveRegion: true,
          label: semanticLabel,
          child: Squircle(
            color: context.colorScheme.surface,
            padding: EdgeInsets.symmetric(
              horizontal: spacing.lg,
              vertical: spacing.md,
            ),
            shadows: context.shadows.raised,
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    _icon,
                    color: _iconColor(context),
                    size: context.icons.md,
                  ),
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: context.type.toastTitle),
                        if (message case final message?
                            when message.isNotEmpty) ...[
                          SizedBox(height: spacing.xxs),
                          Text(message, style: context.type.toastMessage),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(width: spacing.sm),
                AsterIconButton(
                  onPressed: onDismiss,
                  tooltip: 'Dismiss',
                  icon: MingCuteIcons.mgc_close_line,
                  showTooltip: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
