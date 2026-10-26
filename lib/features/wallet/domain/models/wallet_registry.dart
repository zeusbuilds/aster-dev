import 'package:flutter/foundation.dart';

import 'wallet_profile.dart';

/// Validated, immutable registry of wallet profiles.
@immutable
final class WalletRegistry {
  WalletRegistry({
    required List<WalletProfile> profiles,
    required this.activeWalletId,
  }) : profiles = List<WalletProfile>.unmodifiable(profiles) {
    final ids = this.profiles.map((profile) => profile.id).toSet();
    if (ids.length != this.profiles.length) {
      throw ArgumentError('Wallet profile IDs must be unique.');
    }
    readyProfiles = List<WalletProfile>.unmodifiable(
      this.profiles.where(
        (profile) => profile.state == WalletProfileState.ready,
      ),
    );
    provisioningProfiles = List<WalletProfile>.unmodifiable(
      this.profiles.where(
        (profile) => profile.state == WalletProfileState.provisioning,
      ),
    );
    deletingProfiles = List<WalletProfile>.unmodifiable(
      this.profiles.where(
        (profile) => profile.state == WalletProfileState.deleting,
      ),
    );
    final activeProfiles = readyProfiles.where(
      (profile) => profile.id == activeWalletId,
    );
    if (activeWalletId != null && activeProfiles.length != 1) {
      throw ArgumentError('The active wallet must be a ready profile.');
    }
    if (readyProfiles.isNotEmpty && activeWalletId == null) {
      throw ArgumentError('A non-empty ready registry needs an active wallet.');
    }
    activeProfile = activeProfiles.firstOrNull;
  }

  final List<WalletProfile> profiles;
  final String? activeWalletId;

  /// Profiles that are fully committed and safe to expose to product UI.
  late final List<WalletProfile> readyProfiles;

  /// Interrupted provisioning transactions requiring startup rollback.
  late final List<WalletProfile> provisioningProfiles;

  /// Authorized removals whose scoped cleanup must complete before opening.
  late final List<WalletProfile> deletingProfiles;

  /// Selected ready profile, or `null` when no wallet has been committed.
  late final WalletProfile? activeProfile;

  @override
  bool operator ==(Object other) =>
      other is WalletRegistry &&
      other.activeWalletId == activeWalletId &&
      listEquals(other.profiles, profiles);

  @override
  int get hashCode => Object.hash(activeWalletId, Object.hashAll(profiles));
}
