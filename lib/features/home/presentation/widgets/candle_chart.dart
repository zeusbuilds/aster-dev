import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../../market/domain/models/models.dart';

const _kCandleCount = 24;

/// Widget displaying a candle chart of price data.
///
/// Shows 24 candles for the last 24 hours as rounded rectangles with
/// smooth loading animation and transition effects.
class CandleChart extends StatefulWidget {
  const CandleChart({super.key, required this.data, required this.isSkeleton});

  final List<BitcoinPricePoint>? data;
  final bool isSkeleton;

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart>
    with TickerProviderStateMixin {
  late final AnimationController _loadingController;
  late final AnimationController _transitionController;
  double _loadingAnimationProgress = 0;

  List<_CandleData>? _candles;
  double? _minPrice;
  double? _maxPrice;
  double? _priceRange;

  @override
  void initState() {
    super.initState();
    const motion = AsterMotion();
    _loadingController = AnimationController(
      vsync: this,
      duration: motion.chartLoadingCycleDuration,
    );
    _transitionController = AnimationController(
      vsync: this,
      duration: motion.chartTransitionDuration,
    );
    if (!widget.isSkeleton) {
      _prepareChartData();
      _transitionController.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = context.motion;
    final loadingDuration = motion.chartLoadingCycleDuration;
    final transitionDuration = context.motionPolicy.duration(
      motion.chartTransitionDuration,
    );
    final loadingDurationChanged =
        _loadingController.duration != loadingDuration;
    _loadingController.duration = loadingDuration;
    _transitionController.duration = transitionDuration;
    if (!_loadingController.isAnimating) {
      _loadingAnimationProgress = motion.settledLoopProgress;
    }

    if (widget.isSkeleton && !context.motionPolicy.reduceMotion) {
      if (loadingDurationChanged || !_loadingController.isAnimating) {
        _loadingController.stop();
        unawaited(_loadingController.repeat(period: loadingDuration));
      }
    } else {
      _loadingController.stop();
      if (widget.isSkeleton) {
        _loadingController.value = motion.settledLoopProgress;
      }
      if (!widget.isSkeleton && context.motionPolicy.reduceMotion) {
        _transitionController.value = 1;
      }
    }
  }

  @override
  void didUpdateWidget(CandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.isSkeleton &&
        (oldWidget.isSkeleton || !listEquals(oldWidget.data, widget.data))) {
      _loadingAnimationProgress = _loadingController.value;
      _loadingController.stop();
      _prepareChartData();
      if (_candles == null || context.motionPolicy.reduceMotion) {
        _transitionController.value = 1;
      } else {
        unawaited(_transitionController.forward(from: 0));
      }
    } else if (widget.isSkeleton) {
      _transitionController.reset();
      _candles = null;
      _minPrice = null;
      _maxPrice = null;
      _priceRange = null;
      if (context.motionPolicy.reduceMotion) {
        _loadingController.stop();
        _loadingController.value = context.motion.settledLoopProgress;
      } else if (!_loadingController.isAnimating) {
        unawaited(
          _loadingController.repeat(
            period: context.motion.chartLoadingCycleDuration,
          ),
        );
      }
    }
  }

  void _prepareChartData() {
    final items = widget.data ?? [];
    if (items.isEmpty) {
      _candles = null;
      _minPrice = null;
      _maxPrice = null;
      _priceRange = null;
      return;
    }

    final last24Items = items.length > _kCandleCount
        ? items.sublist(items.length - _kCandleCount)
        : items;

    final prices = last24Items
        .map((point) => point.fiatMinorUnits.toDouble())
        .toList(growable: false);
    _minPrice = prices.min;
    _maxPrice = prices.max;
    _priceRange = _maxPrice! - _minPrice!;

    _candles = _generatePriceBars(last24Items);
  }

  @override
  void dispose() {
    _loadingController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final metrics = context.metrics;

    return SizedBox(
      height: metrics.chartHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final candleSpacing = spacing.xxs;

          final totalSpacing = candleSpacing * (_kCandleCount - 1);
          final calculatedCandleWidth =
              (constraints.maxWidth - totalSpacing) / (_kCandleCount + 1);
          final sidePadding = calculatedCandleWidth / 2;

          if (widget.isSkeleton) {
            return _buildLoadingState(
              context,
              constraints,
              calculatedCandleWidth,
              sidePadding,
              candleSpacing,
            );
          }

          if (_transitionController.value < 1 && _candles != null) {
            return _buildTransitionState(
              context,
              constraints,
              calculatedCandleWidth,
              sidePadding,
              candleSpacing,
            );
          }

          if (_candles != null) {
            return _buildChartState(
              context,
              constraints,
              calculatedCandleWidth,
              sidePadding,
              candleSpacing,
            );
          }

          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildLoadingState(
    BuildContext context,
    BoxConstraints constraints,
    double candleWidth,
    double sidePadding,
    double candleSpacing,
  ) {
    return AnimatedBuilder(
      animation: _loadingController,
      builder: (context, _) {
        final progress = _loadingController.value;
        final colors = context.appColors;
        final effects = context.effects;
        final metrics = context.metrics;

        return Stack(
          children: List.generate(_kCandleCount, (index) {
            final wavePosition = index - (progress * _kCandleCount);
            final sinValue =
                (math.sin(wavePosition * 2 * math.pi / _kCandleCount) + 1) / 2;

            final heightFactor =
                metrics.chartLoadingBaseHeightFactor +
                (metrics.chartLoadingHeightAmplitude * sinValue);
            final candleHeight = constraints.maxHeight * heightFactor;

            final opacityFactor =
                effects.chartLoadingBaseOpacity +
                (effects.chartLoadingOpacityAmplitude * sinValue);
            final candleColor = colors.onBrandArt.withValues(
              alpha: opacityFactor,
            );

            final x = sidePadding + index * (candleWidth + candleSpacing);

            return _CandleWidget(
              x: x,
              width: candleWidth,
              height: candleHeight,
              centerY: constraints.maxHeight / 2,
              color: candleColor,
            );
          }),
        );
      },
    );
  }

  Widget _buildTransitionState(
    BuildContext context,
    BoxConstraints constraints,
    double candleWidth,
    double sidePadding,
    double candleSpacing,
  ) {
    if (_candles == null ||
        _minPrice == null ||
        _maxPrice == null ||
        _priceRange == null) {
      return const SizedBox();
    }

    return AnimatedBuilder(
      animation: _transitionController,
      builder: (context, _) {
        final colors = context.appColors;
        final effects = context.effects;
        final metrics = context.metrics;
        final animationValue = context.motion.chartTransitionCurve.transform(
          _transitionController.value,
        );

        return Stack(
          children: List.generate(_kCandleCount, (index) {
            if (index >= _candles!.length) {
              return const SizedBox.shrink();
            }

            final candle = _candles![index];
            final openY = _priceToY(candle.open, constraints.maxHeight);
            final closeY = _priceToY(candle.close, constraints.maxHeight);

            final targetBodyTop = openY < closeY ? openY : closeY;
            final targetBodyBottom = openY < closeY ? closeY : openY;
            final targetBodyHeight = targetBodyBottom - targetBodyTop;

            final minimumBodyHeight = metrics.chartMinimumBodyHeight;
            final actualTargetHeight = targetBodyHeight < minimumBodyHeight
                ? minimumBodyHeight
                : targetBodyHeight;
            final actualTargetTop = targetBodyHeight < minimumBodyHeight
                ? (targetBodyTop + targetBodyBottom) / 2 - minimumBodyHeight / 2
                : targetBodyTop;

            final targetCenterY = actualTargetTop + actualTargetHeight / 2;

            final loadingProgress = _loadingAnimationProgress;
            final wavePosition = index - (loadingProgress * _kCandleCount);
            final sinValue =
                (math.sin(wavePosition * 2 * math.pi / _kCandleCount) + 1) / 2;

            final startHeightFactor =
                metrics.chartLoadingBaseHeightFactor +
                (metrics.chartLoadingHeightAmplitude * sinValue);
            final startHeight = constraints.maxHeight * startHeightFactor;
            final startOpacity =
                effects.chartLoadingBaseOpacity +
                (effects.chartLoadingOpacityAmplitude * sinValue);

            final currentHeight =
                startHeight +
                (actualTargetHeight - startHeight) * animationValue;

            final startCenterY = constraints.maxHeight / 2;
            final currentCenterY =
                startCenterY + (targetCenterY - startCenterY) * animationValue;

            final startColor = colors.onBrandArt.withValues(
              alpha: startOpacity,
            );
            final targetColor = colors.onBrandArt.withValues(
              alpha: effects.chartContentOpacity,
            );
            final currentColor = Color.lerp(
              startColor,
              targetColor,
              animationValue,
            )!;

            final x = sidePadding + index * (candleWidth + candleSpacing);

            return _CandleWidget(
              x: x,
              width: candleWidth,
              height: currentHeight,
              centerY: currentCenterY,
              color: currentColor,
            );
          }),
        );
      },
    );
  }

  Widget _buildChartState(
    BuildContext context,
    BoxConstraints constraints,
    double candleWidth,
    double sidePadding,
    double candleSpacing,
  ) {
    if (_candles == null ||
        _minPrice == null ||
        _maxPrice == null ||
        _priceRange == null) {
      return const SizedBox();
    }

    return Stack(
      children: List.generate(_kCandleCount, (index) {
        if (index >= _candles!.length) {
          return const SizedBox.shrink();
        }

        final candle = _candles![index];
        final openY = _priceToY(candle.open, constraints.maxHeight);
        final closeY = _priceToY(candle.close, constraints.maxHeight);

        final bodyTop = openY < closeY ? openY : closeY;
        final bodyBottom = openY < closeY ? closeY : openY;
        final bodyHeight = bodyBottom - bodyTop;

        final minimumBodyHeight = context.metrics.chartMinimumBodyHeight;
        final actualBodyHeight = bodyHeight < minimumBodyHeight
            ? minimumBodyHeight
            : bodyHeight;
        final actualBodyTop = bodyHeight < minimumBodyHeight
            ? (bodyTop + bodyBottom) / 2 - minimumBodyHeight / 2
            : bodyTop;

        final centerY = actualBodyTop + actualBodyHeight / 2;
        final x = sidePadding + index * (candleWidth + candleSpacing);

        return _CandleWidget(
          x: x,
          width: candleWidth,
          height: actualBodyHeight,
          centerY: centerY,
          color: context.appColors.onBrandArt.withValues(
            alpha: context.effects.chartContentOpacity,
          ),
        );
      }),
    );
  }

  double _priceToY(double price, double height) {
    if (_priceRange == null || _priceRange == 0) return height / 2;
    final normalized = (price - _minPrice!) / _priceRange!;
    return height - (normalized * height);
  }

  List<_CandleData> _generatePriceBars(List<BitcoinPricePoint> items) {
    final bars = <_CandleData>[];

    for (int i = 0; i < items.length; i++) {
      final price = items[i].fiatMinorUnits.toDouble();
      final prevPrice = i > 0 ? items[i - 1].fiatMinorUnits.toDouble() : price;

      bars.add(_CandleData(open: prevPrice, close: price));
    }

    return bars;
  }
}

class _CandleWidget extends StatelessWidget {
  const _CandleWidget({
    required this.width,
    required this.height,
    required this.centerY,
    required this.color,
    required this.x,
  });

  final double width;
  final double height;
  final double centerY;
  final Color color;
  final double x;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x,
      top: centerY - height / 2,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: color,
            shape: const StadiumBorder(),
          ),
        ),
      ),
    );
  }
}

class _CandleData {
  const _CandleData({required this.open, required this.close});

  final double open;
  final double close;
}
