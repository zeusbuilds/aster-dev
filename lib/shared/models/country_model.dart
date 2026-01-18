import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'country_model.freezed.dart';
part 'country_model.g.dart';

/// Country model representing a country with its ISO 3166-1 alpha-2 code
@freezed
class CountryModel with _$CountryModel {
  const factory CountryModel({required String name, required String code}) =
      _CountryModel;

  factory CountryModel.fromJson(Map<String, dynamic> json) =>
      _$CountryModelFromJson(json);

  // Cache for loaded countries
  static List<CountryModel>? _cachedCountries;

  /// Load all countries from JSON asset (cached after first load)
  static Future<List<CountryModel>> loadFromJson() async {
    if (_cachedCountries != null) {
      return _cachedCountries!;
    }

    try {
      final String jsonString = await rootBundle.loadString(
        'assets/data/countries.json',
      );
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;

      _cachedCountries = jsonList
          .map((json) => CountryModel.fromJson(json as Map<String, dynamic>))
          .toList();
      return _cachedCountries!;
    } catch (e) {
      throw Exception('Failed to load countries: $e');
    }
  }

  /// Find country by code (case-insensitive)
  static Future<CountryModel?> findByCode(String code) async {
    final countries = await loadFromJson();
    try {
      return countries.firstWhere(
        (country) => country.code.toLowerCase() == code.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Find countries by name (case-insensitive, partial match)
  static Future<List<CountryModel>> searchByName(String query) async {
    final countries = await loadFromJson();
    final lowerQuery = query.toLowerCase();
    return countries
        .where((country) => country.name.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Get all countries sorted by name
  static Future<List<CountryModel>> getAllSorted() async {
    final countries = await loadFromJson();
    final sorted = List<CountryModel>.from(countries);
    sorted.sort((a, b) => a.name.compareTo(b.name));
    return sorted;
  }
}
