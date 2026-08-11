import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

/// Full-width asset-and-rail choice used by Send and Receive entry screens.
class PaymentTargetTile extends StatelessWidget {
  const PaymentTargetTile({
    super.key,
    required this.capability,
    required this.onSelected,
  });

  final WalletPaymentCapability capability;
  final ValueChanged<WalletPaymentTarget> onSelected;

  @override
  Widget build(BuildContext context) {
    final target = capability.target;
    final available = capability.isAvailable;
    final asset = target.assetModel;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(context.radii.card),
      side: BorderSide(
        color: context.appColors.borderSubtle,
        width: context.strokes.border,
      ),
    );

    void select() {
      unawaited(context.haptics.trigger(HapticIntent.selection));
      onSelected(target);
    }

    return Semantics(
      button: true,
      enabled: available,
      label: target.semanticLabel,
      value: available ? null : 'Not configured',
      onTap: available ? select : null,
      excludeSemantics: true,
      child: Opacity(
        opacity: available ? 1 : context.stateLayers.disabled,
        child: Material(
          color: context.colorScheme.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: available ? select : null,
            customBorder: shape,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: context.metrics.selectionIndicatorHeight,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.spacing.lg,
                  vertical: context.spacing.md,
                ),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      asset.icon,
                      width: context.icons.xl,
                      height: context.icons.xl,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.circle,
                        size: context.icons.xl,
                        color: AssetDisplay.colorOf(context, asset),
                      ),
                    ),
                    SizedBox(width: context.spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(target.assetLabel, style: context.type.title),
                          SizedBox(height: context.spacing.xxs),
                          Text(
                            available
                                ? target.railLabel
                                : '${target.railLabel} - Not configured',
                            style: context.type.rowMeta.copyWith(
                              color: context.appColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (target.rail == PaymentRail.lightning) ...[
                      SizedBox(width: context.spacing.sm),
                      Icon(
                        MingCuteIcons.mgc_flash_fill,
                        size: context.icons.sm,
                        color: context.appColors.bitcoin,
                      ),
                    ],
                    SizedBox(width: context.spacing.sm),
                    Icon(
                      MingCuteIcons.mgc_right_line,
                      size: context.icons.sm,
                      color: context.appColors.textTertiary,
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
