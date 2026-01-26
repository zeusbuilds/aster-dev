/// Data model for a single chart data point.
///
/// Represents x (index) and y (price) coordinates for chart visualization.
class ChartDataItem {
  /// X coordinate (index/time).
  final double x;

  /// Y coordinate (price value).
  final double y;

  const ChartDataItem(this.x, this.y);
}
