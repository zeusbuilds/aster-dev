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
    this.selected,
  });

  /// Deployment-resolved support for this asset and payment rail.
  final WalletPaymentCapability capability;

  /// Selection owner, or `null` for a noninteractive placeholder.
  final ValueChanged<WalletPaymentTarget>? onSelected;

  /// Inline selection state. A null value keeps the route navigation style.
  final bool? selected;

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
      selected: selected,
      label: target.semanticLabel,
      value: capability.unavailableReason,
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
                  horizontal: context.spacing.xl,
                  vertical: context.spacing.lg,
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
                                : '${target.railLabel} - ${capability.unavailableReason}',
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
                    if (selected case final isSelected? when configured) ...[
                      SizedBox(width: context.spacing.sm),
                      AsterSelectionIndicator(selected: isSelected),
                    ] else if (enabled) ...[
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
