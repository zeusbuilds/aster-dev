import 'package:flutter/material.dart';

import 'package:custom_numeric_pad/custom_numpad_package.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Screen for setting the amount to receive
///
/// Displays amount card and numeric keypad for entering the receive amount
class ReceiveSetAmountScreen extends StatelessWidget {
  const ReceiveSetAmountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final textTheme = context.textTheme;

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Receive',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
          child: Column(
            children: [
              ReceiveCard(
                amount: '100,000',
                asset: 'BTC',
                marketPrice: '\$160,000',
                balance: '200,000',
              ),
              const Spacer(),
              CustomNumPad(
                key: const ValueKey('send-keyboard'),
                buttonWidth:
                    (MediaQuery.of(context).size.width -
                        spacing.screenPadding * 2 -
                        80) /
                    3,
                buttonHeight: 60,
                rowSpacing: spacing.sm,
                columnSpacing: spacing.sm,
                buttonColor: colors.surfaceSubtle,
                buttonTextStyle:
                    textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.colorScheme.onSurface,
                    ) ??
                    TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: context.colorScheme.onSurface,
                    ),
              ),
              SizedBox(height: spacing.xl),
              CustomButton(text: 'Continue', onTap: () {}),
            ],
          ),
        ),
      ),
    );
  }
}
