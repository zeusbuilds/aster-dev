import 'package:flutter/material.dart';

import 'package:custom_numeric_pad/custom_numpad_package.dart';

import 'package:aster/features/send/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';

/// Screen for sending Bitcoin
///
/// Displays send amount card and numeric keypad for entering the send amount
class SendScreen extends StatelessWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.fill1,
      appBar: CustomAppBar(
        title: 'Send',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.spacing.spacing20),
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
                buttonWidth: (MediaQuery.of(context).size.width - 40 - 80) / 3,
                buttonHeight: 60,
                rowSpacing: 10,
                columnSpacing: 10,
                buttonColor: context.colors.fill2,
                buttonTextStyle: context.textTheme.headlineSmall!
                    .copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.colors.text1,
                    )
                    .toNumeric(context),
              ),
              SizedBox(height: context.spacing.spacing18),
              CustomButton(text: 'Continue', onTap: () {}),
            ],
          ),
        ),
      ),
    );
  }
}
