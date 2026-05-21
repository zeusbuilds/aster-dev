import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Market screen displaying a grid of action tiles
///
/// Each tile represents a market action
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effects = context.effects;
    final spacing = context.spacing;

    final tiles = [
      MarketTile(
        label: 'Buy',
        subtitle: 'Load wallet',
        icon: RemixIcons.shopping_bag_3_line,
        gradientColors: colors.marketBuyGradient,
        shadowColor: colors.bitcoin.withValues(
          alpha: effects.marketShadowOpacity,
        ),
        tipText: 'From 0.1% fee',
        onTap: () {
          // TODO: Navigate to buy screen
        },
      ),
      MarketTile(
        label: 'Sell',
        subtitle: 'Unload wallet',
        icon: RemixIcons.shopping_cart_line,
        gradientColors: colors.marketSellGradient,
        shadowColor: colors.brandArtBright.withValues(
          alpha: effects.marketShadowOpacity,
        ),
        tipText: 'Instant payout',
        onTap: () {
          // TODO: Navigate to sell screen
        },
      ),
      MarketTile(
        label: 'Swap',
        subtitle: 'Exchange assets',
        icon: RemixIcons.token_swap_line,
        gradientColors: colors.marketSwapGradient,
        shadowColor: colors.overlay.withValues(
          alpha: effects.marketShadowOpacity,
        ),
        tipText: 'Best rate',
        onTap: () {
          context.push(RoutePaths.swap);
        },
      ),
      MarketTile(
        label: 'Lend',
        subtitle: 'Earn interest',
        icon: RemixIcons.bank_line,
        gradientColors: colors.marketLendGradient,
        shadowColor: colors.brandArtDeep.withValues(
          alpha: effects.marketShadowOpacity,
        ),
        tipText: '12.4% APY',
        onTap: () {
          // TODO: Navigate to lend screen
        },
      ),
      MarketTile(
        label: 'Send',
        subtitle: 'Send bitcoin',
        icon: RemixIcons.arrow_right_up_line,
        gradientColors: colors.marketSendGradient,
        shadowColor: colors.danger.withValues(
          alpha: effects.marketShadowOpacity,
        ),
        tipText: '~10 min confirmations',
        onTap: () {
          context.push(RoutePaths.sendAddress);
        },
      ),
      MarketTile(
        label: 'Receive',
        subtitle: 'Receive bitcoin',
        icon: RemixIcons.arrow_right_down_line,
        gradientColors: colors.marketReceiveGradient,
        shadowColor: colors.success.withValues(
          alpha: effects.marketShadowOpacity,
        ),
        tipText: 'Free & instant',
        onTap: () {
          context.push(RoutePaths.receive);
        },
      ),
    ];

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(title: 'Market'),
      body: ListView.builder(
        padding: EdgeInsets.only(
          left: spacing.screenPadding,
          right: spacing.screenPadding,
          bottom: spacing.bottomSafe(context) + spacing.navOffset,
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
