import 'package:flutter/material.dart';

import 'package:remixicon/remixicon.dart';

import 'package:aster/features/swap/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';

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
    final colors = context.colors;

    return Stack(
      alignment: Alignment.center,
      children: [
        Squircle(
          color: colors.fill1,
          borderColor: colors.fill2,
          borderRadius: 28,
          padding: EdgeInsets.all(spacing.spacing4),
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
          padding: EdgeInsets.all(spacing.spacing8),
          decoration: BoxDecoration(
            color: colors.fill2,
            shape: BoxShape.circle,
            border: Border.all(color: colors.fill1, width: 3),
          ),
          child: Icon(
            RemixIcons.arrow_down_line,
            size: spacing.spacing22,
            color: colors.text1,
          ),
        ),
      ],
    );
  }
}
