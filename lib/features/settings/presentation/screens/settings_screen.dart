import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import 'package:aster/features/settings/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/presentation/viewmodels/viewmodels.dart';
import 'package:aster/shared/shared.dart';

/// Settings screen displaying wallet, app, and support options
///
/// Shows active wallet, wallet management, app preferences, and support links
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colors = context.colors;
    final textTheme = context.textTheme;
    final walletState = ref.watch(walletViewModelProvider);
    final activeWallet = walletState.activeWallet;

    return Scaffold(
      backgroundColor: colors.fill1,
      appBar: CustomAppBar(title: 'Settings'),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: spacing.spacing20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Multiple wallets section
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.spacing4),
              child: Column(
                children: [
                  SettingsOptionRow(
                    title: activeWallet?.name ?? 'Main',
                    details: activeWallet?.walletId ?? '1F29 1127',
                    prefixIcon: MingCuteIcons.mgc_wallet_3_line,
                    onTap: () => context.pushNamed(RouteNames.walletSelection),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.spacing24),

            /// Wallet section
            Text(
              'Wallet',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.text1,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: spacing.spacing12),
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.spacing4),
              child: Column(
                children: [
                  SettingsOptionRow(
                    title: 'Wallet details',
                    details: 'Main',
                    prefixIcon: MingCuteIcons.mgc_information_line,
                    onTap: () {
                      ToastHelper.showSuccess(
                        context,
                        title: 'Wallet details',
                        message: 'Viewing wallet information',
                      );
                    },
                  ),
                  Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
                  SettingsOptionRow(
                    title: 'Manage assets',
                    prefixIcon: MingCuteIcons.mgc_coin_2_line,
                    onTap: () {
                      ToastHelper.showFailure(
                        context,
                        title: 'Manage assets',
                        message: 'Failed to load asset management',
                      );
                    },
                  ),
                  Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
                  SettingsOptionRow(
                    title: 'Advanced',
                    prefixIcon: MingCuteIcons.mgc_tool_line,
                    onTap: () {
                      ToastHelper.showWarning(
                        context,
                        title: 'Advanced options',
                        message: 'Proceed with caution',
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.spacing24),

            /// App settings section
            Text(
              'App',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.text1,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: spacing.spacing12),
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.spacing4),
              child: Column(
                children: [
                  // SettingsOptionRow(
                  //   title: 'Appearance',
                  //   details: 'System',
                  //   prefixIcon: MingCuteIcons.mgc_moon_line,
                  // ),
                  // Divider(
                  //   color: colors.fill2,
                  //   height: 1,
                  //   thickness: 1,
                  //   indent: spacing.spacing20,
                  // ),
                  SettingsOptionRow(
                    title: 'Currency',
                    details: 'USD',
                    prefixIcon: MingCuteIcons.mgc_cash_line,
                    onTap: () =>
                        context.pushNamed(RouteNames.currencySelection),
                  ),
                  Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
                  SettingsOptionRow(
                    title: 'Language',
                    details: 'English',
                    prefixIcon: MingCuteIcons.mgc_translate_2_line,
                  ),
                  Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
                  SettingsOptionRow(
                    title: 'Region',
                    details: 'United States',
                    prefixIcon: MingCuteIcons.mgc_world_2_line,
                    onTap: () => context.pushNamed(RouteNames.countrySelection),
                  ),
                  Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
                  SettingsOptionRow(
                    title: 'Notifications',
                    details: 'Enabled',
                    prefixIcon: MingCuteIcons.mgc_bell_ringing_line,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.spacing24),

            /// App settings section
            // Text(
            //   'Info',
            //   style: textTheme.bodyMedium?.copyWith(
            //     fontWeight: FontWeight.w600,
            //     color: colors.text1,
            //     letterSpacing: 0.2,
            //   ),
            // ),
            // SizedBox(height: spacing.spacing12),
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.spacing4),
              child: Column(
                children: [
                  SettingsOptionRow(
                    title: 'Contact Support',
                    prefixIcon: MingCuteIcons.mgc_lifebuoy_line,
                  ),
                  Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
                  SettingsOptionRow(
                    title: 'Terms of Service',
                    prefixIcon: MingCuteIcons.mgc_document_2_line,
                  ),
                  Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
                  SettingsOptionRow(
                    title: 'Privacy Policy',
                    prefixIcon: MingCuteIcons.mgc_file_check_line,
                  ),
                  Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
                  SettingsOptionRow(
                    title: 'Twitter',
                    prefixIcon: MingCuteIcons.mgc_twitter_line,
                    onTap: () {},
                  ),
                  Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
                  SettingsOptionRow(
                    title: 'Telegram',
                    prefixIcon: MingCuteIcons.mgc_telegram_line,
                    onTap: () {},
                  ),
                  Divider(
                    color: colors.fill2,
                    height: 1,
                    thickness: 1,
                    indent: spacing.spacing20,
                  ),
                  SettingsOptionRow(
                    title: 'Instagram',
                    prefixIcon: MingCuteIcons.mgc_instagram_line,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.spacing32),

            /// Footer
            Center(
              child: SvgPicture.asset(
                'assets/brand/aster-logo.svg',
                width: spacing.spacing48,
                colorFilter: ColorFilter.mode(colors.text1, BlendMode.srcIn),
              ),
            ),
            SizedBox(height: spacing.spacing4),
            Center(
              child: Text(
                'Aster • Version 1.0.0',
                style: textTheme.bodySmall?.copyWith(color: colors.text3),
              ),
            ),
            SizedBox(height: spacing.bottomSafeHeight + spacing.spacing44),
          ],
        ),
      ),
    );
  }
}
