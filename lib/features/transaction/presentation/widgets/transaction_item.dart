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
  final Color iconColor;

  const TransactionItem({
    super.key,
    required this.type,
    required this.amount,
    required this.time,
    required this.icon,
    this.iconColor = Colors.blueGrey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(spacing.spacing8),
          decoration: BoxDecoration(
            color: colors.fill2,
            shape: BoxShape.circle,
            border: Border.all(color: colors.border2, width: 1),
          ),
          child: Icon(icon, size: spacing.spacing20, color: iconColor),
        ),
        SizedBox(width: spacing.spacing16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      type,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.text1,
                      ),
                    ),
                  ),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: amount,
                          style: textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.text1,
                              )
                              .toNumeric(context),
                        ),
                        TextSpan(
                          text: ' BTC',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.text1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.spacing2),
              RichText(
                text: TextSpan(children: _buildTimeSpans(context, time)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds text spans for time display with proper numeric formatting
  ///
  /// Separates time digits from AM/PM for styling
  List<TextSpan> _buildTimeSpans(BuildContext context, String time) {
    final colors = context.colors;
    final textTheme = context.textTheme;

    // Split time into numeric part (e.g., "12:30") and period (e.g., "PM")
    final parts = time.split(' ');
    final baseStyle = textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
      color: colors.text3,
    );

    if (parts.length == 2) {
      // Has AM/PM
      return [
        TextSpan(
          text: parts[0], // Time digits
          style: baseStyle?.toNumeric(context),
        ),
        TextSpan(
          text: ' ${parts[1]}', // AM/PM
          style: baseStyle,
        ),
      ];
    } else {
      // No AM/PM, just numeric
      return [TextSpan(text: time, style: baseStyle?.toNumeric(context))];
    }
  }
}
