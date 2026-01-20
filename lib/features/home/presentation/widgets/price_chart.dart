import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:aster/shared/shared.dart';

const _kSkeletonPrice = 100000.0;
const _kSkeletonChartItemsCount = 31;
const _kPaddingRatio = 0.995;

/// Widget displaying a line chart of Bitcoin price data
///
/// Shows animated chart with blinking dot indicator at the latest price point
class PriceChart extends StatefulWidget {
  const PriceChart({super.key, required this.data, required this.isSkeleton});

  /// Chart data points (x, y coordinates)
  final List<ChartDataItem>? data;

  /// Whether to show skeleton/loading state
  final bool isSkeleton;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = colors.text5;

    final isNoHistory = widget.data == null || widget.data!.isEmpty;
    final items =
        widget.data ??
        List.generate(
          _kSkeletonChartItemsCount,
          (index) => ChartDataItem(index.toDouble(), _kSkeletonPrice),
        );
    final maxYVal = items.map((e) => e.y).max;

    // Create a smooth gradient that blends with the background
    final gradientColors = [
      // primaryColor.withValues(alpha: 0.2),
      Colors.transparent,
      Colors.transparent,
    ];

    return SizedBox(
      height: 100, // Using fixed height for chart
      child: AnimatedBuilder(
        animation: _blinkController,
        builder: (context, _) {
          // 0.0 → 1.0 pulse value
          final t = _blinkController.value;

          // Middle dot is static (no animation)
          final dotRadius = 4.0;
          final dotOpacity = 1.0;

          // Outer stroke opacity animates
          final strokeOpacity = 0.2 * (0.4 + 0.6 * t * 1.5);

          return LineChart(
            LineChartData(
              gridData: const FlGridData(
                show: false,
                drawHorizontalLine: true,
                drawVerticalLine: true,
              ),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              minX: 0,
              // Finds the min Y value in the data & adds padding at the bottom
              minY: isNoHistory
                  ? 0
                  : items.map((e) => e.y).min * _kPaddingRatio,
              maxY: isNoHistory
                  ? _kSkeletonPrice * 2
                  : maxYVal + (maxYVal * 0.01),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: items.map((e) => FlSpot(e.x, e.y)).toList(),
                  isCurved: false, // Straight lines like real charts
                  color: primaryColor.withValues(alpha: 0.9),
                  barWidth: 2,
                  isStrokeCapRound: false, // Sharp corners like real charts
                  dotData: FlDotData(
                    show: true,
                    checkToShowDot: (spot, _) => spot.x == items.length - 1,
                    getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                      radius: dotRadius,
                      color: widget.isSkeleton
                          ? (isDark ? colors.fill3 : colors.fill2).withValues(
                              alpha: dotOpacity,
                            )
                          : primaryColor.withValues(alpha: dotOpacity),
                      strokeColor: widget.isSkeleton
                          ? Colors.transparent
                          : primaryColor.withValues(alpha: strokeOpacity),
                      strokeWidth: 8,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.3, 1.0],
                      colors: gradientColors,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
      ),
    );
  }
}

/// Data model for a single chart data point
///
/// Represents x (index) and y (price) coordinates
class ChartDataItem {
  /// X coordinate (index/time)
  final double x;

  /// Y coordinate (price value)
  final double y;

  const ChartDataItem(this.x, this.y);
}
