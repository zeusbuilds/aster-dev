import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:remixicon/remixicon.dart';
import 'package:unicons/unicons.dart';

import '../../../../shared/shared.dart';
import '../../data/data.dart';
import '../../data/models/chart_data_item.dart';
import '../view_model/view_models.dart';
import 'candle_chart.dart';

/// Bitcoin market card backed by injected repository state.
class PriceCard extends ConsumerWidget {
  const PriceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final market = ref.watch(bitcoinMarketViewModelProvider);
    final snapshot = market.value;
    final chartData = snapshot?.history.indexed
        .map(
          (entry) =>
              ChartDataItem(entry.$1.toDouble(), entry.$2.usdCents.toDouble()),
        )
        .toList(growable: false);
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
                        _formatUsd(snapshot?.currentUsdCents),
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
            ],
          ),
        ),
        switch (market) {
          AsyncLoading<BitcoinMarketSnapshot>() => const CandleChart(
            data: null,
            isSkeleton: true,
          ),
          AsyncError<BitcoinMarketSnapshot>() => _MarketUnavailable(
            message: 'Price data unavailable',
            onRetry: () =>
                ref.read(bitcoinMarketViewModelProvider.notifier).retry(),
          ),
          AsyncData<BitcoinMarketSnapshot>() when chartData?.isEmpty ?? true =>
            _MarketUnavailable(
              message: '24-hour chart unavailable',
              onRetry: () =>
                  ref.read(bitcoinMarketViewModelProvider.notifier).retry(),
            ),
          AsyncData<BitcoinMarketSnapshot>() => CandleChart(
            data: chartData,
            isSkeleton: false,
          ),
        },
      ],
    );
  }

  static String _formatUsd(int? cents) {
    if (cents == null) return '';
    return '\$${NumberFormat('#,##0').format(cents ~/ 100)}';
  }

  static String _formatBasisPoints(int? basisPoints) {
    if (basisPoints == null) return '';
    final absolute = basisPoints.abs();
    return '${absolute ~/ 100}.${(absolute % 100) ~/ 10}%';
  }
}

class _MarketUnavailable extends StatelessWidget {
  const _MarketUnavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.all(spacing.lg),
      child: Column(
        children: [
          Text(message, style: context.type.brandMetric),
          SizedBox(height: spacing.md),
          CustomButton.compact(text: 'Retry', onTap: onRetry),
        ],
      ),
    );
  }
}
