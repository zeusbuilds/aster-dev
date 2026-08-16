import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/presentation/view_model/view_models.dart';

/// Active wallet identity and wallet-selection command.
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
    final walletName = activeWallet?.name;
    final canSelectWallet = switch (walletState) {
      AsyncData(:final value) when value.wallets.isNotEmpty => true,
      _ => false,
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
              'assets/brand/utexo-mark.svg',
              width: icons.xl,
              colorFilter: ColorFilter.mode(colors.onBrandArt, BlendMode.srcIn),
            ),
          ),
          SizedBox(width: spacing.md),
          Expanded(
            child: Semantics(
              button: true,
              enabled: canSelectWallet,
              liveRegion: walletState.isLoading,
              label: walletState.isLoading
                  ? 'Loading active wallet'
                  : walletName == null
                  ? 'Wallet unavailable'
                  : 'Select wallet, $walletName',
              excludeSemantics: true,
              child: Material(
                color: colors.transparentSurface,
                child: InkWell(
                  onTap: !canSelectWallet
                      ? null
                      : () {
                          unawaited(
                            context.haptics.trigger(HapticIntent.lightImpact),
                          );
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
                        Expanded(
                          child: AppSkeletonizer(
                            enabled: walletState.isLoading,
                            child: Text(
                              walletName ?? 'Wallet unavailable',
                              style: context.type.brandAction.copyWith(
                                color: colors.onBrandArt,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                            ),
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
          ),
        ],
      ),
    );
  }
}
