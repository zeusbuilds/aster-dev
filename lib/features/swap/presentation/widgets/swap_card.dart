import 'package:flutter/material.dart';

import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';
import 'asset_selector_sheet.dart';
import 'swap_pair.dart';

/// Card widget displaying swap pair (from/to assets)
///
/// Shows asset selection, amounts, balances, and swap arrow indicator
class SwapCard extends StatefulWidget {
  const SwapCard({super.key});

  @override
  State<SwapCard> createState() => _SwapCardState();
}

class _SwapCardState extends State<SwapCard> {
  AssetModel _fromAsset = AssetModel.bitcoin;
  AssetModel _toAsset = AssetModel.usdt;

  /// Shows asset selector bottom sheet
  ///
  /// [isFrom] - Whether selecting the "from" asset (true) or "to" asset (false)
  Future<void> _showAssetSelector(bool isFrom) async {
    final selected = await AssetSelectorSheet.show(
      context,
      assets: AssetModel.all,
      selectedAssetName: isFrom ? _fromAsset.token : _toAsset.token,
    );

    if (selected != null && mounted) {
      setState(() {
        if (isFrom) {
          _fromAsset = selected;
        } else {
          _toAsset = selected;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final radius = context.radii;
    final icons = context.icons;
    final strokes = context.strokes;

    return Stack(
      alignment: Alignment.center,
      children: [
        Squircle(
          color: context.colorScheme.surface,
          borderColor: colors.surfaceSubtle,
          borderRadius: radius.sheet,
          padding: EdgeInsets.all(spacing.xs),
          child: Column(
            children: [
              SwapPair(
                from: true,
                asset: _fromAsset,
                amount: '100,000',
                balance: '200,000',
                marketPrice: '\$160,000',
                onAssetTap: () => _showAssetSelector(true),
              ),
              SwapPair(
                from: false,
                asset: _toAsset,
                amount: '7500',
                balance: '2500',
                marketPrice: '\$1',
                onAssetTap: () => _showAssetSelector(false),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.all(spacing.sm),
          decoration: BoxDecoration(
            color: colors.surfaceSubtle,
            shape: BoxShape.circle,
            border: Border.all(
              color: context.colorScheme.surface,
              width: strokes.focusRing,
            ),
          ),
          child: Icon(
            RemixIcons.arrow_down_line,
            size: icons.sm,
            color: context.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
