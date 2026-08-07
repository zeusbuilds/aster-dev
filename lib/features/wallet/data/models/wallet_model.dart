import 'package:flutter/foundation.dart';

/// Non-secret metadata used to identify a wallet inside the app.
///
/// Native wallet state, credentials, and mnemonic material never belong in
/// this model. [id] is an opaque app identifier supplied when the SDK wallet
/// is registered; it must not be derived from seed material.
@immutable
class WalletProfile {
  const WalletProfile({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = false,
  });

  factory WalletProfile.fromJson(Map<String, Object?> json) {
    return WalletProfile(
      id: json['id']! as String,
      name: json['name']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt']! as String).toUtc(),
      isActive: json['isActive'] as bool? ?? false,
    );
  }

  /// Opaque identifier that is unrelated to mnemonic or key material.
  final String id;

  /// User-facing wallet name.
  final String name;

  /// UTC creation time.
  final DateTime createdAt;

  /// UTC time of the latest profile change.
  final DateTime updatedAt;

  /// Whether this is the selected wallet in the persisted registry snapshot.
  final bool isActive;

  /// A compact identifier suitable for display, never for authentication.
  String get displayId {
    final normalized = id.replaceAll('-', '').toUpperCase();
    if (normalized.length <= 12) return normalized;
    return '${normalized.substring(0, 6)} ${normalized.substring(normalized.length - 6)}';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'isActive': isActive,
  };

  WalletProfile copyWith({String? name, DateTime? updatedAt, bool? isActive}) {
    return WalletProfile(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
