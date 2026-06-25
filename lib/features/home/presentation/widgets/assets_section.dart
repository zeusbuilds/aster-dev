import 'package:flutter/material.dart';

import 'package:ming_cute_icons/ming_cute_icons.dart';
import 'package:unicons/unicons.dart';

import '../../../../shared/shared.dart';
import 'asset_row.dart';

/// Widget displaying the list of assets/balances for the wallet
///
/// Shows loading indicator when balance is null or empty
class AssetsSection extends StatelessWidget {
  const AssetsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final icons = context.icons;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
      child: Column(
        children: [
          SizedBox(height: spacing.screenPadding),
          Row(
            children: [
              Text('Assets', style: context.type.sectionTitle),
              const Spacer(),
              Icon(
                MingCuteIcons.mgc_eye_2_line,
                size: icons.sm,
                color: colors.textSecondary,
              ),
            ],
          ),
          SizedBox(height: spacing.lg),
          ...List.generate(2, (index) {
            return Column(
              children: [
                AssetRow(
                  name: index == 0 ? 'LBTC' : 'USDt',
                  denomination: 'sats',
                  fiatBalance: '\$0.00',
                  assetBalance: '0 sats',
                  icon: UniconsLine.bitcoin,
                  iconColor: index == 0 ? colors.bitcoin : colors.liquid,
                  isLoading: true,
                ),
                if (index < 1) SizedBox(height: spacing.lg),
              ],
            );
          }),
        ],
      ),
    );
  }
}
