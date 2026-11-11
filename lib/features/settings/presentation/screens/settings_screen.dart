import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../bridge/presentation/hosted_bridge_screen.dart';
import '../../../bridge/presentation/view_model/hosted_bridge_controller.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/pages/wallet_selection_screen.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../../domain/models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';
import 'advanced_settings_screen.dart';
import 'bitcoin_unit_selection_screen.dart';
import 'network_configuration_screen.dart';
import 'security_settings_screen.dart';
import 'wallet_details_screen.dart';

enum _SettingsPanel {
  walletDetails(RouteNames.walletDetails, 'Wallet details could not open'),
  security(RouteNames.security, 'Security settings could not open'),
  advanced(RouteNames.advancedSettings, 'Advanced settings could not open'),
  devBridge(RouteNames.hostedBridge, 'Dev Bridge could not open'),
  wallets(
    RouteNames.walletSelection,
    'Wallet selector could not open',
    canClose: true,
  ),
  bitcoinUnit(
    RouteNames.bitcoinUnitSelection,
    'Bitcoin unit selector could not open',
    canClose: true,
  ),
  network(
    RouteNames.networkConfiguration,
    'Network configuration could not open',
    canClose: true,
  );

  const _SettingsPanel(
    this.routeName,
    this.failureTitle, {
    this.canClose = false,
  });

  final String routeName;
  final String failureTitle;
  final bool canClose;
}

/// Presents independent wallet, preference, package, and public-link state.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.isActiveTab});

  /// Selection state when mounted as a tab. Standalone routes omit it.
  final bool? isActiveTab;

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
  final _panelKey = GlobalKey();
  var _panel = _SettingsPanel.walletDetails;
  var _returnPanel = _SettingsPanel.walletDetails;
  var _retainPanel = false;
  var _resetPanelWhenIdle = false;

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
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActiveTab == true && widget.isActiveTab == false) {
      _resetPanelWhenIdle = true;
    }
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

  void _openPanel(_SettingsPanel panel) {
    if (_panel == panel) return;
    setState(() {
      if (panel.canClose && !_panel.canClose) _returnPanel = _panel;
      _panel = panel;
    });
  }

  void _closePanel(_SettingsPanel panel) {
    if (mounted && _panel == panel) _openPanel(_returnPanel);
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
        !(isDuoCover || context.isOpenDuoLandscape) ||
        CoverTabRail.hasBottomFallbackOf(context);
    final split = context.fitsDuoLandscapePanes;
    final tabClearance = hasBottomTabs ? metrics.floatingNavClearance : 0.0;
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
          if (_resetPanelWhenIdle && !navigation.inFlight) {
            // Keep an in-flight panel mounted until its completion is handled.
            _panel = _SettingsPanel.walletDetails;
            _returnPanel = _SettingsPanel.walletDetails;
            _resetPanelWhenIdle = false;
          }

          VoidCallback? open(_SettingsPanel panel) {
            if (navigation.inFlight) return null;
            if (split) {
              return () {
                if (navigation.inFlight || _panel == panel) return;
                FocusScope.of(context).unfocus();
                unawaited(context.haptics.trigger(HapticIntent.selection));
                _openPanel(panel);
              };
            }
            return () => unawaited(
              navigation.openRoute(
                command: () => context.pushNamed<void>(panel.routeName),
                failureTitle: panel.failureTitle,
              ),
            );
          }

          final options = Scaffold(
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
                            : open(_SettingsPanel.wallets),
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
                                ? open(_SettingsPanel.walletDetails)
                                : null,
                          ),
                          const AsterDivider.inset(),
                          AsterOptionRow(
                            title: 'Security',
                            prefixIcon: MingCuteIcons.mgc_shield_line,
                            hapticIntent: null,
                            onTap: open(_SettingsPanel.security),
                          ),
                          const AsterDivider.inset(),
                          AsterOptionRow(
                            title: 'Advanced',
                            prefixIcon: MingCuteIcons.mgc_tool_line,
                            hapticIntent: null,
                            onTap: open(_SettingsPanel.advanced),
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
                                          onTap: open(_SettingsPanel.devBridge),
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
                                ? open(_SettingsPanel.bitcoinUnit)
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
                          tabClearance,
                    ),
                  ],
                ),
              ),
            ),
          );

          if (split) {
            _retainPanel = true;
          } else if (!navigation.inFlight) {
            _retainPanel = false;
          }
          if (!_retainPanel) return options;

          Widget withPanel(bool bridgeAvailable) {
            final panel =
                _panel == _SettingsPanel.devBridge &&
                    !bridgeAvailable &&
                    !navigation.inFlight
                ? _SettingsPanel.walletDetails
                : _panel;
            Widget detailFor({required bool showNetworkBack}) {
              final content = switch (panel) {
                _SettingsPanel.walletDetails => const WalletDetailsScreen(
                  embedded: true,
                ),
                _SettingsPanel.security => const SecuritySettingsScreen(
                  embedded: true,
                ),
                _SettingsPanel.advanced => AdvancedSettingsScreen(
                  embedded: true,
                  onOpenNetworkConfiguration: open(_SettingsPanel.network),
                ),
                _SettingsPanel.network => NetworkConfigurationScreen(
                  onClose: () => _closePanel(panel),
                  showBack: showNetworkBack,
                ),
                _SettingsPanel.wallets => WalletSelectionScreen(
                  onClose: () => _closePanel(panel),
                  showBack: false,
                ),
                _SettingsPanel.bitcoinUnit => BitcoinUnitSelectionScreen(
                  onClose: () => _closePanel(panel),
                  showBack: false,
                ),
                _SettingsPanel.devBridge => const HostedBridgeScreen(
                  embedded: true,
                ),
              };
              return KeyedSubtree(
                key: _panelKey,
                child: KeyedSubtree(key: ValueKey(panel), child: content),
              );
            }

            if (!split) {
              // A pending operation keeps its owner through a fold. Only the
              // original Settings list remains visible and interactive.
              return Stack(
                fit: StackFit.expand,
                children: [
                  Offstage(
                    child: ExcludeFocus(
                      child: TickerMode(
                        enabled: false,
                        child: detailFor(showNetworkBack: true),
                      ),
                    ),
                  ),
                  options,
                ],
              );
            }
            final media = MediaQuery.of(context);
            return DuoBackNavigation(
              showBack: panel == _SettingsPanel.network,
              onBack: !navigation.inFlight
                  ? () => unawaited(
                      navigation.run(
                        command: () => _closePanel(panel),
                        failureTitle: 'Previous page could not open',
                      ),
                    )
                  : null,
              builder: (context, usesRail) => MediaQuery(
                // Detail panels already place the bottom inset inside their
                // content. Include any horizontal tab fallback in that inset.
                data: media.copyWith(
                  padding: media.padding.copyWith(
                    bottom: media.padding.bottom + tabClearance,
                  ),
                  viewPadding: media.viewPadding.copyWith(
                    bottom: media.viewPadding.bottom + tabClearance,
                  ),
                ),
                child: DuoLandscapePanes(
                  left: options,
                  right: detailFor(showNetworkBack: !usesRail),
                ),
              ),
            );
          }

          return hostedBridge == null
              ? withPanel(false)
              : ListenableBuilder(
                  listenable: hostedBridge,
                  builder: (context, _) => withPanel(hostedBridge.available),
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
