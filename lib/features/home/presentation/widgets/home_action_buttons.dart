import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';

/// Equal-width entry commands for the three wallet flows.
class HomeActionButtons extends StatelessWidget {
  const HomeActionButtons({this.stacked = false, super.key});

  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final navigation = AsterNavigationScope.of(context);

    void open(String location, String failureTitle) {
      unawaited(
        navigation.openRoute(
          command: () => context.push<void>(location),
          failureTitle: failureTitle,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minimumButtonWidth =
              unwrappedTextWidth(
                context,
                'Receive',
                context.type.compactButtonLabel,
              ) +
              context.icons.sm +
              spacing.xs +
              spacing.md * 2;
          final vertical =
              stacked ||
              constraints.maxWidth < minimumButtonWidth * 3 + spacing.md * 2;
          final buttons = [
            for (final (label, icon, route) in [
              ('Send', RemixIcons.arrow_right_up_line, RoutePaths.send),
              ('Receive', RemixIcons.arrow_right_down_line, RoutePaths.receive),
              ('Swap', RemixIcons.token_swap_line, RoutePaths.swap),
            ])
              CustomButton.compact(
                text: label,
                width: double.infinity,
                suffixIcon: icon,
                variant: ButtonVariant.translucent,
                enabled: !navigation.inFlight,
                hapticIntent: null,
                onTap: () => open(route, '$label could not open'),
              ),
          ];
          if (vertical) {
            return Column(
              children: [
                for (var index = 0; index < buttons.length; index++) ...[
                  if (index > 0) SizedBox(height: spacing.xs),
                  buttons[index],
                ],
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var index = 0; index < buttons.length; index++) ...[
                if (index > 0) SizedBox(width: spacing.md),
                Expanded(child: buttons[index]),
              ],
            ],
          );
        },
      ),
    );
  }
}
