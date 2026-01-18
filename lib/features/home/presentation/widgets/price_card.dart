import 'package:aster/features/home/data/data.dart';
import 'package:aster/features/home/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:remixicon/remixicon.dart';
import 'package:unicons/unicons.dart';

/// Widget displaying Bitcoin price information with chart
/// Shows current price, price change percentage, and 24-hour price chart
class PriceCard extends StatefulWidget {
  const PriceCard({super.key});

  @override
  State<PriceCard> createState() => _PriceCardState();
}

class _PriceCardState extends State<PriceCard> {
  List<ChartDataItem>? _chartData;
  double? _currentPrice;
  double? _priceChange;
  bool _isLoading = true;
  bool _hasFetched = false; // Track if we've already fetched data

  @override
  void initState() {
    super.initState();
    _fetchPriceData();
  }

  Future<void> _fetchPriceData() async {
    // Only fetch once
    if (_hasFetched) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Import the service
      final chartData = await BitcoinPriceService.fetchTodayPriceData();
      final currentPrice = await BitcoinPriceService.fetchCurrentPrice();
      final priceChange = BitcoinPriceService.calculatePriceChange(chartData);

      if (mounted) {
        setState(() {
          _chartData = chartData;
          _currentPrice = currentPrice;
          _priceChange = priceChange;
          _isLoading = false;
          _hasFetched = true; // Mark as fetched
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error loading price data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasFetched =
              true; // Mark as fetched even on error to prevent retries
        });
      }
    }
  }

  /// Formats price as currency string (e.g., "$100,000")
  String _formatPrice(double? price) {
    if (price == null) return 'Loading...';
    final formatter = NumberFormat('#,##0');
    return '\$${formatter.format(price)}';
  }

  /// Formats price change percentage (e.g., "5.2%")
  String _formatPriceChange(double? change) {
    if (change == null) return '';
    return '${change.abs().toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: spacing.spacing16,
            horizontal: spacing.spacing16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            // textBaseline: TextBaseline.alphabetic,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: colors.fill1,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      UniconsLine.bitcoin,
                      size: spacing.spacing32,
                      color: Colors.orange.withValues(alpha: 0.8),
                    ),
                  ),
                  SizedBox(width: spacing.spacing4),
                  Text(
                    'Bitcoin Price',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.text5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatPrice(_currentPrice),
                    style: textTheme.displayMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.text5,
                          fontSize: 40,
                          height: 0.85,
                        )
                        .toNumeric(context),
                  ),
                ],
              ),
              if (_priceChange != null) ...[
                // SizedBox(height: spacing.spacing2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      (_priceChange ?? 0) >= 0
                          ? RemixIcons.arrow_up_line
                          : RemixIcons.arrow_down_line,
                      size: spacing.spacing14,
                      color: (_priceChange ?? 0) >= 0
                          ? colors.success6
                          : colors.danger6,
                    ),
                    SizedBox(width: spacing.spacing2),
                    Text(
                      _formatPriceChange(_priceChange),
                      style: textTheme.labelLarge
                          ?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: (_priceChange ?? 0) >= 0
                                ? colors.success6
                                : colors.danger6,
                          )
                          .toNumeric(context),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _isLoading
            ? SizedBox(
                height: spacing.spacing80,
                child: Center(
                  child: CustomLoader(
                    colorVariant: LoaderColorVariant.primary,
                    size: LoaderSize.medium,
                  ),
                ),
              )
            : PriceChart(
                data: _chartData ?? [],
                isSkeleton: _chartData == null || _chartData!.isEmpty,
              ),
      ],
    );
  }
}

/// Custom painter for drawing grid lines with fade effects
/// Used for chart background decoration
class GridPainter extends CustomPainter {
  /// Color of the grid lines
  final Color color;

  /// Size of each grid cell
  final double gridSize;

  /// Height of fade effect at top and bottom
  final double fadeHeight;

  GridPainter({
    required this.color,
    this.gridSize = 10.0,
    this.fadeHeight = 40.0,
  });

  /// Calculates opacity for grid lines based on vertical position
  /// Creates fade effect at top and bottom edges
  double _getOpacity(double y, double height) {
    if (y < fadeHeight) {
      // Fade from top
      return (y / fadeHeight) * 0.1;
    } else if (y > height - fadeHeight) {
      // Fade from bottom
      return ((height - y) / fadeHeight) * 0.1;
    } else {
      // Full opacity in middle
      return 0.1;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    // Draw vertical lines
    for (double x = 0; x < size.width; x += gridSize) {
      // For vertical lines, use average opacity
      final avgOpacity = (size.height / 2 < fadeHeight)
          ? (size.height / 2 / fadeHeight) * 0.1
          : 0.1;
      final paint = basePaint..color = color.withValues(alpha: avgOpacity);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines with position-based opacity
    for (double y = 0; y < size.height; y += gridSize) {
      final opacity = _getOpacity(y, size.height);
      final paint = basePaint..color = color.withValues(alpha: opacity);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
