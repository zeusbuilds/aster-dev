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
/// ordered even when multiple ViewModels issue work concurrently.
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
        ),
        AppFailureResult<WalletSecret>(:final failure) => AppResult.failure(
          failure,
        ),
      };
    });
  }

  Future<AppResult<void>> provision({
    required WalletProfile profile,
    required String mnemonic,
    required String databasePassword,
  }) {
    return _enqueue(() async {
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
              outcomeUnknown: true,
              cause: failure,
            ),
          );
        }
        try {
          await _directories.remove(profile.id, storageToken: storageToken);
          return AppResult.failure(failure);
        } catch (cleanupError, cleanupStackTrace) {
          return AppResult.failure(
            AppFailure(
              code: 'wallet_provision_rollback_failed',
              kind: AppFailureKind.storage,
              userMessage:
                  'Wallet setup failed and local cleanup needs attention.',
              retryable: false,
              cause: <Object>[
                failure,
                FailureMapper.from(cleanupError, cleanupStackTrace),
              ],
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
        initializeMnemonic: mnemonic,
        storageDirectory: storageDirectory,
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
        final failure = _provisionRollbackFailure(activation, cleanupFailures);
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
    });
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
        ),
        AppFailureResult<WalletSecret>(:final failure) => AppResult.failure(
          failure,
        ),
      };
    });
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
        await engine.reinitialize(databasePassword: secret.databasePassword);
        _emit(
          WalletRuntimeSnapshot(
            phase: WalletRuntimePhase.active,
            walletId: profile.id,
          ),
        );
        return const AppResult.success(null);
      } catch (error, stackTrace) {
        final reinitializeFailure = FailureMapper.from(error, stackTrace);
        final cleanup = await _destroyCurrentUnsafe();
        if (cleanup case AppFailureResult<void>(:final failure)) {
          final combined = AppFailure(
            code: 'wallet_resume_cleanup_failed',
            kind: AppFailureKind.storage,
            userMessage: 'The wallet could not be reopened or cleaned up.',
            retryable: false,
            outcomeUnknown:
                reinitializeFailure.outcomeUnknown || failure.outcomeUnknown,
            cause: <Object>[reinitializeFailure, failure],
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
        final recovery = await _activateUnsafe(profile, secret);
        if (recovery is AppSuccess<void>) return recovery;
        final recoveryFailure = (recovery as AppFailureResult<void>).failure;
        final combined = AppFailure(
          code: 'wallet_resume_recovery_failed',
          kind: AppFailureKind.unavailable,
          userMessage: 'The wallet could not be reopened. Try again.',
          retryable: !recoveryFailure.outcomeUnknown,
          outcomeUnknown:
              reinitializeFailure.outcomeUnknown ||
              recoveryFailure.outcomeUnknown,
          cause: <Object>[reinitializeFailure, recovery],
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
    return _enqueue(() async {
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
            cause: List<AppFailure>.unmodifiable(failures),
          ),
        );
      }
      return const AppResult.success(null);
    });
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
    });
  }

  Future<AppResult<void>> dispose() {
    final inFlight = _disposeInFlight;
    if (inFlight != null) return inFlight;
    _disposing = true;
    final disposal = _enqueue(() async {
      final result = await _destroyCurrentUnsafe();
      if (result is AppFailureResult<void>) return result;
      _emit(const WalletRuntimeSnapshot(phase: WalletRuntimePhase.disposed));
      await _states.close();
      return result;
    }, allowDisposing: true);
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
    String? initializeMnemonic,
    String? storageDirectory,
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
          return AppResult.failure(failure);
      }
    }

    final destroy = await _destroyCurrentUnsafe();
    if (destroy is AppFailureResult<void>) return destroy;
    final activation = await _activateUnsafe(
      profile,
      secret,
      initializeMnemonic: initializeMnemonic,
      storageDirectory: storageDirectory,
    );
    if (activation is AppSuccess<void> ||
        previousProfile == null ||
        previousSecret == null) {
      return activation;
    }

    if (_engine != null) return activation;

    final rollback = await _activateUnsafe(previousProfile, previousSecret);
    if (rollback is AppFailureResult<void>) {
      final activationFailure = (activation as AppFailureResult<void>).failure;
      final failure = AppFailure(
        code: 'wallet_switch_rollback_failed',
        kind: AppFailureKind.storage,
        userMessage: 'Neither wallet could be opened safely.',
        retryable: false,
        outcomeUnknown:
            activationFailure.outcomeUnknown || rollback.failure.outcomeUnknown,
        cause: <Object>[activation, rollback],
      );
      _emit(
        WalletRuntimeSnapshot(
          phase: WalletRuntimePhase.failed,
          failure: failure,
        ),
      );
      return AppResult.failure(failure);
    }
    return activation;
  }

  Future<AppResult<void>> _activateUnsafe(
    WalletProfile profile,
    WalletSecret secret, {
    String? initializeMnemonic,
    String? storageDirectory,
  }) async {
    _emit(
      WalletRuntimeSnapshot(
        phase: WalletRuntimePhase.activating,
        walletId: profile.id,
      ),
    );
    WalletEngine? candidate;
    try {
      final resolvedStorageDirectory =
          storageDirectory ??
          await _directories.open(
            profile.id,
            storageToken: profile.storageToken,
          );
      candidate = _engineFactory.create(
        WalletEngineConfiguration(
          storageDirectory: resolvedStorageDirectory,
          services: _services,
        ),
      );
      await candidate.initialize(
        databasePassword: secret.databasePassword,
        mnemonic: initializeMnemonic,
      );
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
      return _runtimeFailure(error, stackTrace, walletId: _activeProfile?.id);
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
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.complete(
          AppResult.failure(FailureMapper.from(error, stackTrace)),
        );
      }
    });
    return completer.future;
  }
}
