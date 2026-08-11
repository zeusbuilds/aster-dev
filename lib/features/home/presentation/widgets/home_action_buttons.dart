import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';

/// Equal-width entry commands for the three wallet flows.
class HomeActionButtons extends StatelessWidget {
  const HomeActionButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            flex: 1,
            child: CustomButton.compact(
              text: 'Send',
              width: double.infinity,
              suffixIcon: RemixIcons.arrow_right_up_line,
              variant: ButtonVariant.translucent,
              onTap: () async => context.push(RoutePaths.send),
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            flex: 1,
            child: CustomButton.compact(
              text: 'Receive',
              width: double.infinity,
              suffixIcon: RemixIcons.arrow_right_down_line,
              variant: ButtonVariant.translucent,
              onTap: () async => context.push(RoutePaths.receive),
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            flex: 1,
            child: CustomButton.compact(
              text: 'Swap',
              width: double.infinity,
              suffixIcon: RemixIcons.token_swap_line,
              variant: ButtonVariant.translucent,
              onTap: () async => context.push(RoutePaths.swap),
            ),
          ),
        ],
      ),
    );
  }
}
