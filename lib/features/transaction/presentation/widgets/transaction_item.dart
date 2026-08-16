import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../formatting/formatting.dart';

/// One typed Activity record with stable semantics and exact amount display.
class TransactionItem extends StatelessWidget {
  const TransactionItem({
    super.key,
    required this.activity,
    required this.bitcoinUnit,
    required this.valuesVisible,
    this.onTap,
    required this.formatter,
  });

  final WalletActivity activity;
  final BitcoinUnit bitcoinUnit;
  final bool valuesVisible;
  final VoidCallback? onTap;
  final ActivityDisplayFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final title = formatter.activityTitle(activity);
    final amount = formatter.amountText(activity, bitcoinUnit);
    final amountLabel = !valuesVisible
        ? 'Amount hidden'
        : amount ?? 'Amount unavailable';
    final status = formatter.statusLabel(activity.status);
    final time = formatter.timeLabel(activity.occurredAt);
    final lightning = activity.rail == PaymentRail.lightning;
    final icon = switch (activity.direction) {
      WalletActivityDirection.sent => RemixIcons.arrow_right_up_line,
      WalletActivityDirection.received => RemixIcons.arrow_right_down_line,
      WalletActivityDirection.internal => RemixIcons.exchange_2_line,
      WalletActivityDirection.unknown => RemixIcons.flashlight_line,
    };
    final iconColor = switch (activity.direction) {
      WalletActivityDirection.sent => context.appColors.danger,
      WalletActivityDirection.received => context.appColors.success,
      WalletActivityDirection.internal => context.colorScheme.primary,
      WalletActivityDirection.unknown => context.appColors.warning,
    };

    return Semantics(
      button: true,
      enabled: onTap != null,
      label:
          '$title${lightning ? ', Lightning' : ', on-chain'}, '
          '$amountLabel, $status, $time',
      onTap: onTap,
      excludeSemantics: true,
      child: Squircle(
        padding: EdgeInsets.zero,
        color: context.appColors.surfaceRaised,
        child: Material(
          color: context.appColors.transparentSurface,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: context.metrics.minTouchTarget,
              ),
              child: Padding(
                padding: EdgeInsets.all(context.spacing.lg),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(context.spacing.sm),
                      decoration: BoxDecoration(
                        color: context.appColors.surfaceSubtle,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.appColors.borderSubtle,
                          width: context.strokes.divider,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: context.icons.sm,
                        color: iconColor,
                      ),
                    ),
                    SizedBox(width: context.spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  style: context.type.rowTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (lightning) ...[
                                SizedBox(width: context.spacing.xs),
                                Icon(
                                  RemixIcons.flashlight_fill,
                                  size: context.icons.xxs,
                                  color: context.appColors.warning,
                                  semanticLabel: 'Lightning',
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: context.spacing.xxs),
                          NumericText(
                            '$time, $status',
                            style: context.type.rowMeta,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: context.spacing.sm),
                    Flexible(
                      child: AmountText(
                        valuesVisible ? amount ?? '--' : '••••',
                        style: context.type.amountInline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ),
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
