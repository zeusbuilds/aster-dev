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
    final colors = context.colors;
    final spacing = context.spacing;

    final tiles = [
      MarketTile(
        label: 'Buy',
        subtitle: 'Load wallet',
        icon: RemixIcons.shopping_bag_3_line,
        gradientColors: [const Color(0xFFE89B6B), const Color(0xFFD47A4A)],
        shadowColor: const Color(0x26D47A4A),
        tipText: 'From 0.1% fee',
        onTap: () {
          // TODO: Navigate to buy screen
        },
      ),
      MarketTile(
        label: 'Sell',
        subtitle: 'Unload wallet',
        icon: RemixIcons.shopping_cart_line,
        gradientColors: [const Color(0xFF6BA8E8), const Color(0xFF4A88C8)],
        shadowColor: const Color(0x264A88C8),
        tipText: 'Instant payout',
        onTap: () {
          // TODO: Navigate to sell screen
        },
      ),
      MarketTile(
        label: 'Swap',
        subtitle: 'Exchange assets',
        icon: RemixIcons.token_swap_line,
        gradientColors: [
          Color.fromARGB(255, 105, 105, 105),
          Color.fromARGB(255, 105, 105, 105),
        ],
        tipText: 'Best rate',
        onTap: () {
          context.push(RoutePaths.swap);
        },
      ),
      MarketTile(
        label: 'Lend',
        subtitle: 'Earn interest',
        icon: RemixIcons.bank_line,
        gradientColors: [const Color(0xFF7B8FA8), const Color(0xFF5A6B82)],
        shadowColor: const Color(0x265A6B82),
        tipText: '12.4% APY',
        onTap: () {
          // TODO: Navigate to lend screen
        },
      ),
      MarketTile(
        label: 'Send',
        subtitle: 'Send bitcoin',
        icon: RemixIcons.arrow_right_up_line,
        gradientColors: [const Color(0xFF9B7BB8), const Color(0xFF7A5A96)],
        shadowColor: const Color(0x267A5A96),
        tipText: '~10 min confirmations',
        onTap: () {
          context.push(RoutePaths.sendAddress);
        },
      ),
      MarketTile(
        label: 'Receive',
        subtitle: 'Receive bitcoin',
        icon: RemixIcons.arrow_right_down_line,
        gradientColors: [const Color(0xFF5BB89A), const Color(0xFF3D9678)],
        shadowColor: const Color(0x263D9678),
        tipText: 'Free & instant',
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
