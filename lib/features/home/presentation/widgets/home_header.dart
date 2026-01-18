import 'package:aster/features/wallet/presentation/viewmodels/viewmodels.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

/// Header widget for the home screen
/// Displays the app logo and active wallet name with navigation to wallet selection
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;
    final walletState = ref.watch(walletViewModelProvider);
    final activeWallet = walletState.activeWallet;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.spacing20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SvgPicture.asset(
              'assets/brand/aster-logo.svg',
              width: spacing.spacing44,
              colorFilter: ColorFilter.mode(colors.text5, BlendMode.srcIn),
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
                    color: colors.text5,
                  ),
                ),
                SizedBox(width: spacing.spacing4),
                Icon(
                  MingCuteIcons.mgc_wallet_3_line,
                  size: spacing.spacing24,
                  color: colors.text5,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
