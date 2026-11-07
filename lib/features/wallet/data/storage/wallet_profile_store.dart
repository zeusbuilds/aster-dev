import 'dart:async';
import 'dart:convert';

import '../../../../core/config/app_environment.dart';
import '../../../../core/config/signet_deployment.dart';
import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';
import 'wallet_registry_document_store.dart';

abstract interface class WalletProfilePersistence {
  Future<AppResult<WalletRegistry>> read();
  Future<AppResult<WalletRegistry>> stageProvision(WalletProfile profile);
  Future<AppResult<WalletRegistry>> commitProvision(String walletId);
  Future<AppResult<WalletRegistry>> setActive(String walletId);
  Future<AppResult<WalletRegistry>> remove(String walletId);
}

/// Persists delete authority before any wallet resources are destroyed.
abstract interface class WalletDeletionPersistence {
  Future<AppResult<WalletRegistry>> stageDeletion(String walletId);
}

/// Serialized, versioned storage for current non-secret wallet metadata.
final class WalletProfileStore
    implements WalletProfilePersistence, WalletDeletionPersistence {
  WalletProfileStore(this._documents, {DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  final WalletRegistryDocumentStore _documents;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();

  static const _rlnSchemaVersion = 1;
  static const _backendSchemaVersion = 2;
  static const _signetDeploymentSchemaVersion = 3;

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
        throw _profileConflict('wallet_profile_already_exists');
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
        throw _profileConflict('wallet_profile_stage_missing');
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
        throw _profileConflict('wallet_profile_activation_conflict');
      }
      return WalletRegistry(
        profiles: snapshot.profiles,
        activeWalletId: walletId,
      );
    }, fallbackCode: 'wallet_registry_activate_failed');
  }

  @override
  Future<AppResult<WalletRegistry>> stageDeletion(String walletId) {
    return _mutate((snapshot) {
      final target = snapshot.readyProfiles
          .where((profile) => profile.id == walletId)
          .firstOrNull;
      if (target == null ||
          snapshot.provisioningProfiles.isNotEmpty ||
          snapshot.deletingProfiles.isNotEmpty) {
        throw _profileConflict('wallet_deletion_conflict');
      }
      return WalletRegistry(
        profiles: [
          for (final profile in snapshot.profiles)
            if (profile.id == walletId)
              profile.copyWith(
                state: WalletProfileState.deleting,
                updatedAt: _nextUpdatedAt(profile),
              )
            else
              profile,
        ],
        activeWalletId: snapshot.activeWalletId == walletId
            ? snapshot.readyProfiles
                  .where((profile) => profile.id != walletId)
                  .firstOrNull
                  ?.id
            : snapshot.activeWalletId,
      );
    }, fallbackCode: 'wallet_registry_delete_stage_failed');
  }

  @override
  Future<AppResult<WalletRegistry>> remove(String walletId) {
    return _mutate((snapshot) {
      final remaining = snapshot.profiles
          .where((profile) => profile.id != walletId)
          .toList(growable: false);
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
    final current = await _documents.read();
    if (current != null) return _decode(current);
    return WalletRegistry(profiles: const [], activeWalletId: null);
  }

  static WalletRegistry _decode(String encoded) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const StoredDataCorruptionException();
    }
    if (decoded is! Map<String, Object?>) {
      throw const StoredDataCorruptionException();
    }
    final version = decoded['version'];
    if (version is! int ||
        (version != _rlnSchemaVersion &&
            version != _backendSchemaVersion &&
            version != _signetDeploymentSchemaVersion)) {
      throw const StoredDataCorruptionException();
    }
    final storesBackend = version != _rlnSchemaVersion;
    final storesSignetDeployment = version == _signetDeploymentSchemaVersion;
    final rawProfiles = decoded['profiles'];
    final activeWalletId = decoded['activeWalletId'];
    if (rawProfiles is! List<Object?> ||
        (activeWalletId != null && activeWalletId is! String)) {
      throw const StoredDataCorruptionException();
    }
    try {
      final registry = WalletRegistry(
        profiles: [
          for (final item in rawProfiles)
            if (item case final Map<String, Object?> profile)
              _profileFromJson(
                profile,
                storesBackend: storesBackend,
                storesSignetDeployment: storesSignetDeployment,
              )
            else
              throw const StoredDataCorruptionException(),
        ],
        activeWalletId: activeWalletId as String?,
      );
      if (version == _backendSchemaVersion &&
          registry.profiles.every(
            (profile) => profile.backend == WalletBackend.rln,
          )) {
        throw const StoredDataCorruptionException();
      }
      if (storesSignetDeployment &&
          !registry.profiles.any(
            (profile) => profile.signetDeployment != null,
          )) {
        throw const StoredDataCorruptionException();
      }
      return registry;
    } on StoredDataCorruptionException {
      rethrow;
    } on ArgumentError {
      throw const StoredDataCorruptionException();
    }
  }

  Future<void> _writeUnsafe(WalletRegistry snapshot) async {
    // Older builds must reject format/deployment-aware records rather than
    // reopen them under legacy assumptions. Unbound RLN registries retain
    // their historical encoding without inferring any Signet deployment.
    final storesSignetDeployment = snapshot.profiles.any(
      (profile) => profile.signetDeployment != null,
    );
    final storesBackend =
        storesSignetDeployment ||
        snapshot.profiles.any(
          (profile) => profile.backend != WalletBackend.rln,
        );
    await _documents.write(
      jsonEncode({
        'version': storesSignetDeployment
            ? _signetDeploymentSchemaVersion
            : storesBackend
            ? _backendSchemaVersion
            : _rlnSchemaVersion,
        'activeWalletId': snapshot.activeWalletId,
        'profiles': [
          for (final profile in snapshot.profiles)
            _profileToJson(
              profile,
              storesBackend: storesBackend,
              storesSignetDeployment: storesSignetDeployment,
            ),
        ],
      }),
    );
  }

  static WalletProfile _profileFromJson(
    Map<String, Object?> json, {
    required bool storesBackend,
    required bool storesSignetDeployment,
  }) {
    try {
      final id = json['id'];
      final name = json['name'];
      final createdAtValue = json['createdAt'];
      final updatedAtValue = json['updatedAt'];
      final environmentValue = json['environment'];
      final backendValue = json['backend'];
      final signetDeploymentValue = json['signetDeployment'];
      final stateValue = json['state'];
      final storageTokenValue = json['storageToken'];
      if (id is! String ||
          name is! String ||
          createdAtValue is! String ||
          updatedAtValue is! String ||
          environmentValue is! String ||
          (storesBackend
              ? backendValue is! String
              : json.containsKey('backend')) ||
          (storesSignetDeployment
              ? signetDeploymentValue != null &&
                    signetDeploymentValue is! String
              : json.containsKey('signetDeployment')) ||
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
        'deleting' => WalletProfileState.deleting,
        _ => throw const StoredDataCorruptionException(),
      };
      return WalletProfile(
        id: id,
        name: name,
        createdAt: createdAt,
        updatedAt: updatedAt,
        environment: BlockchainEnvironment.parse(environmentValue),
        backend: storesBackend
            ? WalletBackend.parse(backendValue as String)
            : WalletBackend.rln,
        signetDeployment:
            storesSignetDeployment && signetDeploymentValue != null
            ? SignetDeployment.parse(signetDeploymentValue as String)
            : null,
        state: state,
        storageToken: storageTokenValue,
      );
    } on StoredDataCorruptionException {
      rethrow;
    } on ArgumentError {
      throw const StoredDataCorruptionException();
    } on AppConfigurationException {
      throw const StoredDataCorruptionException();
    } on FormatException {
      throw const StoredDataCorruptionException();
    }
  }

  static Map<String, Object?> _profileToJson(
    WalletProfile profile, {
    required bool storesBackend,
    required bool storesSignetDeployment,
  }) => {
    'id': profile.id,
    'name': profile.name,
    'createdAt': profile.createdAt.toUtc().toIso8601String(),
    'updatedAt': profile.updatedAt.toUtc().toIso8601String(),
    'environment': profile.environment.name,
    if (storesBackend) 'backend': profile.backend.wireName,
    if (storesSignetDeployment &&
        profile.environment == BlockchainEnvironment.signet)
      'signetDeployment': profile.signetDeployment?.wireName,
    'state': profile.state.name,
    'storageToken': profile.storageToken,
  };

  static AppFailureException _profileConflict(String code) {
    return AppFailureException(
      AppFailure(
        code: code,
        kind: AppFailureKind.conflict,
        userMessage:
            'The wallet changed while this action was running. Try again.',
        retryable: true,
      ),
    );
  }

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
