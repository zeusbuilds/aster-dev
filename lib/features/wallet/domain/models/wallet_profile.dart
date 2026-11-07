import 'package:flutter/foundation.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/config/signet_deployment.dart';
import '../../../../core/validation/validation.dart';

/// Durable state of one wallet profile transaction.
enum WalletProfileState {
  /// Profile was staged before native files and credentials were provisioned.
  provisioning,

  /// Native state and credentials were provisioned and committed.
  ready,

  /// Explicitly authorized local removal, resumed after an interrupted delete.
  deleting,
}

/// Non-secret app identity for one native wallet store.
///
/// Native handles, credentials, and mnemonic material never belong in this
/// model. [id] and [storageToken] are independent random identifiers and must
/// not be derived from seed material.
@immutable
final class WalletProfile {
  WalletProfile({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.environment,
    this.backend = WalletBackend.rln,
    this.signetDeployment,
    required this.state,
    required this.storageToken,
  }) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Has an invalid shape.');
    }
    if (!isValidName(name)) {
      throw ArgumentError.value(name, 'name', 'Has an invalid shape.');
    }
    if (!createdAt.isUtc || !updatedAt.isUtc || updatedAt.isBefore(createdAt)) {
      throw ArgumentError('Wallet profile timestamps are invalid.');
    }
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(storageToken)) {
      throw ArgumentError.value(
        storageToken,
        'storageToken',
        'Has an invalid shape.',
      );
    }
    if (signetDeployment != null &&
        environment != BlockchainEnvironment.signet) {
      throw ArgumentError('Only Signet profiles carry a Signet deployment.');
    }
  }

  /// Whether [value] is safe to persist and render as a wallet name.
  static bool isValidName(String value) =>
      DisplayTextPolicy.isSafe(value, maximumCharacters: 64);

  /// App-generated opaque identifier unrelated to mnemonic or key material.
  final String id;

  /// User-facing wallet name.
  final String name;

  /// UTC creation time.
  final DateTime createdAt;

  /// UTC time of the latest profile change.
  final DateTime updatedAt;

  /// Chain on which this wallet's native store was initialized.
  final BlockchainEnvironment environment;

  /// Native store format that owns this profile's directory.
  final WalletBackend backend;

  /// Chain deployment proven when this Signet wallet was provisioned.
  ///
  /// `null` on an older Signet record means unknown, never public by default.
  /// Such records remain readable but cannot activate against any deployment.
  final SignetDeployment? signetDeployment;

  /// Transaction state used to recover interrupted wallet provisioning.
  final WalletProfileState state;

  /// Non-secret proof of ownership for native files and secret envelopes.
  ///
  /// Every usable profile carries one so opening and cleanup can fail closed
  /// on a colliding resource. Pre-ownership metadata requires explicit wallet
  /// recovery and is never promoted into this model.
  final String storageToken;

  /// A compact identifier suitable for display, never for authentication.
  String get displayId {
    final normalized = id.toUpperCase();
    return '${normalized.substring(0, 6)} ${normalized.substring(26)}';
  }

  WalletProfile copyWith({
    String? name,
    DateTime? updatedAt,
    WalletProfileState? state,
  }) {
    return WalletProfile(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      environment: environment,
      backend: backend,
      signetDeployment: signetDeployment,
      state: state ?? this.state,
      storageToken: storageToken,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WalletProfile &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.environment == environment &&
      other.backend == backend &&
      other.signetDeployment == signetDeployment &&
      other.state == state &&
      other.storageToken == storageToken;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    createdAt,
    updatedAt,
    environment,
    backend,
    signetDeployment,
    state,
    storageToken,
  );
}
