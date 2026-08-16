import 'dart:async';

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
    final navigation = AsterNavigationScope.of(context);

    void open(String location, String failureTitle) {
      unawaited(
        navigation.run(
          command: () => context.push(location),
          failureTitle: failureTitle,
        ),
      );
    }

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
              enabled: !navigation.inFlight,
              hapticIntent: null,
              onTap: () => open(RoutePaths.send, 'Send could not open'),
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
              enabled: !navigation.inFlight,
              hapticIntent: null,
              onTap: () => open(RoutePaths.receive, 'Receive could not open'),
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
              enabled: !navigation.inFlight,
              hapticIntent: null,
              onTap: () => open(RoutePaths.swap, 'Swap could not open'),
            ),
          ),
        ],
      ),
    );
  }
}
