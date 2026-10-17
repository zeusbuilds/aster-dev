import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';
import 'package:unicons/unicons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../market/domain/models/models.dart';
import '../../../market/presentation/models/models.dart';
import '../../../market/presentation/view_model/view_models.dart';
import 'candle_chart.dart';

/// Bitcoin market card backed by injected repository state.
class PriceCard extends ConsumerStatefulWidget {
  const PriceCard({super.key});

  @override
  ConsumerState<PriceCard> createState() => _PriceCardState();
}

class _PriceCardState extends ConsumerState<PriceCard> {
  static final _fiatFormatter = FiatAmountFormatter();
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      bitcoinMarketViewModelProvider,
      (previous, next) => _scheduleExpiry(next.value?.snapshot),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleExpiry(BitcoinMarketSnapshot? snapshot) {
    _expiryTimer?.cancel();
    if (snapshot == null) return;
    final now = ref.read(utcClockProvider)().toUtc();
    final remaining = snapshot.expiresAt.difference(now);
    if (remaining <= Duration.zero) return;
    _expiryTimer = Timer(remaining + const Duration(milliseconds: 1), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final market = ref.watch(bitcoinMarketViewModelProvider);
    final selectedQuote = ref.watch(selectedMarketQuoteCurrencyProvider);
    final selectedCurrency = selectedQuote.value;
    final now = ref.watch(utcClockProvider)().toUtc();
    final marketState = market.value;
    final rawSnapshot = marketState?.snapshot;
    final snapshot =
        rawSnapshot?.quoteCurrency == selectedCurrency &&
            rawSnapshot?.isCurrentAt(now) == true
        ? rawSnapshot
        : null;
    final chartData = snapshot?.history;
    final change = snapshot?.changeBasisPoints;
    final ownsCurrentCurrency =
        rawSnapshot != null && rawSnapshot.quoteCurrency == selectedCurrency;
    final visibleFailure = _visibleFailure(
      selectedQuote: selectedQuote,
      market: market,
      ownsCurrentCurrency: ownsCurrentCurrency,
    );
    final headerLoading = snapshot == null;
    final chartUnavailable = chartData?.isEmpty ?? true;
    final chartOffline =
        chartUnavailable && visibleFailure?.kind == AppFailureKind.connectivity;
    final colors = context.appColors;
    final effects = context.effects;
    final spacing = context.spacing;
    final icons = context.icons;
    final type = context.type;
    final headlineLineHeight = unwrappedSpanSize(
      context,
      TextSpan(
        style: type.brandAmount,
        children: NumericTextSpans.build(context, r'$0', type.brandAmount),
      ),
    ).height;
    final Widget chart = switch ((chartUnavailable, chartOffline)) {
      (true, true) => _OfflineMarketChart(
        onRetry: () => unawaited(
          ref.read(bitcoinMarketViewModelProvider.notifier).retry(),
        ),
      ),
      (true, false) => const CandleChart(data: null, isSkeleton: true),
      (false, _) => CandleChart(data: chartData, isSkeleton: false),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Semantics(
            container: true,
            liveRegion: headerLoading,
            label: _headerSemantics(
              loading: headerLoading,
              snapshot: snapshot,
              changeBasisPoints: change,
            ),
            excludeSemantics: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.lg,
                spacing.lg,
                spacing.screenPadding,
                spacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: headlineLineHeight),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: context.colorScheme.surface,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  UniconsLine.bitcoin,
                                  size: icons.md,
                                  color: colors.bitcoin.withValues(
                                    alpha: effects.bitcoinIconOpacity,
                                  ),
                                ),
                              ),
                              SizedBox(width: spacing.xs),
                              Expanded(
                                child: Text(
                                  'Bitcoin Price',
                                  style: type.brandTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: spacing.md),
                        Expanded(
                          flex: 3,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: AppSkeletonizer(
                              enabled: headerLoading,
                              baseColor: colors.onBrandArt.withValues(
                                alpha: effects.chartLoadingBaseOpacity,
                              ),
                              highlightColor: colors.onBrandArt.withValues(
                                alpha: effects.chartContentOpacity,
                              ),
                              child: NumericText(
                                headerLoading
                                    ? '000,000.00'
                                    : _formatPrice(snapshot, headline: true),
                                style: type.brandAmount,
                                textAlign: TextAlign.end,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _PriceChangeVisual(
                    changeBasisPoints: change,
                    loading: headerLoading,
                  ),
                ],
              ),
            ),
          ),
        ),
        chart,
      ],
    );
  }

  static String _formatPrice(
    BitcoinMarketSnapshot? snapshot, {
    bool headline = false,
  }) {
    if (snapshot == null) return '';
    return _fiatFormatter.format(
      minorUnits: snapshot.currentBitcoinPrice.minorUnits,
      symbol: snapshot.quoteCurrency.symbol,
      code: snapshot.quoteCurrency.code,
      minorUnitDigits: snapshot.quoteCurrency.minorUnitDigits,
      includeCurrencyCode: !headline,
      wholeUnitsOnly: headline,
    );
  }

  static String _formatBasisPoints(int? basisPoints) {
    if (basisPoints == null) return '';
    final absolute = basisPoints.abs();
    final wholePercent = absolute ~/ 100;
    final hundredths = absolute % 100;
    final fraction = switch (hundredths) {
      0 => '0',
      _ when hundredths % 10 == 0 => '${hundredths ~/ 10}',
      _ => hundredths.toString().padLeft(2, '0'),
    };
    return '$wholePercent.$fraction%';
  }

  static String _headerSemantics({
    required bool loading,
    required BitcoinMarketSnapshot? snapshot,
    required int? changeBasisPoints,
  }) {
    if (loading || snapshot == null) return 'Bitcoin price loading.';
    final change = switch (changeBasisPoints) {
      null => '24-hour change unavailable',
      0 =>
        'unchanged at ${_formatBasisPoints(changeBasisPoints)} over 24 hours',
      > 0 => 'up ${_formatBasisPoints(changeBasisPoints)} over 24 hours',
      _ => 'down ${_formatBasisPoints(changeBasisPoints)} over 24 hours',
    };
    return 'Bitcoin price ${_formatPrice(snapshot)}. $change.';
  }

  static AppFailure _failure(Object error, StackTrace stackTrace) =>
      error is AppFailureException
      ? error.failure
      : FailureMapper.from(error, stackTrace);

  static AppFailure? _visibleFailure({
    required AsyncValue<MarketQuoteCurrency> selectedQuote,
    required AsyncValue<BitcoinMarketState> market,
    required bool ownsCurrentCurrency,
  }) {
    if (selectedQuote case AsyncError(:final error, :final stackTrace)) {
      return _failure(error, stackTrace);
    }
    if (market case AsyncError(:final error, :final stackTrace)) {
      return _failure(error, stackTrace);
    }
    final state = market.value;
    if (state == null) return null;
    return state.snapshot == null || ownsCurrentCurrency
        ? state.refreshFailure
        : null;
  }
}

class _PriceChangeVisual extends StatelessWidget {
  const _PriceChangeVisual({
    required this.changeBasisPoints,
    required this.loading,
  });

  final int? changeBasisPoints;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final change = changeBasisPoints;
    final colors = context.appColors;
    final effects = context.effects;
    final neutralColor = context.type.brandMetric.color ?? colors.onBrandArt;
    final changeColor = change == null || change == 0
        ? neutralColor
        : change > 0
        ? colors.chartPositive
        : colors.chartNegative;
    final changeIcon = change == null || change == 0
        ? RemixIcons.subtract_line
        : change > 0
        ? RemixIcons.arrow_up_line
        : RemixIcons.arrow_down_line;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (change != null || loading)
          Icon(changeIcon, size: context.icons.xxs, color: changeColor)
        else
          SizedBox(height: context.spacing.md),
        SizedBox(width: context.spacing.xxs),
        NumericText(
          loading ? '0.0%' : _PriceCardState._formatBasisPoints(change),
          style: context.type.brandMetric.copyWith(color: changeColor),
        ),
      ],
    );
    return AppSkeletonizer(
      enabled: loading,
      baseColor: colors.onBrandArt.withValues(
        alpha: effects.chartLoadingBaseOpacity,
      ),
      highlightColor: colors.onBrandArt.withValues(
        alpha: effects.chartContentOpacity,
      ),
      child: content,
    );
  }
}

class _OfflineMarketChart extends StatelessWidget {
  const _OfflineMarketChart({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.onBrandArt.withValues(
      alpha: context.effects.brandContentMutedOpacity,
    );
    return Semantics(
      button: true,
      liveRegion: true,
      label: "You're offline. Tap to try again.",
      onTap: onRetry,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: context.metrics.chartHeight),
          child: TextButton(
            onPressed: onRetry,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("You're offline", style: context.type.brandTitle),
                SizedBox(height: context.spacing.xs),
                Text(
                  'Tap to try again',
                  style: context.type.brandMetric.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
