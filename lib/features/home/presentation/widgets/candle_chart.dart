import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../data/models/chart_data_item.dart';

const _kCandleCount = 24;
const _kMinBodyHeight = 2.0;

const _kBaseHeight = 0.8;
const _kHeightAmplitude = 0.2;
const _kBaseOpacity = 0.5;
const _kOpacityAmplitude = 0.3;
const _kTargetOpacity = 0.8;

/// Widget displaying a candle chart of price data.
///
/// Shows 24 candles for the last 24 hours as rounded rectangles with
/// smooth loading animation and transition effects.
class CandleChart extends StatefulWidget {
  const CandleChart({super.key, required this.data, required this.isSkeleton});

  final List<ChartDataItem>? data;
  final bool isSkeleton;

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart>
    with TickerProviderStateMixin {
  late final AnimationController _loadingController;
  late final AnimationController _transitionController;

  bool _shouldShowLoading = true;
  bool _dataReady = false;
  bool _transitionTriggered = false;
  bool _isTransitioning = false;
  double? _loadingAnimationProgress;

  List<CandleData>? _candles;
  double? _minPrice;
  double? _maxPrice;
  double? _priceRange;
  Timer? _transitionDelayTimer;
  Timer? _transitionPauseTimer;

  @override
  void initState() {
    super.initState();
    const motion = AsterMotion();
    _loadingController = AnimationController(
      vsync: this,
      duration: motion.chartLoadingCycleDuration,
    );
    unawaited(_loadingController.repeat());

    _transitionController = AnimationController(
      vsync: this,
      duration: motion.chartTransitionDuration,
    );

    _loadingController.addListener(_checkAnimationProgress);
    _transitionController.addListener(() {
      if (_transitionController.isCompleted) {
        setState(() {
          _isTransitioning = false;
          _shouldShowLoading = false;
        });
      }
    });
    if (!widget.isSkeleton) {
      _prepareChartData();
      _dataReady = _candles != null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = context.motion;
    _loadingController.duration = motion.chartLoadingCycleDuration;
    _transitionController.duration = motion.chartTransitionDuration;
  }

  void _checkAnimationProgress() {
    if (!_dataReady || _transitionTriggered) return;

    final motion = context.motion;
    final progress = _loadingController.value;
    final currentIndex = (progress * _kCandleCount).floor() % _kCandleCount;

    if (currentIndex == _kCandleCount - 1) {
      _transitionTriggered = true;

      final remainingProgress = 1.0 - progress;
      final remainingTime =
          remainingProgress * motion.chartLoadingCycleDuration.inMilliseconds;

      _transitionDelayTimer?.cancel();
      _transitionDelayTimer = Timer(
        Duration(
          milliseconds:
              remainingTime.toInt() +
              motion.chartTransitionSettleDelay.inMilliseconds,
        ),
        () {
          if (mounted && _dataReady && _candles != null) {
            _loadingController.stop();
            _loadingAnimationProgress = _loadingController.value;

            _transitionPauseTimer?.cancel();
            _transitionPauseTimer = Timer(
              motion.chartTransitionPauseDuration,
              () {
                if (mounted && _dataReady && _candles != null) {
                  setState(() {
                    _isTransitioning = true;
                  });
                  unawaited(_transitionController.forward());
                }
              },
            );
          }
        },
      );
    }
  }

  @override
  void didUpdateWidget(CandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.isSkeleton &&
        (oldWidget.isSkeleton || !listEquals(oldWidget.data, widget.data))) {
      _cancelPendingTransition();
      _prepareChartData();
      _dataReady = _candles != null;
      _transitionTriggered = false;
      _shouldShowLoading = true;
      _isTransitioning = false;
      _loadingAnimationProgress = null;
      _transitionController.reset();
      if (!_loadingController.isAnimating) {
        unawaited(_loadingController.repeat());
      }
    } else if (widget.isSkeleton) {
      _cancelPendingTransition();
      _dataReady = false;
      _transitionTriggered = false;
      _shouldShowLoading = true;
      _isTransitioning = false;
      _loadingAnimationProgress = null;
      _transitionController.reset();
      _candles = null;
      _minPrice = null;
      _maxPrice = null;
      _priceRange = null;
      if (!_loadingController.isAnimating) {
        unawaited(_loadingController.repeat());
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

    final prices = last24Items.map((e) => e.y).toList();
    _minPrice = prices.min;
    _maxPrice = prices.max;
    _priceRange = _maxPrice! - _minPrice!;

    _candles = _generatePriceBars(last24Items);
  }

  @override
  void dispose() {
    _cancelPendingTransition();
    _loadingController.removeListener(_checkAnimationProgress);
    _loadingController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  void _cancelPendingTransition() {
    _transitionDelayTimer?.cancel();
    _transitionDelayTimer = null;
    _transitionPauseTimer?.cancel();
    _transitionPauseTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final metrics = context.metrics;
    final showLoading =
        widget.isSkeleton || (_shouldShowLoading && !_isTransitioning);

    return SizedBox(
      height: metrics.chartHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final radius = context.radii;
          final candleSpacing = spacing.xxs;
          final borderRadius = radius.pill;

          final totalSpacing = candleSpacing * (_kCandleCount - 1);
          final calculatedCandleWidth =
              (constraints.maxWidth - totalSpacing) / (_kCandleCount + 1);
          final sidePadding = calculatedCandleWidth / 2;

          if (showLoading) {
            return _buildLoadingState(
              context,
              constraints,
              calculatedCandleWidth,
              sidePadding,
              candleSpacing,
              borderRadius,
            );
          }

          if (_isTransitioning && _candles != null) {
            return _buildTransitionState(
              context,
              constraints,
              calculatedCandleWidth,
              sidePadding,
              candleSpacing,
              borderRadius,
            );
          }

          if (_candles != null) {
            return _buildChartState(
              context,
              constraints,
              calculatedCandleWidth,
              sidePadding,
              candleSpacing,
              borderRadius,
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
    double borderRadius,
  ) {
    return AnimatedBuilder(
      animation: _loadingController,
      builder: (context, _) {
        final progress = _loadingController.value;
        final colors = context.appColors;

        return Stack(
          children: List.generate(_kCandleCount, (index) {
            final wavePosition = index - (progress * _kCandleCount);
            final sinValue =
                (math.sin(wavePosition * 2 * math.pi / _kCandleCount) + 1) / 2;

            final heightFactor = _kBaseHeight + (_kHeightAmplitude * sinValue);
            final candleHeight = constraints.maxHeight * heightFactor;

            final opacityFactor =
                _kBaseOpacity + (_kOpacityAmplitude * sinValue);
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
              borderRadius: borderRadius,
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
    double borderRadius,
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

            final actualTargetHeight = targetBodyHeight < _kMinBodyHeight
                ? _kMinBodyHeight
                : targetBodyHeight;
            final actualTargetTop = targetBodyHeight < _kMinBodyHeight
                ? (targetBodyTop + targetBodyBottom) / 2 - _kMinBodyHeight / 2
                : targetBodyTop;

            final targetCenterY = actualTargetTop + actualTargetHeight / 2;

            final loadingProgress = _loadingAnimationProgress ?? 0.0;
            final wavePosition = index - (loadingProgress * _kCandleCount);
            final sinValue =
                (math.sin(wavePosition * 2 * math.pi / _kCandleCount) + 1) / 2;

            final startHeightFactor =
                _kBaseHeight + (_kHeightAmplitude * sinValue);
            final startHeight = constraints.maxHeight * startHeightFactor;
            final startOpacity =
                _kBaseOpacity + (_kOpacityAmplitude * sinValue);

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
              alpha: _kTargetOpacity,
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
              borderRadius: borderRadius,
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
    double borderRadius,
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

        final actualBodyHeight = bodyHeight < _kMinBodyHeight
            ? _kMinBodyHeight
            : bodyHeight;
        final actualBodyTop = bodyHeight < _kMinBodyHeight
            ? (bodyTop + bodyBottom) / 2 - _kMinBodyHeight / 2
            : bodyTop;

        final centerY = actualBodyTop + actualBodyHeight / 2;
        final x = sidePadding + index * (candleWidth + candleSpacing);

        return _CandleWidget(
          x: x,
          width: candleWidth,
          height: actualBodyHeight,
          centerY: centerY,
          color: context.appColors.onBrandArt.withValues(
            alpha: _kTargetOpacity,
          ),
          borderRadius: borderRadius,
        );
      }),
    );
  }

  double _priceToY(double price, double height) {
    if (_priceRange == null || _priceRange == 0) return height / 2;
    final normalized = (price - _minPrice!) / _priceRange!;
    return height - (normalized * height);
  }

  List<CandleData> _generatePriceBars(List<ChartDataItem> items) {
    final bars = <CandleData>[];

    for (int i = 0; i < items.length; i++) {
      final price = items[i].y;
      final prevPrice = i > 0 ? items[i - 1].y : price;

      bars.add(CandleData(open: prevPrice, close: price));
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
    required this.borderRadius,
    required this.x,
  });

  final double width;
  final double height;
  final double centerY;
  final Color color;
  final double borderRadius;
  final double x;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x,
      top: centerY - height / 2,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class CandleData {
  const CandleData({required this.open, required this.close});

  final double open;
  final double close;
}
