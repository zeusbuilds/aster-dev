import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Widget displaying a single transaction item
///
/// Shows transaction type, amount, time, and icon with proper formatting
class TransactionItem extends StatelessWidget {
  /// Type of transaction (e.g., "Sent", "Received", "Swap")
  final String type;

  /// Transaction amount (with +/- prefix)
  final String amount;

  /// Time of transaction
  final String time;

  /// Icon to display for transaction type
  final IconData icon;

  /// Color of the transaction icon
  final Color? iconColor;

  const TransactionItem({
    super.key,
    required this.type,
    required this.amount,
    required this.time,
    required this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final icons = context.icons;
    final strokes = context.strokes;
    final textRoles = context.type;

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(spacing.sm),
          decoration: BoxDecoration(
            color: colors.surfaceSubtle,
            shape: BoxShape.circle,
            border: Border.all(
              color: colors.borderSubtle,
              width: strokes.divider,
            ),
          ),
          child: Icon(
            icon,
            size: icons.sm,
            color: iconColor ?? colors.textSecondary,
          ),
        ),
        SizedBox(width: spacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(type, style: context.type.rowTitle)),
                  AmountText('$amount BTC', style: textRoles.amountInline),
                ],
              ),
              SizedBox(height: spacing.xxs),
              AmountText(
                time,
                style: textRoles.rowMeta.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
