import 'dart:convert';

import 'package:flutter/services.dart';

/// Country model representing a country with its ISO 3166-1 alpha-2 code
class CountryModel {
  const CountryModel({required this.name, required this.code});

  factory CountryModel.fromJson(Map<String, Object?> json) {
    return CountryModel(
      name: json['name']! as String,
      code: json['code']! as String,
    );
  }

  final String name;
  final String code;

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
      final jsonList = json.decode(jsonString) as List<Object?>;

      _cachedCountries = List.unmodifiable(
        jsonList.map(
          (item) => CountryModel.fromJson(item! as Map<String, Object?>),
        ),
      );
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

  @override
  bool operator ==(Object other) =>
      other is CountryModel && other.name == name && other.code == code;

  @override
  int get hashCode => Object.hash(name, code);
}
