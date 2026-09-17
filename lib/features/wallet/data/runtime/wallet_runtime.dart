import 'dart:async';

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';
import '../storage/wallet_secret_store.dart';
import 'wallet_directory_manager.dart';
import 'wallet_engine.dart';

enum WalletRuntimePhase {
  inactive,
  activating,
  active,
  suspended,
  failed,
  disposed,
}

enum _ReconciliationAccess { blocked, audit, rollback, disposal }

sealed class _WalletActivation {
  const _WalletActivation();
}

final class _ProvisionWalletActivation extends _WalletActivation {
  const _ProvisionWalletActivation({
    required this.mnemonic,
    required this.storageDirectory,
  });

  final String mnemonic;
  final String storageDirectory;
}

final class _OpenPersistedWalletActivation extends _WalletActivation {
  const _OpenPersistedWalletActivation();
}

/// Observable state for the single app-owned native wallet runtime.
final class WalletRuntimeSnapshot {
  const WalletRuntimeSnapshot({
    required this.phase,
    this.walletId,
    this.failure,
  });

  final WalletRuntimePhase phase;
  final String? walletId;
  final AppFailure? failure;

  @override
  bool operator ==(Object other) =>
      other is WalletRuntimeSnapshot &&
      other.phase == phase &&
      other.walletId == walletId &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(phase, walletId, failure);
}

/// Sole owner of the app's live native wallet engine.
///
/// All engine access is serialized with lifecycle transitions. This keeps
/// wallet switching, suspension, native cleanup, and repository operations
/// ordered even when multiple ViewModels issue work concurrently. A
/// reconciliation-required result quarantines subsequent work in the same
/// queue; only explicit audit, rollback, and disposal paths may bypass it.
final class WalletRuntime {
  WalletRuntime(
    this._engineFactory,
    this._directories,
    this._secrets,
    this._services,
  );

  final WalletEngineFactory _engineFactory;
  final WalletDirectoryManager _directories;
  final WalletSecretStore _secrets;
  final WalletServiceConfiguration _services;
  final StreamController<WalletRuntimeSnapshot> _states =
      StreamController<WalletRuntimeSnapshot>.broadcast(sync: true);

  Future<void> _tail = Future<void>.value();
  WalletEngine? _engine;
  WalletProfile? _activeProfile;
  var _snapshot = const WalletRuntimeSnapshot(
    phase: WalletRuntimePhase.inactive,
  );
  bool _disposing = false;
  Future<AppResult<void>>? _disposeInFlight;
  String? _reconciliationRollbackWalletId;

  WalletRuntimeSnapshot get snapshot => _snapshot;
  Stream<WalletRuntimeSnapshot> get states => _states.stream;

  Future<AppResult<void>> restore(WalletProfile profile) {
    return _enqueue(() async {
      if (profile.state != WalletProfileState.ready) {
        return AppResult.failure(_profileStateFailure(profile));
      }
      if (profile.environment != _services.environment) {
        return AppResult.failure(_networkMismatchFailure());
      }
      final secretResult = await _secrets.read(
        profile.id,
        expectedStorageToken: profile.storageToken,
      );
      return switch (secretResult) {
        AppSuccess<WalletSecret>(:final value) => _activateReplacingUnsafe(
          profile,
          value,
          activation: const _OpenPersistedWalletActivation(),
        ),
        AppFailureResult<WalletSecret>(:final failure) => AppResult.failure(
          failure,
        ),
      };
    }, reconciliationWalletId: profile.id);
  }

  Future<AppResult<void>> provision({
    required WalletProfile profile,
    required String mnemonic,
    required String databasePassword,
  }) {
    return _enqueue(
      () async {
        if (profile.state != WalletProfileState.provisioning) {
          return AppResult.failure(_profileStateFailure(profile));
        }
        if (profile.environment != _services.environment) {
          return AppResult.failure(_networkMismatchFailure());
        }
        final storageToken = profile.storageToken;
        late final String storageDirectory;
        try {
          storageDirectory = await _directories.create(
            profile.id,
            storageToken: storageToken,
          );
        } catch (error, stackTrace) {
          return AppResult.failure(
            FailureMapper.from(
              error,
              stackTrace,
              fallbackCode: 'wallet_directory_create_failed',
            ),
          );
        }

        final writeResult = await _secrets.write(
          profile.id,
          WalletSecret(
            databasePassword: databasePassword,
            mnemonic: mnemonic,
            storageToken: storageToken,
          ),
        );
        if (writeResult case AppFailureResult<void>(:final failure)) {
          if (failure.outcomeUnknown) {
            return AppResult.failure(
              AppFailure(
                code: 'wallet_provision_rollback_failed',
                kind: AppFailureKind.storage,
                userMessage:
                    'Wallet setup and credential storage could not be confirmed. '
                    'Restart the app before continuing.',
                retryable: false,
                requiresReconciliation: true,
                outcomeUnknown: true,
                cause: failure,
              ),
            );
          }
          try {
            await _directories.remove(profile.id, storageToken: storageToken);
            return AppResult.failure(failure);
          } catch (cleanupError, cleanupStackTrace) {
            final cleanupFailure = FailureMapper.from(
              cleanupError,
              cleanupStackTrace,
              fallbackCode: 'wallet_directory_cleanup_failed',
            );
            return AppResult.failure(
              AppFailure(
                code: 'wallet_provision_rollback_failed',
                kind: AppFailureKind.storage,
                userMessage:
                    'Wallet setup failed and local cleanup needs attention.',
                retryable: false,
                requiresReconciliation: true,
                outcomeUnknown:
                    failure.outcomeUnknown || cleanupFailure.outcomeUnknown,
                cause: <AppFailure>[failure, cleanupFailure],
                stackTrace: cleanupStackTrace,
              ),
            );
          }
        }

        final activation = await _activateReplacingUnsafe(
          profile,
          WalletSecret(
            databasePassword: databasePassword,
            mnemonic: mnemonic,
            storageToken: storageToken,
          ),
          activation: _ProvisionWalletActivation(
            mnemonic: mnemonic,
            storageDirectory: storageDirectory,
          ),
        );
        if (activation is AppSuccess<void>) return activation;

        if (_activeProfile?.id == profile.id && _engine != null) {
          return AppResult.failure(
            _provisionRollbackFailure(activation, const []),
          );
        }

        final cleanupFailures = <AppFailure>[];
        final secretCleanup = await _secrets.delete(
          profile.id,
          storageToken: storageToken,
        );
        if (secretCleanup case AppFailureResult<void>(:final failure)) {
          cleanupFailures.add(failure);
        } else {
          try {
            await _directories.remove(profile.id, storageToken: storageToken);
          } catch (error, stackTrace) {
            cleanupFailures.add(
              FailureMapper.from(
                error,
                stackTrace,
                fallbackCode: 'wallet_directory_cleanup_failed',
              ),
            );
          }
        }
        if (cleanupFailures.isNotEmpty) {
          final failure = _provisionRollbackFailure(
            activation,
            cleanupFailures,
          );
          _emit(
            WalletRuntimeSnapshot(
              phase: WalletRuntimePhase.failed,
              failure: failure,
            ),
          );
          return AppResult.failure(failure);
        }
        _emit(const WalletRuntimeSnapshot(phase: WalletRuntimePhase.inactive));
        return activation;
      },
      reconciliationWalletId: profile.id,
      reconciliationRollbackWalletId: profile.id,
    );
  }

  Future<AppResult<void>> switchTo(WalletProfile profile) {
    return _enqueue(() async {
      if (profile.state != WalletProfileState.ready) {
        return AppResult.failure(_profileStateFailure(profile));
      }
      if (profile.environment != _services.environment) {
        return AppResult.failure(_networkMismatchFailure());
      }
      if (_snapshot.phase == WalletRuntimePhase.active &&
          _activeProfile?.id == profile.id) {
        return const AppResult.success(null);
      }
      final secretResult = await _secrets.read(
        profile.id,
        expectedStorageToken: profile.storageToken,
      );
      return switch (secretResult) {
        AppSuccess<WalletSecret>(:final value) => _activateReplacingUnsafe(
          profile,
          value,
          activation: const _OpenPersistedWalletActivation(),
        ),
        AppFailureResult<WalletSecret>(:final failure) => AppResult.failure(
          failure,
        ),
      };
    }, reconciliationWalletId: profile.id);
  }

  Future<AppResult<T>> run<T>(
    Future<T> Function(WalletEngine engine) operation,
  ) {
    return _enqueue(() async {
      final engine = _engine;
      if (engine == null || _snapshot.phase != WalletRuntimePhase.active) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_not_ready',
            kind: AppFailureKind.authentication,
            userMessage: 'Open a wallet before continuing.',
            retryable: false,
          ),
        );
      }
      try {
        return AppResult.success(await operation(engine));
      } catch (error, stackTrace) {
        return AppResult.failure(FailureMapper.from(error, stackTrace));
      }
    });
  }

  Future<AppResult<void>> sync() => run((engine) => engine.sync());

  Future<AppResult<void>> suspend() {
    return _enqueue(() async {
      final engine = _engine;
      if (_snapshot.phase == WalletRuntimePhase.suspended ||
          _snapshot.phase == WalletRuntimePhase.inactive) {
        return const AppResult.success(null);
      }
      if (_snapshot.phase == WalletRuntimePhase.failed) {
        return AppResult.failure(
          _snapshot.failure ??
              const AppFailure(
                code: 'wallet_runtime_failed',
                kind: AppFailureKind.conflict,
                userMessage: 'The wallet must be reopened before continuing.',
                retryable: true,
              ),
        );
      }
      if (engine == null || _snapshot.phase != WalletRuntimePhase.active) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_suspend_invalid_state',
            kind: AppFailureKind.conflict,
            userMessage: 'The wallet cannot be suspended in its current state.',
            retryable: false,
          ),
        );
      }
      try {
        await engine.shutdown();
        _emit(
          WalletRuntimeSnapshot(
            phase: WalletRuntimePhase.suspended,
            walletId: _activeProfile?.id,
          ),
        );
        return const AppResult.success(null);
      } catch (error, stackTrace) {
        return _runtimeFailure(error, stackTrace, walletId: _activeProfile?.id);
      }
    });
  }

  Future<AppResult<void>> resume() {
    return _enqueue(() async {
      if (_snapshot case WalletRuntimeSnapshot(
        phase: WalletRuntimePhase.failed,
        failure: final failure?,
      )) {
        return AppResult.failure(failure);
      }
      final engine = _engine;
      final profile = _activeProfile;
      if (engine == null || profile == null) {
        if (_snapshot.phase == WalletRuntimePhase.inactive) {
          return const AppResult.success(null);
        }
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_resume_invalid_state',
            kind: AppFailureKind.conflict,
            userMessage: 'The wallet must be reopened before continuing.',
            retryable: true,
          ),
        );
      }
      if (_snapshot.phase == WalletRuntimePhase.active) {
        return const AppResult.success(null);
      }
      if (_snapshot.phase != WalletRuntimePhase.suspended) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_resume_invalid_state',
            kind: AppFailureKind.conflict,
            userMessage: 'The wallet must be reopened before continuing.',
            retryable: true,
          ),
        );
      }
      final secretResult = await _secrets.read(
        profile.id,
        expectedStorageToken: profile.storageToken,
      );
      if (secretResult case AppFailureResult<WalletSecret>(:final failure)) {
        return AppResult.failure(failure);
      }
      final secret = (secretResult as AppSuccess<WalletSecret>).value;
      _emit(
        WalletRuntimeSnapshot(
          phase: WalletRuntimePhase.activating,
          walletId: profile.id,
        ),
      );
      try {
        await engine.openPersisted(databasePassword: secret.databasePassword);
        _emit(
          WalletRuntimeSnapshot(
            phase: WalletRuntimePhase.active,
            walletId: profile.id,
          ),
        );
        return const AppResult.success(null);
      } catch (error, stackTrace) {
        final reopenFailure = FailureMapper.from(error, stackTrace);
        final cleanup = await _destroyCurrentUnsafe();
        if (cleanup case AppFailureResult<void>(:final failure)) {
          final combined = AppFailure(
            code: 'wallet_resume_cleanup_failed',
            kind: AppFailureKind.storage,
            userMessage: 'The wallet could not be reopened or cleaned up.',
            retryable: false,
            requiresReconciliation: true,
            outcomeUnknown:
                reopenFailure.outcomeUnknown || failure.outcomeUnknown,
            cause: <Object>[reopenFailure, failure],
            stackTrace: stackTrace,
          );
          _emit(
            WalletRuntimeSnapshot(
              phase: WalletRuntimePhase.failed,
              walletId: profile.id,
              failure: combined,
            ),
          );
          return AppResult.failure(combined);
        }
        final recovery = await _activateUnsafe(
          profile,
          secret,
          activation: const _OpenPersistedWalletActivation(),
        );
        if (recovery is AppSuccess<void>) return recovery;
        final recoveryFailure = (recovery as AppFailureResult<void>).failure;
        final outcomeUnknown =
            reopenFailure.outcomeUnknown || recoveryFailure.outcomeUnknown;
        final requiresReconciliation =
            reopenFailure.requiresReconciliation ||
            recoveryFailure.requiresReconciliation;
        final combined = AppFailure(
          code: 'wallet_resume_recovery_failed',
          kind: AppFailureKind.unavailable,
          userMessage: requiresReconciliation
              ? 'The wallet state could not be confirmed. Restart the app '
                    'before continuing.'
              : 'The wallet could not be reopened. Try again.',
          retryable: !requiresReconciliation,
          requiresReconciliation: requiresReconciliation,
          outcomeUnknown: outcomeUnknown,
          cause: <AppFailure>[reopenFailure, recoveryFailure],
          stackTrace: stackTrace,
        );
        _emit(
          WalletRuntimeSnapshot(
            phase: WalletRuntimePhase.failed,
            walletId: profile.id,
            failure: combined,
          ),
        );
        return AppResult.failure(combined);
      }
    });
  }

  Future<AppResult<String>> recoveryMnemonic(String walletId) {
    return _enqueue(() async {
      if (_activeProfile?.id != walletId) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_not_active',
            kind: AppFailureKind.conflict,
            userMessage: 'Select this wallet before checking its seed phrase.',
            retryable: false,
          ),
        );
      }
      if (_snapshot.phase != WalletRuntimePhase.active) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_not_ready',
            kind: AppFailureKind.conflict,
            userMessage: 'Open the wallet before checking its seed phrase.',
            retryable: true,
          ),
        );
      }
      final activeProfile = _activeProfile!;
      final result = await _secrets.read(
        walletId,
        expectedStorageToken: activeProfile.storageToken,
      );
      return switch (result) {
        AppSuccess<WalletSecret>(:final value) => AppResult.success(
          value.mnemonic,
        ),
        AppFailureResult<WalletSecret>(:final failure) => AppResult.failure(
          failure,
        ),
      };
    });
  }

  Future<AppResult<void>> rollbackProvision(
    String walletId, {
    required String storageToken,
  }) {
    return _enqueue(
      () async {
        final failures = <AppFailure>[];
        if (_activeProfile?.id == walletId) {
          final destroy = await _destroyCurrentUnsafe();
          if (destroy case AppFailureResult<void>(:final failure)) {
            return AppResult.failure(
              AppFailure(
                code: 'wallet_rollback_failed',
                kind: AppFailureKind.storage,
                userMessage: 'Local wallet cleanup did not complete.',
                retryable: false,
                requiresReconciliation: true,
                outcomeUnknown: failure.outcomeUnknown,
                cause: failure,
              ),
            );
          }
        }
        final secret = await _secrets.delete(
          walletId,
          storageToken: storageToken,
        );
        if (secret case AppFailureResult<void>(:final failure)) {
          return AppResult.failure(
            AppFailure(
              code: 'wallet_rollback_failed',
              kind: AppFailureKind.storage,
              userMessage: 'Local wallet cleanup did not complete.',
              retryable: false,
              requiresReconciliation: true,
              outcomeUnknown: failure.outcomeUnknown,
              cause: failure,
            ),
          );
        }
        try {
          await _directories.remove(walletId, storageToken: storageToken);
        } catch (error, stackTrace) {
          failures.add(FailureMapper.from(error, stackTrace));
        }
        if (failures.isNotEmpty) {
          return AppResult.failure(
            AppFailure(
              code: 'wallet_rollback_failed',
              kind: AppFailureKind.storage,
              userMessage: 'Local wallet cleanup did not complete.',
              retryable: false,
              requiresReconciliation: true,
              outcomeUnknown: failures.any((failure) => failure.outcomeUnknown),
              cause: List<AppFailure>.unmodifiable(failures),
            ),
          );
        }
        return const AppResult.success(null);
      },
      reconciliationAccess: _ReconciliationAccess.rollback,
      reconciliationWalletId: walletId,
      reconciliationRollbackWalletId: walletId,
    );
  }

  /// Reconciles durable registry ownership against directories and secrets.
  ///
  /// Extra or missing resources are preserved for explicit recovery; this
  /// method never guesses ownership or performs destructive cleanup.
  Future<AppResult<void>> verifyStorage(List<WalletProfile> profiles) {
    return _enqueue(() async {
      try {
        final expectedIds = profiles.map((profile) => profile.id).toSet();
        final directoryIds = await _directories.walletIds();
        final secretIdsResult = await _secrets.walletIds();
        if (secretIdsResult case AppFailureResult<Set<String>>(
          :final failure,
        )) {
          return AppResult.failure(failure);
        }
        final secretIds = (secretIdsResult as AppSuccess<Set<String>>).value;
        if (!_sameIds(expectedIds, directoryIds) ||
            !_sameIds(expectedIds, secretIds)) {
          return AppResult.failure(_storageRecoveryFailure());
        }
        for (final profile in profiles) {
          await _directories.open(
            profile.id,
            storageToken: profile.storageToken,
          );
          final secret = await _secrets.verify(
            profile.id,
            expectedStorageToken: profile.storageToken,
          );
          if (secret case AppFailureResult<void>(:final failure)) {
            return AppResult.failure(failure);
          }
        }
        return const AppResult.success(null);
      } catch (error, stackTrace) {
        return AppResult.failure(
          FailureMapper.from(
            error,
            stackTrace,
            fallbackCode: 'wallet_storage_audit_failed',
          ),
        );
      }
    }, reconciliationAccess: _ReconciliationAccess.audit);
  }

  Future<AppResult<void>> dispose() {
    final inFlight = _disposeInFlight;
    if (inFlight != null) return inFlight;
    _disposing = true;
    final disposal = _enqueue(
      () async {
        final result = await _destroyCurrentUnsafe();
        if (result is AppFailureResult<void>) return result;
        _emit(const WalletRuntimeSnapshot(phase: WalletRuntimePhase.disposed));
        await _states.close();
        return result;
      },
      allowDisposing: true,
      reconciliationAccess: _ReconciliationAccess.disposal,
    );
    _disposeInFlight = disposal;
    unawaited(
      disposal.then((result) {
        if (result is AppFailureResult<void>) {
          _disposing = false;
          _disposeInFlight = null;
        }
      }),
    );
    return disposal;
  }

  Future<AppResult<void>> _activateReplacingUnsafe(
    WalletProfile profile,
    WalletSecret secret, {
    required _WalletActivation activation,
  }) async {
    if (profile.environment != _services.environment) {
      return AppResult.failure(_networkMismatchFailure());
    }

    final previousProfile = _activeProfile;
    WalletSecret? previousSecret;
    if (previousProfile != null && previousProfile.id != profile.id) {
      final previousResult = await _secrets.read(
        previousProfile.id,
        expectedStorageToken: previousProfile.storageToken,
      );
      switch (previousResult) {
        case AppSuccess<WalletSecret>(:final value):
          previousSecret = value;
        case AppFailureResult<WalletSecret>(:final failure):
          if (failure.requiresReconciliation) {
            _emit(
              WalletRuntimeSnapshot(
                phase: WalletRuntimePhase.failed,
                walletId: previousProfile.id,
                failure: failure,
              ),
            );
          }
          return AppResult.failure(failure);
      }
    }

    final destroy = await _destroyCurrentUnsafe();
    if (destroy is AppFailureResult<void>) return destroy;
    final activationResult = await _activateUnsafe(
      profile,
      secret,
      activation: activation,
    );
    if (activationResult is AppSuccess<void> ||
        previousProfile == null ||
        previousSecret == null) {
      return activationResult;
    }

    if (_engine != null) return activationResult;

    final rollback = await _activateUnsafe(
      previousProfile,
      previousSecret,
      activation: const _OpenPersistedWalletActivation(),
    );
    if (rollback is AppFailureResult<void>) {
      final activationFailure =
          (activationResult as AppFailureResult<void>).failure;
      final failure = AppFailure(
        code: 'wallet_switch_rollback_failed',
        kind: AppFailureKind.storage,
        userMessage: 'Neither wallet could be opened safely.',
        retryable: false,
        requiresReconciliation: true,
        outcomeUnknown:
            activationFailure.outcomeUnknown || rollback.failure.outcomeUnknown,
        cause: <Object>[activationResult, rollback],
      );
      _emit(
        WalletRuntimeSnapshot(
          phase: WalletRuntimePhase.failed,
          failure: failure,
        ),
      );
      return AppResult.failure(failure);
    }
    return activationResult;
  }

  Future<AppResult<void>> _activateUnsafe(
    WalletProfile profile,
    WalletSecret secret, {
    required _WalletActivation activation,
  }) async {
    _emit(
      WalletRuntimeSnapshot(
        phase: WalletRuntimePhase.activating,
        walletId: profile.id,
      ),
    );
    WalletEngine? candidate;
    try {
      final String resolvedStorageDirectory;
      switch (activation) {
        case _ProvisionWalletActivation(:final storageDirectory):
          resolvedStorageDirectory = storageDirectory;
        case _OpenPersistedWalletActivation():
          resolvedStorageDirectory = await _directories.open(
            profile.id,
            storageToken: profile.storageToken,
          );
      }
      candidate = _engineFactory.create(
        WalletEngineConfiguration(
          storageDirectory: resolvedStorageDirectory,
          services: _services,
        ),
      );
      switch (activation) {
        case _ProvisionWalletActivation(:final mnemonic):
          await candidate.provision(
            databasePassword: secret.databasePassword,
            mnemonic: mnemonic,
          );
        case _OpenPersistedWalletActivation():
          await candidate.openPersisted(
            databasePassword: secret.databasePassword,
          );
      }
      _engine = candidate;
      _activeProfile = profile.state == WalletProfileState.provisioning
          ? profile.copyWith(state: WalletProfileState.ready)
          : profile;
      _emit(
        WalletRuntimeSnapshot(
          phase: WalletRuntimePhase.active,
          walletId: profile.id,
        ),
      );
      return const AppResult.success(null);
    } catch (error, stackTrace) {
      final activationFailure = FailureMapper.from(error, stackTrace);
      AppFailure? cleanupFailure;
      if (candidate != null) {
        try {
          await candidate.destroy();
        } catch (cleanupError, cleanupStackTrace) {
          cleanupFailure = FailureMapper.from(cleanupError, cleanupStackTrace);
          _engine = candidate;
          _activeProfile = profile;
        }
      }
      if (cleanupFailure != null) {
        final failure = AppFailure(
          code: 'wallet_activation_cleanup_failed',
          kind: AppFailureKind.storage,
          userMessage: 'The wallet could not be opened or cleaned up safely.',
          retryable: false,
          requiresReconciliation: true,
          outcomeUnknown:
              activationFailure.outcomeUnknown || cleanupFailure.outcomeUnknown,
          cause: <AppFailure>[activationFailure, cleanupFailure],
          stackTrace: stackTrace,
        );
        _emit(
          WalletRuntimeSnapshot(
            phase: WalletRuntimePhase.failed,
            walletId: profile.id,
            failure: failure,
          ),
        );
        return AppResult.failure(failure);
      }
      _engine = null;
      _activeProfile = null;
      _emit(
        WalletRuntimeSnapshot(
          phase: WalletRuntimePhase.failed,
          walletId: profile.id,
          failure: activationFailure,
        ),
      );
      return AppResult.failure(activationFailure);
    }
  }

  Future<AppResult<void>> _destroyCurrentUnsafe() async {
    final engine = _engine;
    if (engine == null) {
      _activeProfile = null;
      return const AppResult.success(null);
    }
    try {
      await engine.destroy();
      _engine = null;
      _activeProfile = null;
      _emit(const WalletRuntimeSnapshot(phase: WalletRuntimePhase.inactive));
      return const AppResult.success(null);
    } catch (error, stackTrace) {
      final cause = FailureMapper.from(error, stackTrace);
      final failure = AppFailure(
        code: 'wallet_native_cleanup_failed',
        kind: AppFailureKind.storage,
        userMessage:
            'The wallet could not be closed safely. Restart the app before '
            'continuing.',
        retryable: false,
        requiresReconciliation: true,
        outcomeUnknown: cause.outcomeUnknown,
        cause: cause,
        stackTrace: stackTrace,
      );
      _emit(
        WalletRuntimeSnapshot(
          phase: WalletRuntimePhase.failed,
          walletId: _activeProfile?.id,
          failure: failure,
        ),
      );
      return AppResult.failure(failure);
    }
  }

  AppResult<void> _runtimeFailure(
    Object error,
    StackTrace stackTrace, {
    String? walletId,
  }) {
    final failure = FailureMapper.from(error, stackTrace);
    _emit(
      WalletRuntimeSnapshot(
        phase: WalletRuntimePhase.failed,
        walletId: walletId,
        failure: failure,
      ),
    );
    return AppResult.failure(failure);
  }

  static AppFailure _profileStateFailure(WalletProfile profile) {
    return AppFailure(
      code: 'wallet_profile_state_invalid',
      kind: AppFailureKind.conflict,
      userMessage: 'Wallet setup has not reached a usable state.',
      retryable: false,
      cause: profile.state,
    );
  }

  static AppFailure _networkMismatchFailure() => const AppFailure(
    code: 'wallet_network_mismatch',
    kind: AppFailureKind.configuration,
    userMessage: 'This wallet belongs to a different network.',
    retryable: false,
  );

  static bool _sameIds(Set<String> expected, Set<String> actual) =>
      expected.length == actual.length && expected.containsAll(actual);

  static AppFailure _storageRecoveryFailure() => const AppFailure(
    code: 'wallet_storage_recovery_required',
    kind: AppFailureKind.storage,
    userMessage:
        'Stored wallet resources do not match. Recover the wallet before '
        'continuing.',
    retryable: false,
    requiresReconciliation: true,
  );

  static AppFailure _provisionRollbackFailure(
    AppResult<void> activation,
    List<AppFailure> cleanupFailures,
  ) {
    final activationUnknown = switch (activation) {
      AppFailureResult<void>(:final failure) => failure.outcomeUnknown,
      AppSuccess<void>() => false,
    };
    return AppFailure(
      code: 'wallet_provision_rollback_failed',
      kind: AppFailureKind.storage,
      userMessage: 'Wallet setup failed and local cleanup needs attention.',
      retryable: false,
      requiresReconciliation: true,
      outcomeUnknown:
          activationUnknown ||
          cleanupFailures.any((failure) => failure.outcomeUnknown),
      cause: <Object>[activation, ...cleanupFailures],
    );
  }

  void _emit(WalletRuntimeSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_states.isClosed) _states.add(snapshot);
  }

  Future<AppResult<T>> _enqueue<T>(
    Future<AppResult<T>> Function() operation, {
    bool allowDisposing = false,
    _ReconciliationAccess reconciliationAccess = _ReconciliationAccess.blocked,
    String? reconciliationWalletId,
    String? reconciliationRollbackWalletId,
  }) {
    if ((_disposing && !allowDisposing) ||
        _snapshot.phase == WalletRuntimePhase.disposed) {
      return Future<AppResult<T>>.value(
        AppResult.failure(
          const AppFailure(
            code: 'wallet_runtime_disposed',
            kind: AppFailureKind.conflict,
            userMessage: 'The wallet is closed. Restart the app to continue.',
            retryable: false,
          ),
        ),
      );
    }
    final completer = Completer<AppResult<T>>();
    _tail = _tail.then((_) async {
      // Check inside the queue so work scheduled before a failing operation
      // cannot begin after that operation establishes reconciliation state.
      final retainedSnapshot = switch (_snapshot) {
        final snapshot
            when snapshot.phase == WalletRuntimePhase.failed &&
                snapshot.failure?.requiresReconciliation == true =>
          snapshot,
        _ => null,
      };
      final retainedFailure = retainedSnapshot?.failure;
      if (retainedFailure != null) {
        final canRun = switch (reconciliationAccess) {
          _ReconciliationAccess.blocked => false,
          _ReconciliationAccess.audit || _ReconciliationAccess.disposal => true,
          _ReconciliationAccess.rollback =>
            _reconciliationRollbackWalletId != null &&
                _reconciliationRollbackWalletId ==
                    reconciliationRollbackWalletId,
        };
        if (!canRun) {
          completer.complete(AppResult.failure(retainedFailure));
          return;
        }
      }
      try {
        final result = await operation();
        _settleReconciliation(
          result,
          retainedSnapshot: retainedSnapshot,
          access: reconciliationAccess,
          reconciliationWalletId: reconciliationWalletId,
          reconciliationRollbackWalletId: reconciliationRollbackWalletId,
        );
        completer.complete(result);
      } catch (error, stackTrace) {
        final result = AppResult<T>.failure(
          FailureMapper.from(error, stackTrace),
        );
        _settleReconciliation(
          result,
          retainedSnapshot: retainedSnapshot,
          access: reconciliationAccess,
          reconciliationWalletId: reconciliationWalletId,
          reconciliationRollbackWalletId: reconciliationRollbackWalletId,
        );
        completer.complete(result);
      }
    });
    return completer.future;
  }

  /// Retains the first public failure until its owned recovery completes.
  void _settleReconciliation<T>(
    AppResult<T> result, {
    required WalletRuntimeSnapshot? retainedSnapshot,
    required _ReconciliationAccess access,
    required String? reconciliationWalletId,
    required String? reconciliationRollbackWalletId,
  }) {
    if (retainedSnapshot != null) {
      if (result is AppSuccess<T> &&
          (access == _ReconciliationAccess.rollback ||
              access == _ReconciliationAccess.disposal)) {
        _reconciliationRollbackWalletId = null;
        if (access == _ReconciliationAccess.rollback) {
          _emit(
            _engine != null && _activeProfile != null
                ? WalletRuntimeSnapshot(
                    phase: WalletRuntimePhase.active,
                    walletId: _activeProfile!.id,
                  )
                : const WalletRuntimeSnapshot(
                    phase: WalletRuntimePhase.inactive,
                  ),
          );
        }
        return;
      }

      // Audit and failed recovery attempts may return their own diagnostics,
      // but they cannot replace the failure that established quarantine.
      if (!identical(_snapshot, retainedSnapshot)) _emit(retainedSnapshot);
      return;
    }

    if (result case AppFailureResult<T>(:final failure)
        when failure.requiresReconciliation) {
      _reconciliationRollbackWalletId = reconciliationRollbackWalletId;
      _emit(
        WalletRuntimeSnapshot(
          phase: WalletRuntimePhase.failed,
          walletId:
              (_snapshot.phase == WalletRuntimePhase.failed
                  ? _snapshot.walletId
                  : null) ??
              reconciliationWalletId ??
              _activeProfile?.id ??
              _snapshot.walletId,
          failure: failure,
        ),
      );
    }
  }
}
