import 'package:flutter/material.dart';

import 'package:gdk_flutter/src/models/gdk_wallet_models.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';
import 'package:unicons/unicons.dart';

import '../../../../shared/shared.dart';
import 'widgets.dart';

/// Widget displaying the list of assets/balances for the wallet
///
/// Shows loading indicator when balance is null or empty
class AssetsSection extends StatelessWidget {
  /// The GDK balance object containing asset amounts
  final GdkBalance? balance;

  const AssetsSection({super.key, required this.balance});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.spacing20),
      child: Column(
        children: [
          SizedBox(height: spacing.spacing20),
          Row(
            children: [
              Text(
                'Assets',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.text1,
                ),
              ),
              const Spacer(),
              Icon(
                MingCuteIcons.mgc_eye_2_line,
                size: spacing.spacing18,
                color: colors.text2,
              ),
            ],
          ),
          SizedBox(height: spacing.spacing16),
          if (balance == null || balance!.amounts.isEmpty)
            ...List.generate(2, (index) {
              return Column(
                children: [
                  AssetRow(
                    name: index == 0 ? 'LBTC' : 'USDt',
                    denomination: 'sats',
                    fiatBalance: '\$0.00',
                    assetBalance: '0 sats',
                    icon: UniconsLine.bitcoin,
                    iconColor: index == 0 ? Colors.orange : Colors.teal,
                    isLoading: true,
                  ),
                  if (index < 1) SizedBox(height: spacing.spacing16),
                ],
              );
            })
          else
            ...balance!.amounts.entries.map((entry) {
              final assetKey = entry.key.toString();
              final rawAmount = entry.value;
              final amount = int.tryParse(rawAmount.toString()) ?? 0;

              return Column(
                children: [
                  AssetRow(
                    name:
                        assetKey ==
                            '6f0279e9ed041c3d710a9f57d0c02928416460c4b722ae3457a11eec381c526d'
                        ? 'LBTC'
                        : assetKey,
                    denomination: 'sats',
                    fiatBalance: '\$110.00', // fiat not wired yet
                    assetBalance: '$amount sats',
                    icon: UniconsLine.bitcoin,
                    iconColor: Colors.orange,
                  ),
                  SizedBox(height: spacing.spacing16),
                  AssetRow(
                    name:
                        assetKey ==
                            '6f0279e9ed041c3d710a9f57d0c02928416460c4b722ae3457a11eec381c526d'
                        ? 'USDt'
                        : assetKey,
                    denomination: 'sats',
                    fiatBalance: '\$110.00', // fiat not wired yet
                    assetBalance: '$amount sats',
                    icon: UniconsLine.bitcoin,
                    iconColor: Colors.teal,
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}
