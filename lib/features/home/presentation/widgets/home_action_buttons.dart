import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';

/// Row of action buttons for Send, Receive, and Swap operations
///
/// Provides quick access to main wallet operations from the home screen
class HomeActionButtons extends StatelessWidget {
  const HomeActionButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.spacing20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            flex: 1,
            child: CustomButton.compact(
              text: 'Send',
              suffixIcon: RemixIcons.arrow_right_up_line,
              variant: ButtonVariant.translucent,
              onTap: () {
                context.push(RoutePaths.sendAddress);
              },
            ),
          ),
          SizedBox(width: spacing.spacing12),
          Expanded(
            flex: 1,
            child: CustomButton.compact(
              text: 'Receive',
              suffixIcon: RemixIcons.arrow_right_down_line,
              variant: ButtonVariant.translucent,
              onTap: () {
                context.push(RoutePaths.receive);
              },
            ),
          ),
          SizedBox(width: spacing.spacing12),
          Expanded(
            flex: 1,
            child: CustomButton.compact(
              text: 'Swap',
              suffixIcon: RemixIcons.token_swap_line,
              variant: ButtonVariant.translucent,
              onTap: () {
                context.push(RoutePaths.swap);
              },
            ),
          ),
        ],
      ),
    );
  }
}
