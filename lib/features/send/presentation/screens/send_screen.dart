import 'package:custom_numeric_pad/custom_numpad_package.dart';
import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Screen for sending Bitcoin
///
/// Displays send amount card and numeric keypad for entering the send amount
class SendScreen extends StatelessWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final metrics = context.metrics;

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Send',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
          child: Column(
            children: [
              SendCard(
                amount: '100,000',
                asset: AssetModel.bitcoin,
                marketPrice: '\$160,000',
                balance: '200,000',
              ),
              const Spacer(),
              CustomNumPad(
                key: const ValueKey('send-keyboard'),
                buttonWidth:
                    (MediaQuery.of(context).size.width -
                        spacing.screenPadding * 2 -
                        metrics.keypadHorizontalReserve) /
                    3,
                buttonHeight: metrics.keypadButtonHeight,
                rowSpacing: metrics.keypadGap,
                columnSpacing: metrics.keypadGap,
                buttonColor: context.appColors.surfaceSubtle,
                buttonTextStyle: context.type.keypadNumber.toNumeric(context),
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
