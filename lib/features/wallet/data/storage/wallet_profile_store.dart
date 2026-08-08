import 'dart:async';
import 'dart:convert';

import '../../../../core/config/app_environment.dart';
import '../../../../core/constants/storage_keys.dart';
import '../../../../core/errors/errors.dart';
import '../../../../core/storage/preferences_service.dart';
import '../../domain/models/models.dart';
import 'wallet_registry_document_store.dart';

abstract interface class WalletProfilePersistence {
  Future<AppResult<WalletRegistry>> read();
  Future<AppResult<WalletRegistry>> stageProvision(WalletProfile profile);
  Future<AppResult<WalletRegistry>> commitProvision(String walletId);
  Future<AppResult<WalletRegistry>> setActive(String walletId);
  Future<AppResult<WalletRegistry>> remove(String walletId);
}

/// Serialized, versioned storage for non-secret wallet metadata.
final class WalletProfileStore implements WalletProfilePersistence {
  WalletProfileStore(
    this._documents,
    this._legacyPreferences, {
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  final WalletRegistryDocumentStore _documents;
  final PreferencesService _legacyPreferences;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();

  @override
  Future<AppResult<WalletRegistry>> read() {
    return _enqueue(() async {
      try {
        return AppResult.success(await _readUnsafe());
      } catch (error, stackTrace) {
        return AppResult.failure(
          FailureMapper.from(
            error,
            stackTrace,
            fallbackCode: 'wallet_registry_read_failed',
          ),
        );
      }
    });
  }

  @override
  Future<AppResult<WalletRegistry>> stageProvision(WalletProfile profile) {
    return _mutate((snapshot) {
      if (profile.state != WalletProfileState.provisioning) {
        throw ArgumentError.value(
          profile.state,
          'profile.state',
          'A staged profile must be provisioning.',
        );
      }
      if (snapshot.profiles.any((item) => item.id == profile.id)) {
        throw StateError('Wallet profile already exists.');
      }
      return WalletRegistry(
        profiles: [...snapshot.profiles, profile],
        activeWalletId: snapshot.activeWalletId,
      );
    }, fallbackCode: 'wallet_registry_stage_failed');
  }

  @override
  Future<AppResult<WalletRegistry>> commitProvision(String walletId) {
    return _mutate((snapshot) {
      final profile = snapshot.profiles
          .where((item) => item.id == walletId)
          .firstOrNull;
      if (profile == null || profile.state != WalletProfileState.provisioning) {
        throw StateError('Staged wallet profile does not exist.');
      }
      return WalletRegistry(
        profiles: [
          for (final item in snapshot.profiles)
            if (item.id == walletId)
              item.copyWith(
                state: WalletProfileState.ready,
                updatedAt: _nextUpdatedAt(item),
              )
            else
              item,
        ],
        activeWalletId: walletId,
      );
    }, fallbackCode: 'wallet_registry_commit_failed');
  }

  @override
  Future<AppResult<WalletRegistry>> setActive(String walletId) {
    return _mutate((snapshot) {
      if (!snapshot.profiles.any(
        (profile) =>
            profile.id == walletId && profile.state == WalletProfileState.ready,
      )) {
        throw StateError('Wallet profile does not exist.');
      }
      return WalletRegistry(
        profiles: snapshot.profiles,
        activeWalletId: walletId,
      );
    }, fallbackCode: 'wallet_registry_activate_failed');
  }

  @override
  Future<AppResult<WalletRegistry>> remove(String walletId) {
    return _mutate((snapshot) {
      final remaining = snapshot.profiles
          .where((profile) => profile.id != walletId)
          .toList(growable: false);
      if (remaining.length == snapshot.profiles.length) {
        throw StateError('Wallet profile does not exist.');
      }
      return WalletRegistry(
        profiles: remaining,
        activeWalletId: snapshot.activeWalletId == walletId
            ? remaining
                  .where((profile) => profile.state == WalletProfileState.ready)
                  .firstOrNull
                  ?.id
            : snapshot.activeWalletId,
      );
    }, fallbackCode: 'wallet_registry_remove_failed');
  }

  Future<AppResult<WalletRegistry>> _mutate(
    WalletRegistry Function(WalletRegistry current) mutation, {
    required String fallbackCode,
  }) {
    return _enqueue(() async {
      try {
        final next = mutation(await _readUnsafe());
        await _writeUnsafe(next);
        return AppResult.success(next);
      } catch (error, stackTrace) {
        return AppResult.failure(
          FailureMapper.from(error, stackTrace, fallbackCode: fallbackCode),
        );
      }
    });
  }

  Future<WalletRegistry> _readUnsafe() async {
    if (await _legacyPreferences.containsKey(
          StorageKeys.legacyWalletRegistryV2,
        ) ||
        await _legacyPreferences.containsKey(
          StorageKeys.legacyWalletRegistryV1,
        )) {
      throw const LegacyWalletDataException();
    }
    final current = await _documents.read();
    if (current != null) return _decode(current, version: 3);
    return WalletRegistry(profiles: const [], activeWalletId: null);
  }

  static WalletRegistry _decode(String encoded, {required int version}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const StoredDataCorruptionException();
    }
    if (decoded is! Map<String, Object?> || decoded['version'] != version) {
      throw const StoredDataCorruptionException();
    }
    final rawProfiles = decoded['profiles'];
    final activeWalletId = decoded['activeWalletId'];
    if (rawProfiles is! List<Object?> ||
        (activeWalletId != null && activeWalletId is! String)) {
      throw const StoredDataCorruptionException();
    }
    try {
      return WalletRegistry(
        profiles: [
          for (final item in rawProfiles)
            if (item case final Map<String, Object?> profile)
              _profileFromJson(profile)
            else
              throw const StoredDataCorruptionException(),
        ],
        activeWalletId: activeWalletId as String?,
      );
    } on StoredDataCorruptionException {
      rethrow;
    } on ArgumentError {
      throw const StoredDataCorruptionException();
    }
  }

  Future<void> _writeUnsafe(WalletRegistry snapshot) async {
    await _documents.write(
      jsonEncode({
        'version': 3,
        'activeWalletId': snapshot.activeWalletId,
        'profiles': [
          for (final profile in snapshot.profiles) _profileToJson(profile),
        ],
      }),
    );
  }

  static WalletProfile _profileFromJson(Map<String, Object?> json) {
    try {
      final id = json['id'];
      final name = json['name'];
      final createdAtValue = json['createdAt'];
      final updatedAtValue = json['updatedAt'];
      final environmentValue = json['environment'];
      final stateValue = json['state'];
      final storageTokenValue = json['storageToken'];
      if (id is! String ||
          name is! String ||
          createdAtValue is! String ||
          updatedAtValue is! String ||
          environmentValue is! String ||
          stateValue is! String ||
          storageTokenValue is! String) {
        throw const StoredDataCorruptionException();
      }
      final createdAt = DateTime.tryParse(createdAtValue);
      final updatedAt = DateTime.tryParse(updatedAtValue);
      if (createdAt == null ||
          updatedAt == null ||
          !createdAt.isUtc ||
          !updatedAt.isUtc ||
          environmentValue != environmentValue.trim()) {
        throw const StoredDataCorruptionException();
      }
      final state = switch (stateValue) {
        'provisioning' => WalletProfileState.provisioning,
        'ready' => WalletProfileState.ready,
        _ => throw const StoredDataCorruptionException(),
      };
      return WalletProfile(
        id: id,
        name: name,
        createdAt: createdAt,
        updatedAt: updatedAt,
        environment: BlockchainEnvironment.parse(environmentValue),
        state: state,
        storageToken: storageTokenValue,
      );
    } on StoredDataCorruptionException {
      rethrow;
    } on ArgumentError {
      throw const StoredDataCorruptionException();
    } on AppConfigurationException {
      throw const StoredDataCorruptionException();
    }
  }

  static Map<String, Object?> _profileToJson(WalletProfile profile) => {
    'id': profile.id,
    'name': profile.name,
    'createdAt': profile.createdAt.toUtc().toIso8601String(),
    'updatedAt': profile.updatedAt.toUtc().toIso8601String(),
    'environment': profile.environment.name,
    'state': profile.state.name,
    'storageToken': profile.storageToken,
  };

  DateTime _nextUpdatedAt(WalletProfile profile) {
    final now = _clock().toUtc();
    return now.isAfter(profile.updatedAt) ? now : profile.updatedAt;
  }

  static DateTime _utcNow() => DateTime.now().toUtc();

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
