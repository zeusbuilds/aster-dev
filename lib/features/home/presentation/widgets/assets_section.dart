import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../market/domain/models/models.dart';
import '../../../market/presentation/models/models.dart';
import '../../../market/presentation/view_model/view_models.dart';
import '../../../settings/presentation/models/models.dart';
import '../../../settings/presentation/view_model/view_models.dart';
import '../../../wallet/domain/models/models.dart';
import '../formatting/formatting.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import 'asset_row.dart';

/// Portfolio section backed by active-wallet, settings, and market state.
class AssetsSection extends ConsumerStatefulWidget {
  const AssetsSection({required this.home, super.key});

  final AsyncValue<HomeState> home;

  @override
  ConsumerState<AssetsSection> createState() => _AssetsSectionState();
}

class _AssetsSectionState extends ConsumerState<AssetsSection> {
  Timer? _marketExpiryTimer;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      bitcoinMarketViewModelProvider,
      (previous, next) => _scheduleMarketExpiry(next.value?.snapshot),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _marketExpiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleMarketExpiry(BitcoinMarketSnapshot? snapshot) {
    _marketExpiryTimer?.cancel();
    if (snapshot == null) return;
    final now = ref.read(utcClockProvider)().toUtc();
    final expiries = <DateTime>[
      snapshot.currentBitcoinPrice.expiresAt,
      if (snapshot.currentUsdtPrice case final price?) price.expiresAt,
    ]..sort();
    DateTime? nextExpiry;
    for (final expiry in expiries) {
      if (expiry.isAfter(now)) {
        nextExpiry = expiry;
        break;
      }
    }
    if (nextExpiry == null) return;
    final remaining = nextExpiry.difference(now);
    _marketExpiryTimer = Timer(remaining + const Duration(milliseconds: 1), () {
      if (!mounted) return;
      setState(() {});
      _scheduleMarketExpiry(snapshot);
    });
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.home;
    final settings = ref.watch(settingsViewModelProvider);
    final market = ref.watch(bitcoinMarketViewModelProvider);
    final clock = ref.watch(utcClockProvider);
    final settingsState = settings.value;
    final visibilitySaving =
        settingsState?.operation == SettingsOperation.balanceVisibility;
    final balancesVisible = settingsState?.snapshot.preferences.balancesVisible;

    Future<void> toggleVisibility() async {
      final current = balancesVisible;
      if (current == null || visibilitySaving) return;
      final succeeded = await ref
          .read(settingsViewModelProvider.notifier)
          .setBalancesVisible(!current);
      if (!context.mounted) return;
      if (succeeded) {
        unawaited(context.haptics.trigger(HapticIntent.selection));
        return;
      }
      final failure = ref
          .read(settingsViewModelProvider)
          .value
          ?.operationFailure;
      if (failure == null) return;
      unawaited(context.haptics.trigger(HapticIntent.error));
      context.toasts.show(
        title: 'Could not update balance visibility',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
      ref.read(settingsViewModelProvider.notifier).clearOperationFailure();
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.screenPadding),
      child: Column(
        children: [
          SizedBox(height: context.spacing.screenPadding),
          Row(
            children: [
              Expanded(child: Text('Assets', style: context.type.sectionTitle)),
              AsterIconButton(
                icon: balancesVisible == false
                    ? MingCuteIcons.mgc_eye_close_line
                    : MingCuteIcons.mgc_eye_2_line,
                tooltip: balancesVisible == false
                    ? 'Show balances'
                    : 'Hide balances',
                hapticIntent: null,
                loading: visibilitySaving,
                color: context.appColors.textSecondary,
                onPressed: balancesVisible == null ? null : toggleVisibility,
              ),
            ],
          ),
          SizedBox(height: context.spacing.lg),
          _AssetsBody(
            home: home,
            settings: settings,
            market: market,
            now: clock().toUtc(),
          ),
        ],
      ),
    );
  }
}

class _AssetsBody extends ConsumerWidget {
  const _AssetsBody({
    required this.home,
    required this.settings,
    required this.market,
    required this.now,
  });

  final AsyncValue<HomeState> home;
  final AsyncValue<SettingsState> settings;
  final AsyncValue<BitcoinMarketState> market;
  final DateTime now;

  static final _formatter = HomeAssetDisplayFormatter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (home.isLoading || settings.isLoading) {
      return const _AssetLoadingList();
    }
    if (home case AsyncError(:final error, :final stackTrace)) {
      return _AssetsFailure(
        failure: _failure(error, stackTrace),
        onRetry: () => ref.read(homeViewModelProvider.notifier).retry(),
      );
    }
    if (settings case AsyncError(:final error, :final stackTrace)) {
      return _AssetsFailure(
        failure: _failure(error, stackTrace),
        onRetry: () => ref.read(settingsViewModelProvider.notifier).retry(),
      );
    }
    final homeState = home.requireValue;
    final settingsState = settings.requireValue;
    final navigation = AsterNavigationScope.of(context);
    final preferences = settingsState.snapshot.preferences;
    final marketState = market.value;
    final marketSnapshot = marketState?.snapshot;
    final displays = <HomeAssetDisplay>[
      _formatter.format(
        balance: homeState.portfolio.bitcoin,
        bitcoinUnit: preferences.bitcoinUnit,
        currencyCode: preferences.currencyCode,
        now: now,
        bitcoinMarket: marketSnapshot,
      ),
      if (homeState.portfolio.usdt case final balance?)
        _formatter.format(
          balance: balance,
          bitcoinUnit: preferences.bitcoinUnit,
          currencyCode: preferences.currencyCode,
          now: now,
          bitcoinMarket: marketSnapshot,
        ),
    ];
    return Column(
      children: [
        for (var index = 0; index < displays.length; index += 1) ...[
          AssetRow.loaded(
            display: displays[index],
            balancesVisible: preferences.balancesVisible,
            onTap: navigation.inFlight
                ? null
                : () {
                    unawaited(
                      navigation.openRoute(
                        command: () => context.pushNamed<void>(
                          RouteNames.transactionList,
                          pathParameters: <String, String>{
                            RoutePaths.assetKindParameter:
                                displays[index].kind.slug,
                          },
                        ),
                        failureTitle: 'Activity could not open',
                      ),
                    );
                  },
          ),
          if (index < displays.length - 1) SizedBox(height: context.spacing.lg),
        ],
      ],
    );
  }

  static AppFailure _failure(Object error, StackTrace stackTrace) =>
      error is AppFailureException
      ? error.failure
      : FailureMapper.from(error, stackTrace);
}

class _AssetLoadingList extends StatelessWidget {
  const _AssetLoadingList();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading asset balances',
      excludeSemantics: true,
      child: Column(
        children: [
          AssetRow.loading(kind: WalletAssetKind.bitcoin, title: 'Bitcoin'),
          SizedBox(height: context.spacing.lg),
          AssetRow.loading(kind: WalletAssetKind.usdt, title: 'USDT'),
        ],
      ),
    );
  }
}

class _AssetsFailure extends StatelessWidget {
  const _AssetsFailure({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.xl),
      child: Column(
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              failure.userMessage,
              style: context.type.statusMessage,
              textAlign: TextAlign.center,
            ),
          ),
          if (failure.retryable) ...[
            SizedBox(height: context.spacing.lg),
            CustomButton.compact(text: 'Retry', onTap: onRetry),
          ],
        ],
      ),
    );
  }
}
