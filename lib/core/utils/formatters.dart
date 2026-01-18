import 'package:intl/intl.dart';

/// Formatting utilities
class Formatters {
  Formatters._();

  /// Formats currency amount
  static String formatCurrency(
    double amount, {
    String symbol = '\$',
    int decimalPlaces = 2,
  }) {
    final formatter = NumberFormat.currency(
      symbol: symbol,
      decimalDigits: decimalPlaces,
    );
    return formatter.format(amount);
  }

  /// Formats number with commas
  static String formatNumber(double number, {int decimalPlaces = 2}) {
    final formatter = NumberFormat('#,##0.${'0' * decimalPlaces}');
    return formatter.format(number);
  }

  /// Formats date
  static String formatDate(DateTime date, {String pattern = 'yyyy-MM-dd'}) {
    final formatter = DateFormat(pattern);
    return formatter.format(date);
  }

  /// Formats date and time
  static String formatDateTime(
    DateTime date, {
    String pattern = 'yyyy-MM-dd HH:mm:ss',
  }) {
    final formatter = DateFormat(pattern);
    return formatter.format(date);
  }

  /// Formats relative time (e.g., "2 hours ago")
  static String formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
    if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    }
    if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    }
    if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    }
    return 'Just now';
  }
}

