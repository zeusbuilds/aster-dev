import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';
import '../../../wallet/presentation/view_model/viewmodels.dart';
import '../view_model/view_models.dart';

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
    final settings = ref.watch(settingsViewModelProvider);
    final activeWallet = switch (walletState) {
      AsyncData(:final value) => value.activeWallet,
      _ => null,
    };
    final settingsState = settings.value;
    final settingsSnapshot = settingsState?.snapshot;
    final settingsFailure = settings.hasError
        ? FailureMapper.from(settings.error!, StackTrace.current).userMessage
        : null;
    final settingsEnabled = settingsState != null && !settingsState.isSaving;

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
                  AsterOptionRow(
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
                  AsterOptionRow(
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
                  AsterOptionRow(
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
                  AsterOptionRow(
                    title: 'Advanced',
                    prefixIcon: MingCuteIcons.mgc_tool_line,
                    onTap: () => context.pushNamed(RouteNames.advancedSettings),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.xxl),

            /// App settings section
            Text('App', style: type.sectionLabel),
            SizedBox(height: spacing.md),
            Semantics(
              label: settings.isLoading ? 'Loading app settings' : null,
              excludeSemantics: settings.isLoading,
              child: AppSkeletonizer(
                enabled: settings.isLoading,
                child: Squircle(
                  padding: EdgeInsets.symmetric(vertical: spacing.xs),
                  child: Column(
                    children: [
                      AsterOptionRow(
                        title: 'Currency',
                        details:
                            settingsSnapshot?.selectedCurrency.code ??
                            (settings.hasError ? 'Unavailable' : 'Loading'),
                        prefixIcon: MingCuteIcons.mgc_cash_line,
                        onTap: settingsEnabled
                            ? () => context.pushNamed(
                                RouteNames.currencySelection,
                              )
                            : null,
                      ),
                      const AsterDivider.inset(),
                      AsterOptionRow(
                        title: 'Bitcoin unit',
                        details:
                            settingsSnapshot?.preferences.bitcoinUnit.label ??
                            (settings.hasError ? 'Unavailable' : 'Loading'),
                        prefixIcon: MingCuteIcons.mgc_coin_2_line,
                        onTap: settingsEnabled
                            ? () => context.pushNamed(
                                RouteNames.bitcoinUnitSelection,
                              )
                            : null,
                      ),
                      const AsterDivider.inset(),
                      const AsterOptionRow(
                        title: 'Language',
                        details: 'English',
                        prefixIcon: MingCuteIcons.mgc_translate_2_line,
                      ),
                      const AsterDivider.inset(),
                      AsterOptionRow(
                        title: 'Region',
                        details:
                            settingsSnapshot?.selectedRegion.name ??
                            (settings.hasError ? 'Unavailable' : 'Loading'),
                        prefixIcon: MingCuteIcons.mgc_world_2_line,
                        onTap: settingsEnabled
                            ? () =>
                                  context.pushNamed(RouteNames.countrySelection)
                            : null,
                      ),
                      const AsterDivider.inset(),
                      const AsterOptionRow(
                        title: 'Notifications',
                        details: 'Unavailable',
                        prefixIcon: MingCuteIcons.mgc_bell_ringing_line,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (settingsFailure != null) ...[
              SizedBox(height: spacing.md),
              Text(settingsFailure, style: type.errorMessage),
              SizedBox(height: spacing.sm),
              CustomButton(
                text: 'Retry settings',
                variant: ButtonVariant.secondary,
                onTap: () =>
                    ref.read(settingsViewModelProvider.notifier).retry(),
              ),
            ],
            SizedBox(height: spacing.xxl),

            /// App settings section
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Column(
                children: [
                  AsterOptionRow(
                    title: 'Contact Support',
                    prefixIcon: MingCuteIcons.mgc_lifebuoy_line,
                  ),
                  const AsterDivider.inset(),
                  AsterOptionRow(
                    title: 'Terms of Service',
                    prefixIcon: MingCuteIcons.mgc_document_2_line,
                  ),
                  const AsterDivider.inset(),
                  AsterOptionRow(
                    title: 'Privacy Policy',
                    prefixIcon: MingCuteIcons.mgc_file_check_line,
                  ),
                  const AsterDivider.inset(),
                  AsterOptionRow(
                    title: 'Twitter',
                    prefixIcon: MingCuteIcons.mgc_twitter_line,
                    onTap: () {},
                  ),
                  const AsterDivider.inset(),
                  AsterOptionRow(
                    title: 'Telegram',
                    prefixIcon: MingCuteIcons.mgc_telegram_line,
                    onTap: () {},
                  ),
                  const AsterDivider.inset(),
                  AsterOptionRow(
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
              child: Text('UTEXO • Version 1.0.0', style: type.versionLabel),
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
