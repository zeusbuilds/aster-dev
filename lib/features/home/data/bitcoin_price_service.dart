import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models/chart_data_item.dart';

/// Service to fetch Bitcoin price data from CoinGecko API
class BitcoinPriceService {
  static const String baseUrl = 'https://api.coingecko.com/api/v3';
  static const Duration _requestTimeout = Duration(seconds: 10);

  /// Fetches hourly Bitcoin price data for the last 24 hours
  ///
  /// Returns a list of ChartDataItem for plotting
  static Future<List<ChartDataItem>> fetchTodayPriceData() async {
    try {
      // Get current timestamp and 24 hours ago timestamp
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(hours: 24));

      // CoinGecko uses Unix timestamps in seconds
      final fromTimestamp = yesterday.millisecondsSinceEpoch ~/ 1000;
      final toTimestamp = now.millisecondsSinceEpoch ~/ 1000;

      // Fetch hourly data (1 hour interval)
      final url = Uri.parse(
        '$baseUrl/coins/bitcoin/market_chart/range'
        '?vs_currency=usd'
        '&from=$fromTimestamp'
        '&to=$toTimestamp',
      );

      final response = await http.get(url).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = _decodeObject(response.body);
        final pricesValue = data['prices'];
        if (pricesValue is! List<Object?>) {
          throw const FormatException('Price history is missing.');
        }

        if (pricesValue.isEmpty) {
          // Fallback: fetch current price if no historical data
          return _fetchCurrentPriceFallback();
        }

        // Convert to ChartDataItem format
        // x: index (0 to n-1), y: price in USD
        final chartData = <ChartDataItem>[];
        for (final (index, point) in pricesValue.indexed) {
          if (point is! List<Object?> || point.length < 2) continue;
          final priceValue = point[1];
          if (priceValue is! num) continue;
          chartData.add(ChartDataItem(index.toDouble(), priceValue.toDouble()));
        }
        if (chartData.isNotEmpty) return chartData;
      }
    } on Exception {
      // The current-price endpoint below is the documented degraded state for
      // an unavailable or malformed history response.
    }
    return _fetchCurrentPriceFallback();
  }

  /// Fetches current Bitcoin price as fallback when historical data is unavailable
  ///
  /// Returns a flat line chart with the current price repeated 24 times
  static Future<List<ChartDataItem>> _fetchCurrentPriceFallback() async {
    try {
      final url = Uri.parse(
        '$baseUrl/simple/price?ids=bitcoin&vs_currencies=usd',
      );

      final response = await http.get(url).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final price = _decodeUsdPrice(response.body);

        // Return a flat line with current price (24 points)
        return List.generate(
          24,
          (index) => ChartDataItem(index.toDouble(), price),
        );
      }
    } on Exception {
      // An empty series is an explicit unavailable state, never fake data.
    }

    // Ultimate fallback: return empty list
    return [];
  }

  /// Fetches the current Bitcoin price in USD from CoinGecko API
  ///
  /// Returns the current price, or null if the request fails
  static Future<double?> fetchCurrentPrice() async {
    try {
      final url = Uri.parse(
        '$baseUrl/simple/price?ids=bitcoin&vs_currencies=usd',
      );

      final response = await http.get(url).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        return _decodeUsdPrice(response.body);
      }
    } on Exception {
      // Null communicates that no current price is available.
    }

    return null;
  }

  /// Calculates the price change percentage from first to last data point
  ///
  /// [data] - List of chart data items
  ///
  /// Returns the percentage change, or null if insufficient data or first price is zero
  static double? calculatePriceChange(List<ChartDataItem> data) {
    if (data.length < 2) return null;

    final firstPrice = data.first.y;
    final lastPrice = data.last.y;

    if (firstPrice == 0) return null;

    return ((lastPrice - firstPrice) / firstPrice) * 100;
  }

  static Map<String, Object?> _decodeObject(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object.');
    }
    return decoded;
  }

  static double _decodeUsdPrice(String source) {
    final bitcoinValue = _decodeObject(source)['bitcoin'];
    if (bitcoinValue is! Map<String, Object?>) {
      throw const FormatException('Bitcoin price is missing.');
    }
    final usdValue = bitcoinValue['usd'];
    if (usdValue is! num) {
      throw const FormatException('USD price is missing.');
    }
    return usdValue.toDouble();
  }
}
