import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Presents Send, Receive, and Swap using the authored Market artwork.
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key, this.isDuoCover = false});

  final bool isDuoCover;

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
              navigation.openRoute(
                command: () => context.push<void>(location),
                failureTitle: failureTitle,
              ),
            );
          }

          final tiles = [
            MarketTile(
              label: 'Send',
              subtitle: 'Bitcoin or USDT',
              icon: RemixIcons.arrow_right_up_line,
              artworkAsset: 'assets/market/send.png',
              gradient: gradients.marketBuy,
              contentTone: MarketContentTone.light,
              shadowColor: colors.bitcoin.withValues(
                alpha: effects.marketShadowOpacity,
              ),
              tipText: 'On-chain',
              hapticIntent: null,
              onTap: open(RoutePaths.send, 'Send could not open'),
            ),
            MarketTile(
              label: 'Receive',
              subtitle: 'Bitcoin or USDT',
              icon: RemixIcons.arrow_right_down_line,
              artworkAsset: 'assets/market/receive.png',
              gradient: gradients.marketSell,
              contentTone: MarketContentTone.light,
              shadowColor: colors.brandArtBright.withValues(
                alpha: effects.marketShadowOpacity,
              ),
              tipText: 'On-chain',
              hapticIntent: null,
              onTap: open(RoutePaths.receive, 'Receive could not open'),
            ),
            MarketTile(
              label: 'Swap',
              subtitle: 'Select asset routes',
              icon: RemixIcons.token_swap_line,
              artworkAsset: 'assets/market/swap.png',
              gradient: gradients.marketSwap,
              shadowColor: colors.overlay.withValues(
                alpha: effects.marketShadowOpacity,
              ),
              tipText: 'Coming soon',
              hapticIntent: null,
              onTap: open(RoutePaths.swap, 'Swap could not open'),
            ),
          ];

          return Scaffold(
            backgroundColor: context.colorScheme.surface,
            appBar: const CustomAppBar(title: 'Market'),
            body: AsterHorizontalSafeArea(
              child: ListView(
                padding: EdgeInsets.only(
                  left: spacing.screenPadding,
                  right: spacing.screenPadding,
                  bottom:
                      context.windowInsets.bottomSystem +
                      spacing.lg +
                      (CoverTabRail.boundsOf(context) == null
                          ? metrics.floatingNavClearance
                          : 0),
                ),
                children: [
                  for (var i = 0; i < tiles.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: !isDuoCover || i < tiles.length - 1
                            ? spacing.md
                            : 0,
                      ),
                      child: tiles[i],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
