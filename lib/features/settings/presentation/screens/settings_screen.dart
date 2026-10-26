import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../../domain/models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Presents independent wallet, preference, package, and public-link state.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final metrics = context.metrics;
    final type = context.type;
    final walletState = ref.watch(walletViewModelProvider);
    final settings = ref.watch(settingsViewModelProvider);
    final appInfo = ref.watch(settingsAppViewModelProvider);
    final activeWallet = switch (walletState) {
      AsyncData(:final value) => value.activeWallet,
      _ => null,
    };
    final walletFailure = walletState.hasError
        ? FailureMapper.from(
            walletState.error!,
            walletState.stackTrace ?? StackTrace.current,
          )
        : null;
    final walletLoading = walletState.isLoading;
    final walletDetailsEnabled =
        !walletLoading &&
        walletFailure == null &&
        walletState.value?.isChangingWallet != true &&
        activeWallet?.state == WalletProfileState.ready;
    final settingsState = settings.value;
    final settingsSnapshot = settingsState?.snapshot;
    final settingsFailure = settings.hasError
        ? FailureMapper.from(
            settings.error!,
            settings.stackTrace ?? StackTrace.current,
          )
        : null;
    final settingsEnabled = settingsState != null && !settingsState.isSaving;

    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);

          VoidCallback? openNamed(String routeName, String failureTitle) {
            if (navigation.inFlight) return null;
            return () => unawaited(
              navigation.openRoute(
                command: () => context.pushNamed<void>(routeName),
                failureTitle: failureTitle,
              ),
            );
          }

          return Scaffold(
            backgroundColor: context.colorScheme.surface,
            appBar: CustomAppBar(title: 'Settings'),
            body: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: walletLoading,
                    label: walletLoading ? 'Loading wallet' : null,
                    excludeSemantics: walletLoading,
                    child: AppSkeletonizer(
                      enabled: walletLoading,
                      child: Squircle(
                        padding: EdgeInsets.symmetric(vertical: spacing.xs),
                        child: AsterOptionRow(
                          key: const ValueKey('settings-wallet-summary'),
                          title: walletLoading
                              ? 'Loading wallet'
                              : walletFailure != null
                              ? 'Wallet unavailable'
                              : activeWallet?.name ?? 'No active wallet',
                          details: walletLoading || walletFailure != null
                              ? null
                              : activeWallet?.displayId ?? 'Choose wallet',
                          prefixIcon: MingCuteIcons.mgc_wallet_3_line,
                          hapticIntent: null,
                          onTap:
                              walletLoading ||
                                  walletFailure != null ||
                                  navigation.inFlight
                              ? null
                              : openNamed(
                                  RouteNames.walletSelection,
                                  'Wallet selector could not open',
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (walletFailure != null) ...[
                    SizedBox(height: spacing.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        walletFailure.userMessage,
                        style: type.errorMessage,
                      ),
                    ),
                    if (walletFailure.retryable) ...[
                      SizedBox(height: spacing.sm),
                      CustomButton.compact(
                        text: 'Retry wallet',
                        variant: ButtonVariant.secondary,
                        onTap: () => unawaited(
                          ref.read(walletViewModelProvider.notifier).reload(),
                        ),
                      ),
                    ],
                  ],
                  SizedBox(height: spacing.xxl),

                  Text('Wallet', style: type.sectionLabel),
                  SizedBox(height: spacing.md),
                  Squircle(
                    padding: EdgeInsets.symmetric(vertical: spacing.xs),
                    child: Column(
                      children: [
                        AsterOptionRow(
                          title: 'Wallet details',
                          details: walletDetailsEnabled
                              ? null
                              : walletLoading
                              ? 'Loading'
                              : 'Unavailable',
                          prefixIcon: MingCuteIcons.mgc_information_line,
                          hapticIntent: null,
                          onTap: walletDetailsEnabled
                              ? openNamed(
                                  RouteNames.walletDetails,
                                  'Wallet details could not open',
                                )
                              : null,
                        ),
                        const AsterDivider.inset(),
                        AsterOptionRow(
                          title: 'Security',
                          prefixIcon: MingCuteIcons.mgc_shield_line,
                          hapticIntent: null,
                          onTap: openNamed(
                            RouteNames.security,
                            'Security settings could not open',
                          ),
                        ),
                        const AsterDivider.inset(),
                        AsterOptionRow(
                          title: 'Advanced',
                          prefixIcon: MingCuteIcons.mgc_tool_line,
                          hapticIntent: null,
                          onTap: openNamed(
                            RouteNames.advancedSettings,
                            'Advanced settings could not open',
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: spacing.xxl),

                  Text('App', style: type.sectionLabel),
                  SizedBox(height: spacing.md),
                  Semantics(
                    liveRegion: settings.isLoading,
                    label: settings.isLoading ? 'Loading app settings' : null,
                    excludeSemantics: settings.isLoading,
                    child: AppSkeletonizer(
                      enabled: settings.isLoading,
                      child: Squircle(
                        padding: EdgeInsets.symmetric(vertical: spacing.xs),
                        child: Column(
                          children: [
                            const AsterOptionRow(
                              title: 'Currency',
                              details: 'USD',
                              prefixIcon: MingCuteIcons.mgc_cash_line,
                            ),
                            const AsterDivider.inset(),
                            AsterOptionRow(
                              title: 'Bitcoin unit',
                              details:
                                  settingsSnapshot
                                      ?.preferences
                                      .bitcoinUnit
                                      .label ??
                                  (settings.hasError
                                      ? 'Unavailable'
                                      : 'Loading'),
                              prefixIcon: MingCuteIcons.mgc_coin_2_line,
                              hapticIntent: null,
                              onTap: settingsEnabled && !navigation.inFlight
                                  ? openNamed(
                                      RouteNames.bitcoinUnitSelection,
                                      'Bitcoin unit selector could not open',
                                    )
                                  : null,
                            ),
                            const AsterDivider.inset(),
                            const AsterOptionRow(
                              title: 'Language',
                              details: 'English',
                              prefixIcon: MingCuteIcons.mgc_translate_2_line,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (settingsFailure != null) ...[
                    SizedBox(height: spacing.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        settingsFailure.userMessage,
                        style: type.errorMessage,
                      ),
                    ),
                    if (settingsFailure.retryable) ...[
                      SizedBox(height: spacing.sm),
                      CustomButton(
                        text: 'Retry settings',
                        variant: ButtonVariant.secondary,
                        onTap: () => ref
                            .read(settingsViewModelProvider.notifier)
                            .retry(),
                      ),
                    ],
                  ],
                  SizedBox(height: spacing.xxl),

                  SettingsLinksCard(
                    state: appInfo.value,
                    loading: appInfo.isLoading,
                    onOpen: (link) => unawaited(_openLink(context, ref, link)),
                  ),
                  SizedBox(height: spacing.xxxl),

                  Center(
                    child: SvgPicture.asset(
                      'assets/brand/aster-mark.svg',
                      width: metrics.brandMarkSize,
                      colorFilter: ColorFilter.mode(
                        context.colorScheme.onSurface,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  SizedBox(height: spacing.xs),
                  SettingsVersionFooter(
                    appInfo: appInfo,
                    onRetry: () {
                      if (appInfo.value case final state?) {
                        if (state.metadataLoading) return;
                        unawaited(
                          ref
                              .read(settingsAppViewModelProvider.notifier)
                              .retryMetadata(),
                        );
                        return;
                      }
                      ref.invalidate(settingsAppViewModelProvider);
                    },
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
        },
      ),
    );
  }

  Future<void> _openLink(
    BuildContext context,
    WidgetRef ref,
    SettingsExternalLink link,
  ) async {
    final toasts = context.toasts;
    final opened = await ref
        .read(settingsAppViewModelProvider.notifier)
        .openLink(link);
    if (!context.mounted) return;
    if (opened) {
      unawaited(context.haptics.trigger(HapticIntent.lightImpact));
      return;
    }
    final failure = ref
        .read(settingsAppViewModelProvider)
        .value
        ?.operationFailure;
    if (failure == null) return;
    unawaited(context.haptics.trigger(HapticIntent.error));
    toasts.show(
      title: 'Link not opened',
      message: failure.userMessage,
      variant: ToastVariant.failure,
    );
    ref.read(settingsAppViewModelProvider.notifier).clearOperationFailure();
  }
}
