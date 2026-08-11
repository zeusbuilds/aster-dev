import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/models/models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';

/// Bottom sheet for choosing one configured asset-and-rail target.
class AssetSelectorSheet extends StatelessWidget {
  const AssetSelectorSheet({
    super.key,
    required this.capabilities,
    required this.selected,
    required this.otherSelection,
    required this.onSelected,
  });

  final List<WalletPaymentCapability> capabilities;
  final WalletPaymentTarget selected;
  final WalletPaymentTarget otherSelection;
  final ValueChanged<WalletPaymentTarget> onSelected;

  static Future<WalletPaymentTarget?> show(
    BuildContext context, {
    required List<WalletPaymentCapability> capabilities,
    required WalletPaymentTarget selected,
    required WalletPaymentTarget otherSelection,
  }) {
    return showModalBottomSheet<WalletPaymentTarget>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.transparentSurface,
      builder: (context) => AssetSelectorSheet(
        capabilities: capabilities,
        selected: selected,
        otherSelection: otherSelection,
        onSelected: (target) => Navigator.of(context).pop(target),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maximumHeight =
        MediaQuery.sizeOf(context).height *
        context.metrics.sheetMaxHeightFactor;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maximumHeight),
      child: Squircle(
        color: context.colorScheme.surface,
        border: BorderRadius.vertical(
          top: Radius.circular(context.radii.sheet),
        ),
        borderColor: context.appColors.transparentSurface,
        borderWidth: 0,
        padding: EdgeInsets.zero,
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: context.spacing.lg),
          child: Column(
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
              SizedBox(height: context.spacing.lg),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.spacing.screenPadding,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select asset and network',
                    style: context.type.title,
                  ),
                ),
              ),
              SizedBox(height: context.spacing.md),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: capabilities.length,
                  itemBuilder: (context, index) {
                    final capability = capabilities[index];
                    return _AssetTargetItem(
                      capability: capability,
                      selected: capability.target == selected,
                      conflictsWithOther: capability.target == otherSelection,
                      onTap: () => onSelected(capability.target),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetTargetItem extends StatelessWidget {
  const _AssetTargetItem({
    required this.capability,
    required this.selected,
    required this.conflictsWithOther,
    required this.onTap,
  });

  final WalletPaymentCapability capability;
  final bool selected;
  final bool conflictsWithOther;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = capability.isAvailable && !selected && !conflictsWithOther;
    final target = capability.target;

    void select() {
      unawaited(context.haptics.trigger(HapticIntent.selection));
      onTap();
    }

    final status = !capability.isAvailable
        ? 'Not configured'
        : conflictsWithOther
        ? 'Already selected'
        : target.railLabel;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: target.semanticLabel,
      value: selected ? 'Selected' : status,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled || selected ? 1 : context.stateLayers.disabled,
        child: InkWell(
          onTap: enabled ? select : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.metrics.minTouchTarget,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.spacing.screenPadding,
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
                          status,
                          style: context.type.rowMeta.copyWith(
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check,
                      size: context.icons.sm,
                      color: context.colorScheme.primary,
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
