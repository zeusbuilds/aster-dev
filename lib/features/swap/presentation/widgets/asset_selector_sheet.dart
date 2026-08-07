import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../../shared/shared.dart';

/// Bottom sheet for selecting an asset
class AssetSelectorSheet extends StatelessWidget {
  final List<AssetModel> assets;
  final String? selectedAssetName;
  final ValueChanged<AssetModel> onAssetSelected;

  const AssetSelectorSheet({
    super.key,
    required this.assets,
    this.selectedAssetName,
    required this.onAssetSelected,
  });

  /// Shows the asset selector as a modal bottom sheet
  ///
  /// [context] - Build context for showing the bottom sheet
  ///
  /// [assets] - List of available assets to choose from
  ///
  /// [selectedAssetName] - Currently selected asset name (for highlighting)
  ///
  /// Returns the selected asset or null if dismissed
  static Future<AssetModel?> show(
    BuildContext context, {
    required List<AssetModel> assets,
    String? selectedAssetName,
  }) {
    final colors = context.appColors;
    final motion = context.motion;
    return showModalBottomSheet<AssetModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.transparentSurface,
      builder: (context) => AssetSelectorSheet(
        assets: assets,
        selectedAssetName: selectedAssetName,
        onAssetSelected: (asset) async {
          await Future<void>.delayed(motion.selectionCommitDelay);
          if (context.mounted) {
            Navigator.of(context).pop(asset);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radii;
    final metrics = context.metrics;
    final type = context.type;
    final maxHeight =
        MediaQuery.of(context).size.height * metrics.sheetMaxHeightFactor;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: context.colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius.card)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: spacing.md),
          // Handle bar
          Container(
            width: metrics.sheetHandleWidth,
            height: metrics.sheetHandleHeight,
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(radius.pill),
            ),
          ),
          SizedBox(height: spacing.lg),
          // Title
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
            child: Text('Select token', style: type.title),
          ),
          SizedBox(height: spacing.lg),
          // Asset list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: assets.length,
              padding: EdgeInsets.only(bottom: spacing.bottomSafeRaw(context)),
              itemBuilder: (context, index) {
                final asset = assets[index];
                final isSelected =
                    asset.token == selectedAssetName ||
                    asset.unit == selectedAssetName;

                return Padding(
                  padding: EdgeInsets.only(bottom: spacing.xs),
                  child: _AssetItem(
                    asset: asset,
                    isSelected: isSelected,
                    onTap: () => onAssetSelected(asset),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual asset item in the selector list
///
/// Displays asset icon, name, chain, and balance information
class _AssetItem extends StatelessWidget {
  /// Asset model to display
  final AssetModel asset;

  /// Whether this asset is currently selected
  final bool isSelected;

  /// Callback when asset is tapped
  final VoidCallback onTap;

  const _AssetItem({
    required this.asset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final motion = context.motion;
    final spacing = context.spacing;
    final radius = context.radii;
    final icons = context.icons;
    final metrics = context.metrics;
    final stateLayers = context.stateLayers;
    final type = context.type;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${asset.token}, ${asset.chain}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) async {
          final canVibrate = await Haptics.canVibrate();
          if (canVibrate) {
            await Haptics.vibrate(HapticsType.light);
          }
        },
        onTap: onTap,
        child: AnimatedContainer(
          duration: motion.selectionTransitionDuration,
          curve: motion.fastEase,
          padding: EdgeInsets.symmetric(vertical: spacing.xs),
          decoration: BoxDecoration(
            color: isSelected
                ? context.colorScheme.primaryContainer.withValues(
                    alpha: stateLayers.selectedContainer,
                  )
                : context.colorScheme.surface,
          ),
          child: Row(
            children: [
              SizedBox(width: spacing.sm),
              // Selection indicator bar
              Container(
                width: metrics.selectionIndicatorWidth,
                height: metrics.selectionIndicatorHeight,
                decoration: BoxDecoration(
                  color: isSelected
                      ? context.colorScheme.primary
                      : colors.transparentSurface,
                  borderRadius: BorderRadius.circular(radius.pill),
                ),
              ),
              SizedBox(width: spacing.md),
              // Icon
              SvgPicture.asset(
                asset.icon,
                width: icons.xl,
                height: icons.xl,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.circle,
                  size: icons.xl,
                  color: AssetDisplay.colorOf(context, asset),
                ),
              ),
              SizedBox(width: spacing.sm),
              // Name and subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(asset.token, style: type.title),
                    SizedBox(height: spacing.xxs),
                    Text(
                      asset.chain,
                      style: type.rowMeta.copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              SizedBox(width: spacing.md),
              // Balance information
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  NumericText('\$0.0', style: type.rowValue),
                  SizedBox(height: spacing.xxs),
                  AmountText(
                    '0 sats',
                    style: type.rowMeta.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
              SizedBox(width: spacing.screenPadding),
            ],
          ),
        ),
      ),
    );
  }
}
