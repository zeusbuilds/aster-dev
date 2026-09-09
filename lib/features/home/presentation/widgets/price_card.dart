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
import '../../../settings/presentation/view_model/view_models.dart';
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
    _expiryTimer = Timer(
      (remaining.isNegative ? Duration.zero : remaining) +
          const Duration(milliseconds: 1),
      () {
        if (mounted) setState(() {});
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
    final chartData = snapshot?.history;
    final change = snapshot?.changeBasisPoints;
    final headerLoading =
        selectedQuote.isLoading || (market.isLoading && rawSnapshot == null);
    final ownsCurrentCurrency =
        rawSnapshot != null && rawSnapshot.quoteCurrency == selectedCurrency;
    final refreshFailure = ownsCurrentCurrency
        ? marketState?.refreshFailure
        : null;
    final colors = context.appColors;
    final effects = context.effects;
    final spacing = context.spacing;
    final icons = context.icons;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          liveRegion: headerLoading,
          label: _headerSemantics(
            loading: headerLoading,
            snapshot: snapshot,
            changeBasisPoints: change,
          ),
          excludeSemantics: true,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: spacing.lg,
              horizontal: spacing.screenPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  textBaseline: TextBaseline.alphabetic,
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
                    Flexible(
                      flex: 2,
                      child: Text(
                        'Bitcoin Price',
                        style: type.brandTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                _PriceChangeVisual(
                  changeBasisPoints: change,
                  loading: headerLoading,
                ),
              ],
            ),
          ),
        ),
        if (ownsCurrentCurrency && marketState!.refreshing)
          const _MarketRefreshStatus.refreshing()
        else if (refreshFailure case final failure?)
          _MarketRefreshStatus.failure(
            message: failure.userMessage,
            onRetry: failure.retryable
                ? () =>
                      ref.read(bitcoinMarketViewModelProvider.notifier).retry()
                : null,
          ),
        switch ((selectedQuote, market)) {
          (AsyncLoading<MarketQuoteCurrency>(), _) => const CandleChart(
            data: null,
            isSkeleton: true,
          ),
          (
            AsyncError<MarketQuoteCurrency>(:final error, :final stackTrace),
            _,
          ) =>
            _MarketUnavailable(
              message: _failure(error, stackTrace).userMessage,
              onRetry: _failure(error, stackTrace).retryable
                  ? () => ref.read(settingsViewModelProvider.notifier).retry()
                  : null,
            ),
          (_, AsyncLoading<BitcoinMarketState>()) => const CandleChart(
            data: null,
            isSkeleton: true,
          ),
          (
            _,
            AsyncError<BitcoinMarketState>(:final error, :final stackTrace),
          ) =>
            _MarketUnavailable(
              message: _failure(error, stackTrace).userMessage,
              onRetry: _failure(error, stackTrace).retryable
                  ? () => ref
                        .read(bitcoinMarketViewModelProvider.notifier)
                        .retry()
                  : null,
            ),
          (_, AsyncData<BitcoinMarketState>()) when snapshot == null =>
            _MarketUnavailable(
              message:
                  marketState?.refreshFailure?.userMessage ??
                  (rawSnapshot?.quoteCurrency == selectedCurrency
                      ? 'Market quote expired'
                      : 'Market quote unavailable'),
              onRetry: marketState?.refreshFailure?.retryable == false
                  ? null
                  : () => ref
                        .read(bitcoinMarketViewModelProvider.notifier)
                        .retry(),
            ),
          (_, AsyncData<BitcoinMarketState>())
              when chartData?.isEmpty ?? true =>
            _MarketUnavailable(
              message: '24-hour chart unavailable',
              onRetry: () =>
                  ref.read(bitcoinMarketViewModelProvider.notifier).retry(),
            ),
          (_, AsyncData<BitcoinMarketState>()) => CandleChart(
            data: chartData,
            isSkeleton: false,
          ),
        },
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
    if (loading) return 'Bitcoin price loading.';
    if (snapshot == null) {
      return 'Bitcoin price unavailable.';
    }
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
}

final class _MarketRefreshStatus extends StatelessWidget {
  const _MarketRefreshStatus.refreshing()
    : message = 'Refreshing market data',
      refreshing = true,
      onRetry = null;

  const _MarketRefreshStatus.failure({
    required this.message,
    required this.onRetry,
  }) : refreshing = false;

  final String message;
  final bool refreshing;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.spacing.lg,
        context.spacing.xs,
        context.spacing.lg,
        context.spacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              liveRegion: true,
              label: message,
              excludeSemantics: true,
              child: Text(
                message,
                style: context.type.brandMetric,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (refreshing) ...[
            SizedBox(width: context.spacing.sm),
            const GridLoader(
              colorStyle: GridLoaderColorStyle.white,
              style: GridLoaderStyle.plusLoop,
            ),
          ] else if (onRetry case final retry?) ...[
            SizedBox(width: context.spacing.sm),
            AsterIconButton(
              icon: RemixIcons.refresh_line,
              tooltip: 'Retry market refresh',
              color: context.appColors.onBrandArt,
              hapticIntent: null,
              onPressed: retry,
            ),
          ],
        ],
      ),
    );
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

class _MarketUnavailable extends StatelessWidget {
  const _MarketUnavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: context.metrics.chartHeight),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(message, style: context.type.brandMetric),
            ),
            if (onRetry case final retry?) ...[
              SizedBox(height: spacing.md),
              CustomButton.compact(
                text: 'Retry',
                variant: ButtonVariant.translucent,
                onTap: retry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
