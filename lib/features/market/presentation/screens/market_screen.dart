import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import 'package:aster/features/market/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';

/// Market screen displaying a grid of action tiles
///
/// Each tile represents a market action
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    final tiles = [
      MarketTile(
        label: 'Buy',
        subtitle: 'Load wallet',
        icon: RemixIcons.shopping_bag_3_line,
        onTap: () {
          // TODO: Navigate to buy screen
        },
      ),
      MarketTile(
        label: 'Sell',
        subtitle: 'Unload wallet',
        icon: RemixIcons.shopping_cart_line,
        onTap: () {
          // TODO: Navigate to sell screen
        },
      ),
      MarketTile(
        label: 'Swap',
        subtitle: 'Exchange assets',
        icon: RemixIcons.token_swap_line,
        onTap: () {
          context.push(RoutePaths.swap);
        },
      ),
      MarketTile(
        label: 'Lend',
        subtitle: 'Earn interest',
        icon: RemixIcons.bank_line,
        onTap: () {
          // TODO: Navigate to lend screen
        },
      ),
      MarketTile(
        label: 'Send',
        subtitle: 'Send bitcoin',
        icon: RemixIcons.arrow_right_up_line,
        onTap: () {
          context.push(RoutePaths.sendAddress);
        },
      ),
      MarketTile(
        label: 'Receive',
        subtitle: 'Receive bitcoin',
        icon: RemixIcons.arrow_right_down_line,
        onTap: () {
          context.push(RoutePaths.receive);
        },
      ),
    ];

    return Scaffold(
      backgroundColor: colors.fill1,
      appBar: const CustomAppBar(title: 'Market'),
      body: ListView.builder(
        padding: EdgeInsets.only(
          left: spacing.spacing20,
          right: spacing.spacing20,
          bottom: spacing.bottomSafeHeight + spacing.spacing44,
        ),
        itemCount: tiles.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(bottom: spacing.spacing12),
            child: tiles[index],
          );
        },
      ),
    );
  }
}
