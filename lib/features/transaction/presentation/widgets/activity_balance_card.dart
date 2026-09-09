import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';
import '../formatting/formatting.dart';

/// Real total and available balance for the selected Activity asset.
class ActivityBalanceCard extends StatelessWidget {
  const ActivityBalanceCard({
    super.key,
    required this.balance,
    required this.bitcoinUnit,
    required this.valuesVisible,
    required this.formatter,
  });

  final WalletBalance balance;
  final BitcoinUnit bitcoinUnit;
  final bool valuesVisible;
  final ActivityDisplayFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final total = formatter.totalBalanceText(balance, bitcoinUnit);
    final available = formatter.availableBalanceText(balance, bitcoinUnit);
    final title = formatter.assetTitle(balance.asset.kind);
    return Semantics(
      label: valuesVisible
          ? '$title total $total, available $available'
          : '$title balance hidden',
      excludeSemantics: true,
      child: Squircle(
        color: context.appColors.surfaceRaised,
        padding: EdgeInsets.all(context.spacing.screenPadding),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total balance', style: context.type.rowMeta),
                  SizedBox(height: context.spacing.xxs),
                  AmountText(
                    valuesVisible ? total : '••••',
                    style: context.type.amountInline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: context.spacing.xs),
                  AmountText(
                    valuesVisible ? 'Available $available' : 'Balance hidden',
                    style: context.type.rowMeta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: context.spacing.lg),
            WalletAssetIcon(kind: balance.asset.kind, size: context.icons.xl),
          ],
        ),
      ),
    );
  }
}
