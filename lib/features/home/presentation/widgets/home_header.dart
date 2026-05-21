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
    final textTheme = context.textTheme;
    final walletState = ref.watch(walletViewModelProvider);
    final activeWallet = walletState.activeWallet;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.pushNamed(RouteNames.onboardingWelcome),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SvgPicture.asset(
                'assets/brand/aster-logo.svg',
                width: spacing.navOffset,
                colorFilter: ColorFilter.mode(
                  colors.onBrandArt,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.pushNamed(RouteNames.walletSelection),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  activeWallet?.name ?? 'Main Wallet',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onBrandArt,
                  ),
                ),
                SizedBox(width: spacing.xs),
                Icon(
                  MingCuteIcons.mgc_wallet_3_line,
                  size: spacing.xxl,
                  color: colors.onBrandArt,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
