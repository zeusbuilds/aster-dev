import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';
import 'package:unicons/unicons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../market/domain/models/models.dart';
import '../../../market/presentation/view_model/view_models.dart';
import 'candle_chart.dart';

/// Bitcoin market card backed by injected repository state.
class PriceCard extends ConsumerStatefulWidget {
  const PriceCard({this.chartHeight, super.key});

  final double? chartHeight;

  @override
  ConsumerState<PriceCard> createState() => _PriceCardState();
}

class _PriceCardState extends ConsumerState<PriceCard> {
  static final _fiatFormatter = FiatAmountFormatter();
  Timer? _expiryTimer;
  Timer? _startupWaveTimer;
  bool _showStartupWave = false;
  BitcoinMarketSnapshot? _lastChartSnapshot;

  @override
  void initState() {
    super.initState();
    ref.listenManual(bitcoinMarketViewModelProvider, (previous, next) {
      final snapshot = next.value?.snapshot;
      if (snapshot != null && snapshot.history.isNotEmpty) {
        _lastChartSnapshot = snapshot;
      }
      _scheduleExpiry(snapshot);
    }, fireImmediately: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final splashVisible = StartupRevealScope.splashVisibleOf(context);
    final waveDuration = context.motionPolicy.duration(
      context.motion.chartStartupWaveDuration,
    );
    if (waveDuration == Duration.zero || splashVisible) {
      _startupWaveTimer?.cancel();
      _startupWaveTimer = null;
      _showStartupWave = splashVisible && waveDuration > Duration.zero;
    } else if (_showStartupWave && TickerMode.valuesOf(context).enabled) {
      _startupWaveTimer ??= Timer(waveDuration, () {
        _startupWaveTimer = null;
        setState(() => _showStartupWave = false);
      });
    }
  }

  @override
  void dispose() {
    _startupWaveTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleExpiry(BitcoinMarketSnapshot? snapshot) {
    _expiryTimer?.cancel();
    final now = ref.read(utcClockProvider)().toUtc();
    final expiries = [
      if (snapshot != null) snapshot.expiresAt,
      if (_lastChartSnapshot != null) _lastChartSnapshot!.expiresAt,
    ].where((expiry) => expiry.isAfter(now)).toList()..sort();
    if (expiries.isEmpty) return;
    _expiryTimer = Timer(
      expiries.first.difference(now) + const Duration(milliseconds: 1),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleExpiry(
          ref.read(bitcoinMarketViewModelProvider).value?.snapshot,
        );
      },
    );
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
    // A partial quote response must not erase an independently validated chart.
    // Retain its own freshness deadline rather than extending it with each new
    // spot quote, and never reuse history for a different selected currency.
    final retainedChart = _lastChartSnapshot;
    final chartSnapshot = snapshot?.history.isNotEmpty == true
        ? snapshot
        : retainedChart?.quoteCurrency == selectedCurrency &&
              retainedChart?.isCurrentAt(now) == true
        ? retainedChart
        : null;
    final chartData = chartSnapshot?.history;
    final change = snapshot?.changeBasisPoints;
    final headerLoading = snapshot == null;
    final chartUnavailable = chartData?.isEmpty ?? true;
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
    final chart = CandleChart(
      data: chartData,
      isSkeleton: chartUnavailable || _showStartupWave,
      height: widget.chartHeight,
    );

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
