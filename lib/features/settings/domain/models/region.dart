import 'package:flutter/foundation.dart';

/// Validated ISO 3166-1 alpha-2 region metadata.
@immutable
final class Region {
  Region({required this.name, required this.code}) {
    if (name.trim() != name || name.isEmpty || name.length > 80) {
      throw const FormatException('Invalid region name.');
    }
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
      throw const FormatException('Invalid ISO 3166-1 region code.');
    }
  }

  factory Region.fromJson(Map<String, Object?> json) {
    return Region(name: json['name'] as String, code: json['code'] as String);
  }

  final String name;
  final String code;

  @override
  bool operator ==(Object other) =>
      other is Region && other.name == name && other.code == code;

  @override
  int get hashCode => Object.hash(name, code);
}
