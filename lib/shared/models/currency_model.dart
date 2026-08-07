import 'dart:convert';

import 'package:flutter/services.dart';

/// Currency model representing a currency with its ISO 4217 code
class CurrencyModel {
  const CurrencyModel({
    required this.name,
    required this.symbol,
    required this.code,
    required this.countryCode,
  });

  factory CurrencyModel.fromJson(Map<String, Object?> json) {
    return CurrencyModel(
      name: json['name']! as String,
      symbol: json['symbol']! as String,
      code: json['code']! as String,
      countryCode: json['countryCode']! as String,
    );
  }

  final String name;
  final String symbol;
  final String code;
  final String countryCode;

  // Cache for loaded currencies
  static List<CurrencyModel>? _cachedCurrencies;

  /// Load all currencies from JSON asset (cached after first load)
  static Future<List<CurrencyModel>> loadFromJson() async {
    if (_cachedCurrencies != null) {
      return _cachedCurrencies!;
    }

    try {
      final String jsonString = await rootBundle.loadString(
        'assets/data/currencies.json',
      );
      final jsonList = json.decode(jsonString) as List<Object?>;

      _cachedCurrencies = List.unmodifiable(
        jsonList.map(
          (item) => CurrencyModel.fromJson(item! as Map<String, Object?>),
        ),
      );
      return _cachedCurrencies!;
    } catch (e) {
      throw Exception('Failed to load currencies: $e');
    }
  }

  /// Find currency by code (case-insensitive)
  static Future<CurrencyModel?> findByCode(String code) async {
    final currencies = await loadFromJson();
    try {
      return currencies.firstWhere(
        (currency) => currency.code.toLowerCase() == code.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Find currencies by name (case-insensitive, partial match)
  static Future<List<CurrencyModel>> searchByName(String query) async {
    final currencies = await loadFromJson();
    final lowerQuery = query.toLowerCase();
    return currencies
        .where((currency) => currency.name.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Get all currencies sorted by name
  static Future<List<CurrencyModel>> getAllSorted() async {
    final currencies = await loadFromJson();
    final sorted = List<CurrencyModel>.from(currencies);
    sorted.sort((a, b) => a.name.compareTo(b.name));
    return sorted;
  }

  @override
  bool operator ==(Object other) {
    return other is CurrencyModel &&
        other.name == name &&
        other.symbol == symbol &&
        other.code == code &&
        other.countryCode == countryCode;
  }

  @override
  int get hashCode => Object.hash(name, symbol, code, countryCode);
}
