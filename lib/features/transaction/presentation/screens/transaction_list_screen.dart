import 'package:flutter/material.dart';

import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Screen displaying list of Bitcoin transactions
///
/// Shows balance summary and grouped transaction history
class TransactionListScreen extends StatelessWidget {
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Bitcoin Transactions',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Squircle(
              padding: EdgeInsets.symmetric(
                vertical: spacing.lg,
                horizontal: spacing.lg,
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
                          color: colors.textTertiary,
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
                                    color: context.colorScheme.onSurface,
                                  )
                                  .toNumeric(context),
                            ),
                            TextSpan(
                              text: ' BTC',
                              style: textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: context.colorScheme.onSurface,
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
                              color: colors.textTertiary,
                            )
                            .toNumeric(context),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Icon(
                    RemixIcons.bit_coin_fill,
                    size: spacing.navOffset,
                    color: colors.bitcoin,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.lg),
            Text(
              'Today',
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.textTertiary,
              ),
            ),
            SizedBox(height: spacing.lg),
            const TransactionItem(
              type: 'Sent',
              amount: '-100',
              time: '12:30 PM',
              icon: RemixIcons.arrow_right_up_line,
            ),
            SizedBox(height: spacing.lg),
            const TransactionItem(
              type: 'Received',
              amount: '+100',
              time: '12:30 PM',
              icon: RemixIcons.arrow_right_down_line,
            ),
            SizedBox(height: spacing.lg),
            const TransactionItem(
              type: 'Swap',
              amount: '100',
              time: '12:30 PM',
              icon: RemixIcons.exchange_line,
            ),
            SizedBox(height: spacing.lg),
            Text(
              'Yesterday',
              style: textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.textTertiary,
              ),
            ),
            SizedBox(height: spacing.lg),
            const TransactionItem(
              type: 'Sent',
              amount: '-100',
              time: '12:30 PM',
              icon: RemixIcons.arrow_right_up_line,
            ),
            SizedBox(height: spacing.lg),
            const TransactionItem(
              type: 'Received',
              amount: '+100',
              time: '12:30 PM',
              icon: RemixIcons.arrow_right_down_line,
            ),
            SizedBox(height: spacing.lg),
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
