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
    final colors = context.appColors;
    final textTheme = context.textTheme;
    final walletState = ref.watch(walletViewModelProvider);
    final activeWallet = walletState.activeWallet;

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
                    details: activeWallet?.walletId ?? '1F29 1127',
                    prefixIcon: MingCuteIcons.mgc_wallet_3_line,
                    onTap: () => context.pushNamed(RouteNames.walletSelection),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.xxl),

            /// Wallet section
            Text(
              'Wallet',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.colorScheme.onSurface,
                letterSpacing: 0.2,
              ),
            ),
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
                      ToastHelper.showSuccess(
                        context,
                        title: 'Wallet details',
                        message: 'Viewing wallet information',
                      );
                    },
                  ),
                  Divider(
                    color: colors.surfaceSubtle,
                    height: 1,
                    thickness: 1,
                    indent: spacing.screenPadding,
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
                    color: colors.surfaceSubtle,
                    height: 1,
                    thickness: 1,
                    indent: spacing.screenPadding,
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
            SizedBox(height: spacing.xxl),

            /// App settings section
            Text(
              'App',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.colorScheme.onSurface,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: spacing.md),
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Column(
                children: [
                  // SettingsOptionRow(
                  //   title: 'Appearance',
                  //   details: 'System',
                  //   prefixIcon: MingCuteIcons.mgc_moon_line,
                  // ),
                  // Divider(
                  //   color: colors.surfaceSubtle,
                  //   height: 1,
                  //   thickness: 1,
                  //   indent: spacing.screenPadding,
                  // ),
                  SettingsOptionRow(
                    title: 'Currency',
                    details: 'USD',
                    prefixIcon: MingCuteIcons.mgc_cash_line,
                    onTap: () =>
                        context.pushNamed(RouteNames.currencySelection),
                  ),
                  Divider(
                    color: colors.surfaceSubtle,
                    height: 1,
                    thickness: 1,
                    indent: spacing.screenPadding,
                  ),
                  SettingsOptionRow(
                    title: 'Language',
                    details: 'English',
                    prefixIcon: MingCuteIcons.mgc_translate_2_line,
                  ),
                  Divider(
                    color: colors.surfaceSubtle,
                    height: 1,
                    thickness: 1,
                    indent: spacing.screenPadding,
                  ),
                  SettingsOptionRow(
                    title: 'Region',
                    details: 'United States',
                    prefixIcon: MingCuteIcons.mgc_world_2_line,
                    onTap: () => context.pushNamed(RouteNames.countrySelection),
                  ),
                  Divider(
                    color: colors.surfaceSubtle,
                    height: 1,
                    thickness: 1,
                    indent: spacing.screenPadding,
                  ),
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
            // Text(
            //   'Info',
            //   style: textTheme.bodyMedium?.copyWith(
            //     fontWeight: FontWeight.w600,
            //     color: context.colorScheme.onSurface,
            //     letterSpacing: 0.2,
            //   ),
            // ),
            // SizedBox(height: spacing.md),
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Column(
                children: [
                  SettingsOptionRow(
                    title: 'Contact Support',
                    prefixIcon: MingCuteIcons.mgc_lifebuoy_line,
                  ),
                  Divider(
                    color: colors.surfaceSubtle,
                    height: 1,
                    thickness: 1,
                    indent: spacing.screenPadding,
                  ),
                  SettingsOptionRow(
                    title: 'Terms of Service',
                    prefixIcon: MingCuteIcons.mgc_document_2_line,
                  ),
                  Divider(
                    color: colors.surfaceSubtle,
                    height: 1,
                    thickness: 1,
                    indent: spacing.screenPadding,
                  ),
                  SettingsOptionRow(
                    title: 'Privacy Policy',
                    prefixIcon: MingCuteIcons.mgc_file_check_line,
                  ),
                  Divider(
                    color: colors.surfaceSubtle,
                    height: 1,
                    thickness: 1,
                    indent: spacing.screenPadding,
                  ),
                  SettingsOptionRow(
                    title: 'Twitter',
                    prefixIcon: MingCuteIcons.mgc_twitter_line,
                    onTap: () {},
                  ),
                  Divider(
                    color: colors.surfaceSubtle,
                    height: 1,
                    thickness: 1,
                    indent: spacing.screenPadding,
                  ),
                  SettingsOptionRow(
                    title: 'Telegram',
                    prefixIcon: MingCuteIcons.mgc_telegram_line,
                    onTap: () {},
                  ),
                  Divider(
                    color: colors.surfaceSubtle,
                    height: 1,
                    thickness: 1,
                    indent: spacing.screenPadding,
                  ),
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
                width: spacing.huge,
                colorFilter: ColorFilter.mode(
                  context.colorScheme.onSurface,
                  BlendMode.srcIn,
                ),
              ),
            ),
            SizedBox(height: spacing.xs),
            Center(
              child: Text(
                'Aster • Version 1.0.0',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
            SizedBox(height: spacing.bottomSafe(context) + spacing.navOffset),
          ],
        ),
      ),
    );
  }
}
