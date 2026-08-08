import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/presentation/view_model/viewmodels.dart';
import '../widgets/widgets.dart';

/// Settings screen displaying wallet, app, and support options
///
/// Shows active wallet, wallet management, app preferences, and support links
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final metrics = context.metrics;
    final type = context.type;
    final walletState = ref.watch(walletViewModelProvider);
    final activeWallet = switch (walletState) {
      AsyncData(:final value) => value.activeWallet,
      _ => null,
    };

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(title: 'Settings'),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Multiple wallets section
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Column(
                children: [
                  SettingsOptionRow(
                    title: activeWallet?.name ?? 'Main',
                    details: activeWallet?.displayId,
                    prefixIcon: MingCuteIcons.mgc_wallet_3_line,
                    onTap: () => context.pushNamed(RouteNames.walletSelection),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.xxl),

            /// Wallet section
            Text('Wallet', style: type.sectionLabel),
            SizedBox(height: spacing.md),
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Column(
                children: [
                  SettingsOptionRow(
                    title: 'Wallet details',
                    details: 'Main',
                    prefixIcon: MingCuteIcons.mgc_information_line,
                    onTap: () {
                      context.toasts.show(
                        title: 'Wallet details',
                        message: 'Wallet details are not available yet.',
                        variant: ToastVariant.info,
                      );
                    },
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Manage assets',
                    prefixIcon: MingCuteIcons.mgc_coin_2_line,
                    onTap: () {
                      context.toasts.show(
                        title: 'Manage assets',
                        message: 'Asset management is not available yet.',
                        variant: ToastVariant.info,
                      );
                    },
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Advanced',
                    prefixIcon: MingCuteIcons.mgc_tool_line,
                    onTap: () {
                      context.toasts.show(
                        title: 'Advanced options',
                        message: 'Advanced options are not available yet.',
                        variant: ToastVariant.info,
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.xxl),

            /// App settings section
            Text('App', style: type.sectionLabel),
            SizedBox(height: spacing.md),
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Column(
                children: [
                  SettingsOptionRow(
                    title: 'Currency',
                    details: 'USD',
                    prefixIcon: MingCuteIcons.mgc_cash_line,
                    onTap: () =>
                        context.pushNamed(RouteNames.currencySelection),
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Language',
                    details: 'English',
                    prefixIcon: MingCuteIcons.mgc_translate_2_line,
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Region',
                    details: 'United States',
                    prefixIcon: MingCuteIcons.mgc_world_2_line,
                    onTap: () => context.pushNamed(RouteNames.countrySelection),
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Notifications',
                    details: 'Enabled',
                    prefixIcon: MingCuteIcons.mgc_bell_ringing_line,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.xxl),

            /// App settings section
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Column(
                children: [
                  SettingsOptionRow(
                    title: 'Contact Support',
                    prefixIcon: MingCuteIcons.mgc_lifebuoy_line,
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Terms of Service',
                    prefixIcon: MingCuteIcons.mgc_document_2_line,
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Privacy Policy',
                    prefixIcon: MingCuteIcons.mgc_file_check_line,
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Twitter',
                    prefixIcon: MingCuteIcons.mgc_twitter_line,
                    onTap: () {},
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Telegram',
                    prefixIcon: MingCuteIcons.mgc_telegram_line,
                    onTap: () {},
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Instagram',
                    prefixIcon: MingCuteIcons.mgc_instagram_line,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.xxxl),

            /// Footer
            Center(
              child: SvgPicture.asset(
                'assets/brand/aster-logo.svg',
                width: metrics.brandMarkSize,
                colorFilter: ColorFilter.mode(
                  context.colorScheme.onSurface,
                  BlendMode.srcIn,
                ),
              ),
            ),
            SizedBox(height: spacing.xs),
            Center(
              child: Text('Aster • Version 1.0.0', style: type.versionLabel),
            ),
            SizedBox(
              height:
                  context.windowInsets.bottomSystem +
                  spacing.lg +
                  metrics.floatingNavClearance,
            ),
          ],
        ),
      ),
    );
  }
}
