import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:aster/features/home/data/models/chart_data_item.dart';

/// Service to fetch Bitcoin price data from CoinGecko API
class BitcoinPriceService {
  static const String baseUrl = 'https://api.coingecko.com/api/v3';

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

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final prices = data['prices'] as List<dynamic>;

        if (prices.isEmpty) {
          // Fallback: fetch current price if no historical data
          return await _fetchCurrentPriceFallback();
        }

        // Convert to ChartDataItem format
        // x: index (0 to n-1), y: price in USD
        final chartData = <ChartDataItem>[];
        for (int i = 0; i < prices.length; i++) {
          final pricePoint = prices[i] as List<dynamic>;
          final price = (pricePoint[1] as num).toDouble();
          chartData.add(ChartDataItem(i.toDouble(), price));
        }

        return chartData;
      } else {
        // Fallback to current price if API fails
        return await _fetchCurrentPriceFallback();
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error fetching Bitcoin price data: $e');
      // Fallback to current price
      return await _fetchCurrentPriceFallback();
    }
  }

  /// Fetches current Bitcoin price as fallback when historical data is unavailable
  ///
  /// Returns a flat line chart with the current price repeated 24 times
  static Future<List<ChartDataItem>> _fetchCurrentPriceFallback() async {
    try {
      final url = Uri.parse(
        '$baseUrl/simple/price?ids=bitcoin&vs_currencies=usd',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final price = (data['bitcoin']['usd'] as num).toDouble();

        // Return a flat line with current price (24 points)
        return List.generate(
          24,
          (index) => ChartDataItem(index.toDouble(), price),
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error fetching current Bitcoin price: $e');
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

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['bitcoin']['usd'] as num).toDouble();
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error fetching current Bitcoin price: $e');
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
}
