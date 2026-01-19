import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:custom_numeric_pad/custom_numpad_package.dart';
import 'package:flutter/material.dart';

/// Screen for setting the amount to receive
///
/// Displays amount card and numeric keypad for entering the receive amount
class ReceiveSetAmountScreen extends StatelessWidget {
  const ReceiveSetAmountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;
    final textTheme = context.textTheme;

    return Scaffold(
      backgroundColor: colors.fill1,
      appBar: CustomAppBar(
        title: 'Receive',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.spacing20),
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
                        spacing.spacing20 * 2 -
                        80) /
                    3,
                buttonHeight: 60,
                rowSpacing: spacing.spacing8,
                columnSpacing: spacing.spacing8,
                buttonColor: colors.fill2,
                buttonTextStyle:
                    textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.text1,
                    ) ??
                    TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: colors.text1,
                    ),
              ),
              SizedBox(height: spacing.spacing18),
              CustomButton(text: 'Continue', onTap: () {}),
            ],
          ),
        ),
      ),
    );
  }
}
