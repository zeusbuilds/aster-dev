import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../bridge/presentation/view_model/hosted_bridge_controller.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../../domain/models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Presents independent wallet, preference, package, and public-link state.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  Timer? _retryTimer;
  var _retryIndex = 0;
  var _recovering = false;
  var _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Observe the route and the shell's retained IndexedStack, so an inactive
    // Settings tab never keeps recovery work running behind another flow.
    ModalRoute.isCurrentOf(context);
    TickerMode.valuesOf(context);
    _scheduleRecovery();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _scheduleRecovery();
    } else {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    super.dispose();
  }

  static AppFailure? _failure(AsyncValue<Object?> value) => value.hasError
      ? FailureMapper.from(value.error!, value.stackTrace ?? StackTrace.current)
      : null;

  bool get _walletNeedsRecovery {
    final failure = _failure(ref.read(walletViewModelProvider));
    // Recovery here is a registry read only. A durable deletion or an unknown
    // mutation must never be resumed by an automatic Settings refresh.
    return failure?.retryable == true && !failure!.requiresReconciliation;
  }

  bool get _preferencesNeedRecovery =>
      _failure(ref.read(settingsViewModelProvider))?.retryable == true;

  bool get _metadataNeedsRecovery {
    final info = ref.read(settingsAppViewModelProvider);
    return !info.isLoading &&
        info.value?.metadataLoading != true &&
        (info.value?.metadataFailure ?? _failure(info))?.retryable == true;
  }

  bool get _needsRecovery =>
      _walletNeedsRecovery ||
      _preferencesNeedRecovery ||
      _metadataNeedsRecovery;

  bool get _visible =>
      mounted &&
      _foreground &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled &&
      !ref.read(walletLifecycleViewModelProvider).blocksInteraction;

  void _scheduleRecovery() {
    if (!mounted || _recovering) return;
    if (!_visible) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    if (!_needsRecovery) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryIndex = 0;
      return;
    }
    if (_retryTimer != null) return;
    final delay = _retryDelays[_retryIndex];
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_recoverQuietly());
    });
  }

  Future<void> _recoverQuietly() async {
    if (!mounted || _recovering) return;
    if (!_visible) {
      _scheduleRecovery();
      return;
    }
    _recovering = true;
    try {
      await ref
          .read(settingsRecoveryViewModelProvider.notifier)
          .recover(
            wallet: _walletNeedsRecovery,
            preferences: _preferencesNeedRecovery,
            metadata: _metadataNeedsRecovery,
          );
    } finally {
      _recovering = false;
      if (_retryIndex < _retryDelays.length - 1) _retryIndex += 1;
      if (mounted) _scheduleRecovery();
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final metrics = context.metrics;
    final type = context.type;
    final isDuoCover =
        ref
            .watch(duoCoverLayoutProvider)
            .value
            ?.appliesTo(MediaQuery.sizeOf(context)) ==
        true;
    final hasBottomTabs =
        !isDuoCover || CoverTabRail.hasBottomFallbackOf(context);
    final walletState = ref.watch(walletViewModelProvider);
    final settings = ref.watch(settingsViewModelProvider);
    final appInfo = ref.watch(settingsAppViewModelProvider);
    final hostedBridge = ref.watch(hostedBridgeControllerProvider);
    final activeWallet = switch (walletState) {
      AsyncData(:final value) => value.activeWallet,
      _ => null,
    };
    final walletFailure = _failure(walletState);
    final walletLoading = walletState.isLoading;
    final walletDetailsEnabled =
        !walletLoading &&
        walletFailure == null &&
        walletState.value?.isChangingWallet != true &&
        activeWallet?.state == WalletProfileState.ready;
    final settingsState = settings.value;
    // Defaults are a display fallback only, never written over a preference
    // whose storage could not be read (including balance-visibility choices).
    final preferences =
        settingsState?.snapshot.preferences ?? AppPreferences.defaults;
    final settingsEnabled =
        !settings.hasError &&
        !settings.isLoading &&
        settingsState != null &&
        !settingsState.isSaving;
    ref.listen(walletLifecycleViewModelProvider, (_, _) => _scheduleRecovery());
    ref.listen(walletViewModelProvider, (_, _) => _scheduleRecovery());
    ref.listen(settingsViewModelProvider, (_, _) => _scheduleRecovery());
    ref.listen(settingsAppViewModelProvider, (_, _) => _scheduleRecovery());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleRecovery();
    });

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
            body: AsterHorizontalSafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.screenPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Squircle(
                      padding: EdgeInsets.symmetric(vertical: spacing.xs),
                      child: AsterOptionRow(
                        key: const ValueKey('settings-wallet-summary'),
                        title: activeWallet?.name ?? 'Wallet',
                        details: activeWallet?.displayId,
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
                    SizedBox(height: spacing.xxl),

                    Text('Wallet', style: type.sectionLabel),
                    SizedBox(height: spacing.md),
                    Squircle(
                      padding: EdgeInsets.symmetric(vertical: spacing.xs),
                      child: Column(
                        children: [
                          AsterOptionRow(
                            title: 'Wallet details',
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
                          if (hostedBridge != null)
                            ListenableBuilder(
                              listenable: hostedBridge,
                              builder: (context, _) => hostedBridge.available
                                  ? Column(
                                      children: [
                                        const AsterDivider.inset(),
                                        AsterOptionRow(
                                          title: 'Dev Bridge',
                                          prefixIcon: Icons.link,
                                          onTap: openNamed(
                                            RouteNames.hostedBridge,
                                            'Dev Bridge could not open',
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: spacing.xxl),

                    Text('App', style: type.sectionLabel),
                    SizedBox(height: spacing.md),
                    Squircle(
                      padding: EdgeInsets.symmetric(vertical: spacing.xs),
                      child: Column(
                        children: [
                          AsterOptionRow(
                            title: 'Bitcoin unit',
                            details: preferences.bitcoinUnit.label,
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
                            title: 'Currency',
                            details: 'USD',
                            prefixIcon: MingCuteIcons.mgc_cash_line,
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
                    SizedBox(height: spacing.xxl),

                    SettingsLinksCard(
                      state: appInfo.value,
                      loading: appInfo.isLoading,
                      onOpen: (link) =>
                          unawaited(_openLink(context, ref, link)),
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
                    SettingsVersionFooter(appInfo: appInfo),
                    SizedBox(
                      height:
                          context.windowInsets.bottomSystem +
                          spacing.lg +
                          (hasBottomTabs ? metrics.floatingNavClearance : 0),
                    ),
                  ],
                ),
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
