import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/presentation/view_model/viewmodels.dart';

/// Header widget for the home screen
///
/// Displays the app logo and active wallet name with navigation to wallet selection
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final icons = context.icons;
    final walletState = ref.watch(walletViewModelProvider);
    final activeWallet = switch (walletState) {
      AsyncData(:final value) => value.activeWallet,
      _ => null,
    };

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Semantics(
            image: true,
            label: 'UTEXO',
            child: SvgPicture.asset(
              'assets/brand/aster-logo.svg',
              width: icons.xl,
              colorFilter: ColorFilter.mode(colors.onBrandArt, BlendMode.srcIn),
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'Select wallet, ${activeWallet?.name ?? 'Main Wallet'}',
            excludeSemantics: true,
            child: Material(
              color: colors.transparentSurface,
              child: InkWell(
                onTap: () {
                  unawaited(context.haptics.trigger(HapticIntent.lightImpact));
                  unawaited(
                    context.pushNamed<void>(RouteNames.walletSelection),
                  );
                },
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: context.metrics.minTouchTarget,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        activeWallet?.name ?? 'Main Wallet',
                        style: context.type.brandAction.copyWith(
                          color: colors.onBrandArt,
                        ),
                      ),
                      SizedBox(width: spacing.xs),
                      Icon(
                        MingCuteIcons.mgc_wallet_3_line,
                        size: icons.md,
                        color: colors.onBrandArt,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
