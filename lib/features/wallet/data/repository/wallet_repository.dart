import 'dart:convert';

import '../../../../core/core.dart';
import '../models/models.dart';

/// Persists non-secret wallet profile metadata.
///
/// Seed phrases, passwords, keys, native handles, and wallet databases are
/// deliberately outside this repository and remain owned by the SDK runtime.
class WalletRepository {
  const WalletRepository(this._preferencesService);

  final PreferencesService _preferencesService;

  Future<List<WalletProfile>> getAllWallets() async {
    return (await _readRegistry()).profiles;
  }

  Future<WalletProfile?> getActiveWallet() async {
    final profiles = (await _readRegistry()).profiles;
    return profiles.where((profile) => profile.isActive).firstOrNull;
  }

  Future<WalletProfile?> getWalletById(String walletId) async {
    return (await _readRegistry()).profiles
        .where((profile) => profile.id == walletId)
        .firstOrNull;
  }

  /// Registers metadata after the SDK has successfully created or restored a
  /// wallet.
  ///
  /// [walletId] must be opaque and unrelated to mnemonic or key material.
  Future<WalletProfile> registerWallet({
    required String walletId,
    required String name,
  }) async {
    final normalizedId = walletId.trim();
    final normalizedName = name.trim();
    if (normalizedId.isEmpty || normalizedName.isEmpty) {
      throw ArgumentError('Wallet ID and name must not be empty.');
    }
    final registry = await _readRegistry();
    if (registry.profiles.any((profile) => profile.id == normalizedId)) {
      throw StateError('Wallet profile already exists.');
    }
    final now = DateTime.now().toUtc();
    final profile = WalletProfile(
      id: normalizedId,
      name: normalizedName,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    final profiles = [
      for (final existing in registry.profiles)
        existing.copyWith(isActive: false, updatedAt: now),
      profile,
    ];
    await _writeRegistry(_WalletRegistry(profiles));
    return profile;
  }

  Future<void> setActiveWallet(String walletId) async {
    final registry = await _readRegistry();
    if (!registry.profiles.any((profile) => profile.id == walletId)) {
      throw StateError('Wallet profile not found.');
    }
    final now = DateTime.now().toUtc();
    await _writeRegistry(
      _WalletRegistry([
        for (final profile in registry.profiles)
          profile.copyWith(
            isActive: profile.id == walletId,
            updatedAt: profile.id == walletId ? now : profile.updatedAt,
          ),
      ]),
    );
  }

  Future<void> updateWallet(WalletProfile wallet) async {
    final registry = await _readRegistry();
    if (!registry.profiles.any((profile) => profile.id == wallet.id)) {
      throw StateError('Wallet profile not found.');
    }
    await _writeRegistry(
      _WalletRegistry([
        for (final profile in registry.profiles)
          if (profile.id == wallet.id)
            wallet.copyWith(updatedAt: DateTime.now().toUtc())
          else
            profile,
      ]),
    );
  }

  Future<void> deleteWallet(String walletId) async {
    final registry = await _readRegistry();
    final index = registry.profiles.indexWhere(
      (profile) => profile.id == walletId,
    );
    if (index < 0) {
      throw StateError('Wallet profile not found.');
    }
    if (registry.profiles.length == 1) {
      throw StateError('Cannot delete the only wallet profile.');
    }
    final removed = registry.profiles[index];
    final remaining = [...registry.profiles]..removeAt(index);
    if (removed.isActive) {
      remaining[0] = remaining[0].copyWith(
        isActive: true,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    await _writeRegistry(_WalletRegistry(remaining));
  }

  Future<bool> walletExists(String walletId) async {
    return (await getWalletById(walletId)) != null;
  }

  Future<_WalletRegistry> _readRegistry() async {
    final encoded = await _preferencesService.getString(
      StorageKeys.walletRegistry,
    );
    if (encoded == null) return const _WalletRegistry([]);
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, Object?> || decoded['version'] != 1) {
      throw const FormatException('Unsupported wallet registry format.');
    }
    final profilesJson = decoded['profiles'];
    if (profilesJson is! List<Object?>) {
      throw const FormatException('Invalid wallet profile registry.');
    }
    return _WalletRegistry([
      for (final item in profilesJson)
        if (item case final Map<String, Object?> profileJson)
          WalletProfile.fromJson(profileJson)
        else
          throw const FormatException('Invalid wallet profile entry.'),
    ]);
  }

  Future<void> _writeRegistry(_WalletRegistry registry) async {
    await _preferencesService.setString(
      StorageKeys.walletRegistry,
      jsonEncode({
        'version': 1,
        'profiles': [for (final profile in registry.profiles) profile.toJson()],
      }),
    );
  }
}

class _WalletRegistry {
  const _WalletRegistry(this.profiles);

  final List<WalletProfile> profiles;
}
