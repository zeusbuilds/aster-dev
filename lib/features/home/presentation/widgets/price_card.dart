import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';
import 'package:unicons/unicons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../market/domain/models/models.dart';
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
      (previous, next) => _scheduleExpiry(next.value),
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
    final rawSnapshot = market.value;
    final snapshot =
        rawSnapshot?.quoteCurrency == selectedCurrency &&
            rawSnapshot?.isCurrentAt(now) == true
        ? rawSnapshot
        : null;
    final chartData = snapshot?.history;
    final change = snapshot?.changeBasisPoints;
    final colors = context.appColors;
    final effects = context.effects;
    final spacing = context.spacing;
    final icons = context.icons;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: spacing.lg,
            horizontal: spacing.lg,
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
                    flex: 3,
                    child: Text(
                      'Bitcoin Price',
                      style: type.brandTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: spacing.md),
                  Expanded(
                    flex: 4,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: NumericText(
                        _formatPrice(snapshot),
                        style: type.brandAmount,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (change != null)
                    Icon(
                      change >= 0
                          ? RemixIcons.arrow_up_line
                          : RemixIcons.arrow_down_line,
                      size: icons.xxs,
                      color: change >= 0 ? colors.success : colors.danger,
                    )
                  else
                    SizedBox(height: spacing.md),
                  SizedBox(width: spacing.xxs),
                  Text(
                    _formatBasisPoints(change),
                    style: type.brandMetric
                        .copyWith(
                          color: (change ?? 0) >= 0
                              ? colors.success
                              : colors.danger,
                        )
                        .toNumeric(context),
                  ),
                ],
              ),
              Text(
                'Powered by CoinGecko',
                style: type.brandMetric.copyWith(
                  color: colors.onBrandArt.withValues(
                    alpha: effects.chartContentOpacity,
                  ),
                ),
              ),
            ],
          ),
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
          (_, AsyncLoading<BitcoinMarketSnapshot>()) => const CandleChart(
            data: null,
            isSkeleton: true,
          ),
          (
            _,
            AsyncError<BitcoinMarketSnapshot>(:final error, :final stackTrace),
          ) =>
            _MarketUnavailable(
              message: _failure(error, stackTrace).userMessage,
              onRetry: _failure(error, stackTrace).retryable
                  ? () => ref
                        .read(bitcoinMarketViewModelProvider.notifier)
                        .retry()
                  : null,
            ),
          (_, AsyncData<BitcoinMarketSnapshot>()) when snapshot == null =>
            _MarketUnavailable(
              message: rawSnapshot?.quoteCurrency == selectedCurrency
                  ? 'Market quote expired'
                  : 'Market quote unavailable',
              onRetry: () =>
                  ref.read(bitcoinMarketViewModelProvider.notifier).retry(),
            ),
          (_, AsyncData<BitcoinMarketSnapshot>())
              when chartData?.isEmpty ?? true =>
            _MarketUnavailable(
              message: '24-hour chart unavailable',
              onRetry: () =>
                  ref.read(bitcoinMarketViewModelProvider.notifier).retry(),
            ),
          (_, AsyncData<BitcoinMarketSnapshot>()) => CandleChart(
            data: chartData,
            isSkeleton: false,
          ),
        },
      ],
    );
  }

  static String _formatPrice(BitcoinMarketSnapshot? snapshot) {
    if (snapshot == null) return '';
    return _fiatFormatter.format(
      minorUnits: snapshot.currentBitcoinPrice.minorUnits,
      symbol: snapshot.quoteCurrency.symbol,
      code: snapshot.quoteCurrency.code,
      minorUnitDigits: snapshot.quoteCurrency.minorUnitDigits,
    );
  }

  static String _formatBasisPoints(int? basisPoints) {
    if (basisPoints == null) return '';
    final absolute = basisPoints.abs();
    return '${absolute ~/ 100}.${(absolute % 100) ~/ 10}%';
  }

  static AppFailure _failure(Object error, StackTrace stackTrace) =>
      error is AppFailureException
      ? error.failure
      : FailureMapper.from(error, stackTrace);
}

class _MarketUnavailable extends StatelessWidget {
  const _MarketUnavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.all(spacing.lg),
      child: Column(
        children: [
          Text(message, style: context.type.brandMetric),
          if (onRetry case final retry?) ...[
            SizedBox(height: spacing.md),
            CustomButton.compact(text: 'Retry', onTap: retry),
          ],
        ],
      ),
    );
  }
}
