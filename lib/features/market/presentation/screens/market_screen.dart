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
    final colors = context.appColors;
    final effects = context.effects;
    final spacing = context.spacing;
    final metrics = context.metrics;
    final gradients = context.gradients;

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
        onTap: () async => context.push(RoutePaths.swap),
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
        shadowColor: colors.danger.withValues(
          alpha: effects.marketShadowOpacity,
        ),
        tipText: 'On-chain or Lightning',
        onTap: () async => context.push(RoutePaths.send),
      ),
      MarketTile(
        label: 'Receive',
        subtitle: 'Bitcoin or USDT',
        icon: RemixIcons.arrow_right_down_line,
        gradient: gradients.marketReceive,
        shadowColor: colors.success.withValues(
          alpha: effects.marketShadowOpacity,
        ),
        tipText: 'On-chain or Lightning',
        onTap: () async => context.push(RoutePaths.receive),
      ),
    ];

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(title: 'Market'),
      body: ListView.builder(
        padding: EdgeInsets.only(
          left: spacing.screenPadding,
          right: spacing.screenPadding,
          bottom:
              context.windowInsets.bottomSystem +
              spacing.lg +
              metrics.floatingNavClearance,
        ),
        itemCount: tiles.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(bottom: spacing.md),
            child: tiles[index],
          );
        },
      ),
    );
  }
}
