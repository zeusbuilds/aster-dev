import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Presents supported wallet routes and truthful unavailable market actions.
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final colors = context.appColors;
          final effects = context.effects;
          final spacing = context.spacing;
          final metrics = context.metrics;
          final gradients = context.gradients;
          final navigation = AsterNavigationScope.of(context);

          VoidCallback? open(String location, String failureTitle) {
            if (navigation.inFlight) return null;
            return () => unawaited(
              navigation.run(
                command: () => context.push(location),
                failureTitle: failureTitle,
              ),
            );
          }

          final tiles = [
            MarketTile(
              label: 'Buy',
              subtitle: 'Not supported',
              icon: RemixIcons.shopping_bag_3_line,
              gradient: gradients.marketBuy,
              shadowColor: colors.bitcoin.withValues(
                alpha: effects.marketShadowOpacity,
              ),
              tipText: 'Unavailable',
            ),
            MarketTile(
              label: 'Sell',
              subtitle: 'Not supported',
              icon: RemixIcons.shopping_cart_line,
              gradient: gradients.marketSell,
              shadowColor: colors.brandArtBright.withValues(
                alpha: effects.marketShadowOpacity,
              ),
              tipText: 'Unavailable',
            ),
            MarketTile(
              label: 'Swap',
              subtitle: 'Select asset routes',
              icon: RemixIcons.token_swap_line,
              gradient: gradients.marketSwap,
              shadowColor: colors.overlay.withValues(
                alpha: effects.marketShadowOpacity,
              ),
              tipText: 'Execution unavailable',
              hapticIntent: null,
              onTap: open(RoutePaths.swap, 'Swap could not open'),
            ),
            MarketTile(
              label: 'Lend',
              subtitle: 'Not supported',
              icon: RemixIcons.bank_line,
              gradient: gradients.marketLend,
              shadowColor: colors.brandArtDeep.withValues(
                alpha: effects.marketShadowOpacity,
              ),
              tipText: 'Unavailable',
            ),
            MarketTile(
              label: 'Send',
              subtitle: 'Bitcoin or USDT',
              icon: RemixIcons.arrow_right_up_line,
              gradient: gradients.marketSend,
              contentTone: MarketContentTone.dark,
              shadowColor: colors.danger.withValues(
                alpha: effects.marketShadowOpacity,
              ),
              tipText: 'On-chain or Lightning',
              hapticIntent: null,
              onTap: open(RoutePaths.send, 'Send could not open'),
            ),
            MarketTile(
              label: 'Receive',
              subtitle: 'Bitcoin or USDT',
              icon: RemixIcons.arrow_right_down_line,
              gradient: gradients.marketReceive,
              contentTone: MarketContentTone.dark,
              shadowColor: colors.success.withValues(
                alpha: effects.marketShadowOpacity,
              ),
              tipText: 'On-chain or Lightning',
              hapticIntent: null,
              onTap: open(RoutePaths.receive, 'Receive could not open'),
            ),
          ];

          return Scaffold(
            backgroundColor: context.colorScheme.surface,
            appBar: const CustomAppBar(title: 'Market'),
            body: ListView(
              padding: EdgeInsets.only(
                left: spacing.screenPadding,
                right: spacing.screenPadding,
                bottom:
                    context.windowInsets.bottomSystem +
                    spacing.lg +
                    metrics.floatingNavClearance,
              ),
              children: [
                for (final tile in tiles)
                  Padding(
                    padding: EdgeInsets.only(bottom: spacing.md),
                    child: tile,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
