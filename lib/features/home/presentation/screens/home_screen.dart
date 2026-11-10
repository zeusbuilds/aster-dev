import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../settings/presentation/view_model/view_models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Active-wallet overview with truthful market and cross-rail balance states.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const _HomeBalanceRefreshSurface();
}

class _HomeBalanceRefreshSurface extends ConsumerStatefulWidget {
  const _HomeBalanceRefreshSurface();

  @override
  ConsumerState<_HomeBalanceRefreshSurface> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<_HomeBalanceRefreshSurface>
    with WidgetsBindingObserver {
  static const _refreshInterval = Duration(seconds: 30);

  // Keep chart animation and asset quote state when the two panes reparent.
  final _priceCardKey = GlobalKey();
  final _assetsKey = GlobalKey();
  Timer? _refreshTimer;
  var _visible = false;
  var _hasBeenVisible = false;
  var _refreshOnEntry = false;
  var _entryCallbackQueued = false;
  var _refreshInFlight = false;
  var _visibilityRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A newly attached surface may retain an already-loaded provider (for
    // example after hot reload). Refresh that snapshot on its first entry;
    // the ordinary initial AsyncLoading read needs no duplicate request.
    _hasBeenVisible = ref.read(homeViewModelProvider) is AsyncData<HomeState>;
    ref.listenManual(homeViewModelProvider, (_, _) => _scheduleRefresh());
    ref.listenManual(
      walletLifecycleViewModelProvider,
      (_, _) => _scheduleRefresh(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route and IndexedStack visibility, including a pushed
    // Activity/Receive route and a tab retained with TickerMode disabled.
    ModalRoute.isCurrentOf(context);
    TickerMode.valuesOf(context);
    _scheduleRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cancel immediately on inactive/paused, before another widget build.
    // A resumed OS alone is insufficient: native resume must also settle.
    _scheduleRefresh();
  }

  bool get _isVisible =>
      mounted &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      !ref.read(walletLifecycleViewModelProvider).blocksInteraction;

  void _scheduleRefresh() {
    if (!mounted) return;
    final visible = _isVisible;
    if (visible != _visible) {
      _visibilityRevision += 1;
      _visible = visible;
      _refreshOnEntry = visible && _hasBeenVisible;
      _hasBeenVisible = _hasBeenVisible || visible;
      _cancelTimer();
    }
    final home = ref.read(homeViewModelProvider);
    if (!visible ||
        home is! AsyncData<HomeState> ||
        home.value.refreshing ||
        _refreshInFlight ||
        !_canRefreshFailure(home.value.refreshFailure)) {
      _cancelTimer();
      return;
    }
    if (_refreshOnEntry) {
      if (_entryCallbackQueued) return;
      _entryCallbackQueued = true;
      final revision = _visibilityRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _entryCallbackQueued = false;
        if (!mounted) return;
        if (revision == _visibilityRevision && _isVisible) {
          unawaited(_refreshBalances());
        } else {
          _scheduleRefresh();
        }
      });
      return;
    }
    // One timer per completed read. Slow native work never accumulates polls.
    final revision = _visibilityRevision;
    _refreshTimer ??= Timer(_refreshInterval, () {
      _refreshTimer = null;
      if (mounted && revision == _visibilityRevision && _isVisible) {
        unawaited(_refreshBalances());
      }
    });
  }

  Future<void> _refreshBalances() async {
    if (!_isVisible || _refreshInFlight) return;
    final home = ref.read(homeViewModelProvider);
    if (home is! AsyncData<HomeState> ||
        home.value.refreshing ||
        !_canRefreshFailure(home.value.refreshFailure)) {
      return;
    }
    final notifier = ref.read(homeViewModelProvider.notifier);
    _cancelTimer();
    _refreshOnEntry = false;
    _refreshInFlight = true;
    try {
      await notifier.refresh();
    } finally {
      _refreshInFlight = false;
      if (mounted) _scheduleRefresh();
    }
  }

  static bool _canRefreshFailure(AppFailure? failure) =>
      failure == null || (failure.retryable && !failure.requiresReconciliation);

  void _cancelTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visibilityRevision += 1;
    _cancelTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeViewModelProvider);
    ref.watch(settingsViewModelProvider);
    final viewport = MediaQuery.sizeOf(context);
    final isDuoCover =
        ref.watch(duoCoverLayoutProvider).value?.appliesTo(viewport) == true;
    final heroMinimumHeight =
        viewport.height * context.metrics.homeHeroHeightFactor;
    final systemPadding = context.windowInsets.systemPadding;
    final split = context.fitsDuoLandscapePanes;
    // Draw the chart behind the status indicators and keep its controls inside
    // the safe edges.
    final horizontalInsets = EdgeInsets.only(
      left: systemPadding.left,
      right: systemPadding.right,
    );
    final topInset = isDuoCover
        ? math.max(systemPadding.top, context.spacing.md)
        : systemPadding.top;
    final bottomNavSpace = CoverTabRail.boundsOf(context) == null
        ? context.spacing.sm + context.metrics.bottomNavHeight
        : 0.0;
    final bottomContentInset =
        context.windowInsets.bottomSystem +
        bottomNavSpace +
        (context.isOpenDuoLandscape ? context.spacing.lg : context.spacing.xxl);
    final chartHeight = context.metrics.chartHeight;
    final actions = Padding(
      padding: EdgeInsets.only(top: context.spacing.lg),
      child: HomeActionButtons(stacked: split),
    );
    final heroContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const HomeHeader(),
        PriceCard(
          key: _priceCardKey,
          chartHeight: split
              ? (viewport.height / 3).clamp(chartHeight, chartHeight * 2)
              : null,
        ),
        if (!split) actions,
      ],
    );
    final assets = AssetsSection(
      key: _assetsKey,
      home: home,
      showTopGap: !split,
    );
    final bottomGap = SliverToBoxAdapter(
      child: SizedBox(height: bottomContentInset),
    );
    final lightStatus = !split || systemPadding.left > systemPadding.right;

    return AsterNavigationScope(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: context.appColors.transparentSurface,
          statusBarIconBrightness: lightStatus
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: lightStatus ? Brightness.dark : Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: context.colorScheme.surface,
          body: split
              ? Row(
                  textDirection: TextDirection.ltr,
                  children: [
                    Expanded(
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const MeshGradientBackground(),
                            LayoutBuilder(
                              builder: (context, constraints) =>
                                  _HomeScrollView(
                                    primary: false,
                                    slivers: [
                                      SliverToBoxAdapter(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            minHeight: constraints.maxHeight,
                                          ),
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              top: topInset,
                                              left: horizontalInsets.left,
                                              bottom: bottomContentInset,
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [heroContent, actions],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _HomeScrollView(
                        primary: false,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: topInset,
                                right: horizontalInsets.right,
                              ),
                              child: assets,
                            ),
                          ),
                          bottomGap,
                        ],
                      ),
                    ),
                  ],
                )
              : _HomeScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: heroMinimumHeight,
                        ),
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.passthrough,
                            children: [
                              const Positioned.fill(
                                child: MeshGradientBackground(),
                              ),
                              Padding(
                                padding:
                                    horizontalInsets +
                                    EdgeInsets.only(
                                      top: topInset,
                                      bottom: context.spacing.lg,
                                    ),
                                child: heroContent,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(padding: horizontalInsets, child: assets),
                    ),
                    bottomGap,
                  ],
                ),
        ),
      ),
    );
  }
}

class _HomeScrollView extends StatelessWidget {
  const _HomeScrollView({this.primary, required this.slivers});

  final bool? primary;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<OverscrollIndicatorNotification>(
      onNotification: (notification) {
        // Keep the top edge fixed while allowing the bottom-edge bounce.
        if (notification.depth == 0 && notification.leading) {
          notification.disallowIndicator();
        }
        return false;
      },
      child: CustomScrollView(
        primary: primary,
        physics: const _HomeScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: slivers,
      ),
    );
  }
}

/// Holds the top edge in place while preserving the bottom-edge bounce.
///
/// Boundary conditions apply to both pointer updates and ballistic simulations,
/// so a fling toward the top cannot expose blank space above the hero either.
class _HomeScrollPhysics extends BouncingScrollPhysics {
  const _HomeScrollPhysics({super.parent});

  @override
  _HomeScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _HomeScrollPhysics(parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value < position.pixels &&
        position.pixels <= position.minScrollExtent) {
      return value - position.pixels;
    }
    if (value < position.minScrollExtent &&
        position.pixels > position.minScrollExtent) {
      return value - position.minScrollExtent;
    }
    return super.applyBoundaryConditions(position, value);
  }
}
