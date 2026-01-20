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
        icon: RemixIcons.shopping_bag_3_line,
        onTap: () {
          // TODO: Navigate to buy screen
        },
      ),
      MarketTile(
        label: 'Sell',
        icon: RemixIcons.shopping_cart_line,
        onTap: () {
          // TODO: Navigate to sell screen
        },
      ),
      MarketTile(
        label: 'Swap',
        icon: RemixIcons.token_swap_line,
        onTap: () {
          context.push(RoutePaths.swap);
        },
      ),
      MarketTile(
        label: 'Lend',
        icon: RemixIcons.bank_line,
        onTap: () {
          // TODO: Navigate to lend screen
        },
      ),
      MarketTile(
        label: 'Send',
        icon: RemixIcons.arrow_right_up_line,
        onTap: () {
          context.push(RoutePaths.sendAddress);
        },
      ),
      MarketTile(
        label: 'Receive',
        icon: RemixIcons.arrow_right_down_line,
        onTap: () {
          context.push(RoutePaths.receive);
        },
      ),
    ];

    return Scaffold(
      backgroundColor: colors.fill1,
      appBar: const CustomAppBar(title: 'Market'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = spacing.spacing20 * 2;
          final crossAxisSpacing = 16.0;
          final availableWidth =
              constraints.maxWidth - padding - crossAxisSpacing;
          final tileWidth = availableWidth / 2;
          // Calculate aspect ratio accounting for: square squircle + spacing + text height
          // Approximate text height is ~20px, spacing is 8px
          final textHeight = 20.0;
          final spacingHeight = spacing.spacing8;
          final totalHeight = tileWidth + spacingHeight + textHeight;
          final childAspectRatio = tileWidth / totalHeight;

          return GridView.builder(
            padding: EdgeInsets.only(
              left: spacing.spacing20,
              right: spacing.spacing20,
              bottom: spacing.bottomSafeHeight + spacing.spacing44,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: crossAxisSpacing,
              mainAxisSpacing: 24,
              childAspectRatio: childAspectRatio,
            ),
            itemCount: tiles.length,
            itemBuilder: (context, index) {
              return tiles[index];
            },
          );
        },
      ),
    );
  }
}
