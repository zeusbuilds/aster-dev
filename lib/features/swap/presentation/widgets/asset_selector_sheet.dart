import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import 'package:aster/shared/shared.dart';

/// Bottom sheet for selecting an asset
class AssetSelectorSheet extends StatelessWidget {
  final List<AssetModel> assets;
  final String? selectedAssetName;
  final Function(AssetModel) onAssetSelected;

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
    return showModalBottomSheet<AssetModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AssetSelectorSheet(
        assets: assets,
        selectedAssetName: selectedAssetName,
        onAssetSelected: (asset) {
          Future.delayed(const Duration(milliseconds: 250), () {
            Navigator.of(context).pop(asset);
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radius = context.radius;
    final textTheme = context.textTheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colors.fill1,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(radius.radius24),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: spacing.spacing12),
          // Handle bar
          Container(
            width: 56,
            height: 4,
            decoration: BoxDecoration(
              color: colors.fill3,
              borderRadius: BorderRadius.circular(radius.radius50),
            ),
          ),
          SizedBox(height: spacing.spacing16),
          // Title
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.spacing20),
            child: Text(
              'Select token',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.text1,
              ),
            ),
          ),
          SizedBox(height: spacing.spacing16),
          // Asset list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: assets.length,
              padding: EdgeInsets.only(bottom: spacing.bottomSafeHeightRaw),
              itemBuilder: (context, index) {
                final asset = assets[index];
                final isSelected =
                    asset.token == selectedAssetName ||
                    asset.unit == selectedAssetName;

                return Padding(
                  padding: EdgeInsets.only(bottom: spacing.spacing4),
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
    final colors = context.colors;
    final spacing = context.spacing;
    final radius = context.radius;
    final textTheme = context.textTheme;

    return GestureDetector(
      onTapDown: (_) async {
        final canVibrate = await Haptics.canVibrate();
        if (canVibrate) {
          await Haptics.vibrate(HapticsType.light);
        }
      },
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(vertical: spacing.spacing4),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.brand1.withValues(alpha: 0.5)
              : colors.fill1,
        ),
        child: Row(
          children: [
            SizedBox(width: spacing.spacing8),
            // Selection indicator bar
            Container(
              width: spacing.spacing4,
              height: spacing.spacing64,
              decoration: BoxDecoration(
                color: isSelected ? colors.brand6 : Colors.transparent,
                borderRadius: BorderRadius.circular(radius.radius50),
              ),
            ),
            SizedBox(width: spacing.spacing12),
            // Icon
            SvgPicture.asset(
              asset.icon,
              width: spacing.spacing40,
              height: spacing.spacing40,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.circle,
                size: spacing.spacing40,
                color: Color(asset.color),
              ),
            ),
            SizedBox(width: spacing.spacing8),
            // Name and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    asset.token,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.text1,
                    ),
                  ),
                  SizedBox(height: spacing.spacing2),
                  Text(
                    asset.chain,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.text3,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.spacing12),
            // Balance information
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\$0.0',
                  style: textTheme.titleMedium
                      ?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.text1,
                      )
                      .toNumeric(context),
                ),
                SizedBox(height: spacing.spacing2),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '0',
                        style: textTheme.titleSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colors.text3,
                            )
                            .toNumeric(context),
                      ),
                      TextSpan(
                        text: ' sats',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(width: spacing.spacing20),
          ],
        ),
      ),
    );
  }
}
