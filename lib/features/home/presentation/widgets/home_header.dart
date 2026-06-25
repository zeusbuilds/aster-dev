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
    final activeWallet = walletState.activeWallet;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'Open onboarding',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.pushNamed(RouteNames.onboardingWelcome),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SvgPicture.asset(
                  'assets/brand/aster-logo.svg',
                  width: icons.xl,
                  colorFilter: ColorFilter.mode(
                    colors.onBrandArt,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'Select wallet, ${activeWallet?.name ?? 'Main Wallet'}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.pushNamed(RouteNames.walletSelection),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
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
        ],
      ),
    );
  }
}
