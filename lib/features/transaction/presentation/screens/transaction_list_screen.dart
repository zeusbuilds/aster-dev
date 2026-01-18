import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../widgets/widgets.dart';

/// Screen displaying list of Bitcoin transactions
/// Shows balance summary and grouped transaction history
class TransactionListScreen extends StatelessWidget {
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return Scaffold(
      backgroundColor: colors.fill1,
      appBar: CustomAppBar(
        title: 'Bitcoin Transactions',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing.spacing20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Squircle(
              padding: EdgeInsets.symmetric(
                vertical: spacing.spacing16,
                horizontal: spacing.spacing16,
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Balance',
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.text3,
                        ),
                      ),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '0.00001',
                              style: textTheme.bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colors.text1,
                                  )
                                  .toNumeric(context),
                            ),
                            TextSpan(
                              text: ' BTC',
                              style: textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.text1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '\$100,000',
                        style: textTheme.bodyMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: colors.text3,
                            )
                            .toNumeric(context),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Icon(
                    RemixIcons.bit_coin_fill,
                    size: spacing.spacing44,
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.spacing16),
            Text(
              'Today',
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.text3,
              ),
            ),
            SizedBox(height: spacing.spacing16),
            const TransactionItem(
              type: 'Sent',
              amount: '-100',
              time: '12:30 PM',
              icon: RemixIcons.arrow_right_up_line,
            ),
            SizedBox(height: spacing.spacing16),
            const TransactionItem(
              type: 'Received',
              amount: '+100',
              time: '12:30 PM',
              icon: RemixIcons.arrow_right_down_line,
            ),
            SizedBox(height: spacing.spacing16),
            const TransactionItem(
              type: 'Swap',
              amount: '100',
              time: '12:30 PM',
              icon: RemixIcons.exchange_line,
            ),
            SizedBox(height: spacing.spacing16),
            Text(
              'Yesterday',
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.text3,
              ),
            ),
            SizedBox(height: spacing.spacing16),
            const TransactionItem(
              type: 'Sent',
              amount: '-100',
              time: '12:30 PM',
              icon: RemixIcons.arrow_right_up_line,
            ),
            SizedBox(height: spacing.spacing16),
            const TransactionItem(
              type: 'Received',
              amount: '+100',
              time: '12:30 PM',
              icon: RemixIcons.arrow_right_down_line,
            ),
            SizedBox(height: spacing.spacing16),
            const TransactionItem(
              type: 'Swap',
              amount: '100',
              time: '12:30 PM',
              icon: RemixIcons.exchange_line,
            ),
          ],
        ),
      ),
    );
  }
}
