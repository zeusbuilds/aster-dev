import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'currency_model.freezed.dart';
part 'currency_model.g.dart';

/// Currency model representing a currency with its ISO 4217 code
@freezed
class CurrencyModel with _$CurrencyModel {
  const factory CurrencyModel({
    required String name,
    required String symbol,
    required String code,
    required String countryCode,
  }) = _CurrencyModel;

  factory CurrencyModel.fromJson(Map<String, dynamic> json) =>
      _$CurrencyModelFromJson(json);

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
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;

      _cachedCurrencies = jsonList
          .map((json) => CurrencyModel.fromJson(json as Map<String, dynamic>))
          .toList();
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
}
