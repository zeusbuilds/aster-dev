import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';
import '../formatting/formatting.dart';
import '../models/payment_submission_display.dart';

/// A send awaiting native history uses the same compact layout as Activity.
class PaymentSubmissionItem extends StatelessWidget {
  const PaymentSubmissionItem({
    super.key,
    required this.display,
    required this.bitcoinUnit,
    required this.valuesVisible,
    required this.formatter,
    this.onTap,
  });

  final PaymentSubmissionDisplay display;
  final BitcoinUnit bitcoinUnit;
  final bool valuesVisible;
  final ActivityDisplayFormatter formatter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final amount = valuesVisible ? display.amount(bitcoinUnit) : '••••';
    final submittedAt = display.submission.paymentSubmittedAt;
    final time = submittedAt == null ? null : formatter.timeLabel(submittedAt);
    final status = time == null ? display.status : '$time, ${display.status}';
    return Semantics(
      button: true,
      enabled: onTap != null,
      label:
          'Send, ${valuesVisible ? amount : 'Amount hidden'}, '
          '$status',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: context.appColors.transparentSurface,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
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
                    RemixIcons.arrow_right_up_line,
                    size: context.icons.sm,
                    color: context.appColors.textSecondary,
                  ),
                ),
                SizedBox(width: context.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Send', style: context.type.rowTitle),
                      SizedBox(height: context.spacing.xxs),
                      NumericText(status, style: context.type.rowMeta),
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.sm),
                Expanded(
                  child: AmountText(
                    amount,
                    style: context.type.amountInline,
                    maxLines: 2,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
