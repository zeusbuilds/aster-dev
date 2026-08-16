import 'package:flutter/material.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';
import 'wallet_asset_icon.dart';

/// Full-width asset-and-rail choice used by Send and Receive entry screens.
class PaymentTargetTile extends StatelessWidget {
  const PaymentTargetTile({
    super.key,
    required this.capability,
    this.onSelected,
  });

  /// Deployment-resolved support for this asset and payment rail.
  final WalletPaymentCapability capability;

  /// Selection owner, or `null` for a noninteractive placeholder.
  final ValueChanged<WalletPaymentTarget>? onSelected;

  @override
  Widget build(BuildContext context) {
    final target = capability.target;
    final configured = capability.isAvailable;
    final enabled = configured && onSelected != null;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(context.radii.card),
      side: BorderSide(
        color: context.appColors.borderSubtle,
        width: context.strokes.border,
      ),
    );

    void select() {
      onSelected?.call(target);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: target.semanticLabel,
      value: configured ? null : 'Not configured',
      onTap: enabled ? select : null,
      excludeSemantics: true,
      child: Opacity(
        opacity: configured
            ? context.stateLayers.visible
            : context.stateLayers.disabled,
        child: Material(
          color: context.colorScheme.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? select : null,
            customBorder: shape,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: context.metrics.paymentTargetTileMinHeight,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.spacing.lg,
                  vertical: context.spacing.md,
                ),
                child: Row(
                  children: [
                    WalletAssetIcon(
                      kind: target.assetKind,
                      size: context.icons.xl,
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
                            configured
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
                    if (enabled) ...[
                      SizedBox(width: context.spacing.sm),
                      Icon(
                        MingCuteIcons.mgc_right_line,
                        size: context.icons.sm,
                        color: context.appColors.textTertiary,
                      ),
                    ],
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
