import 'dart:async';

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/errors.dart';
import '../../../../core/security/security_controller.dart';
import '../../domain/models/models.dart';
import '../runtime/runtime.dart';
import '../storage/storage.dart';
import '../validation/validation.dart';
import 'wallet_lifecycle_repository.dart';
import 'wallet_payment_operations.dart';
import 'wallet_payment_submissions.dart';
import 'wallet_rgb_setup_operations.dart';

/// Coordinates wallet metadata transactions and the single native runtime.
///
/// The repository never exposes SDK DTOs or credential records. Mutations are
/// first staged durably, then marked ready only after native initialization
/// succeeds. Rollback failures remain durable for startup recovery.
final class WalletRepository implements WalletLifecycleRepository {
  WalletRepository(
    this._profiles,
    this._runtime,
    this._keyGenerator,
    this._identityGenerator,
    this._services, {
    this._bitcoinInstructions = const BitcoinPaymentInstructionParser(),
    DateTime Function()? clock,
    this.rgbSetupStore,
    this.paymentJournalStore,
    this.paymentReceiptStore,
    this.securityController,
  }) : _clock = clock ?? _utcNow {
    _services.validate();
  }

  final WalletProfilePersistence _profiles;
  final WalletRuntime _runtime;
  final WalletKeyGenerator _keyGenerator;
  final WalletIdentityGenerator _identityGenerator;
  final WalletServiceConfiguration _services;
  final BitcoinPaymentInstructionDecoder _bitcoinInstructions;
  final DateTime Function() _clock;
  final RgbWalletSetupStore? rgbSetupStore;
  final WalletPaymentJournalStore? paymentJournalStore;
  final WalletPaymentReceiptStore? paymentReceiptStore;
  final SecurityController? securityController;
  late final WalletPaymentSubmissions _submissions = WalletPaymentSubmissions(
    _runtime,
    paymentJournalStore,
    receipts:
        paymentReceiptStore ??
        (paymentJournalStore is WalletPaymentReceiptStore
            ? paymentJournalStore as WalletPaymentReceiptStore
            : null),
    newId: _identityGenerator.newStorageToken,
    clock: _clock,
  );
  late final WalletRgbSetupOperations _rgbSetup = WalletRgbSetupOperations(
    _runtime,
    _profiles,
    _services,
    rgbSetupStore,
    newId: _identityGenerator.newStorageToken,
    clock: _clock,
  );
  Future<void> _operationTail = Future<void>.value();
  late final WalletPaymentOperations _payments = WalletPaymentOperations(
    _runtime,
    _services,
    _bitcoinInstructions,
    _enqueueOperation,
    beforeOnchainMutation: _assertOnchainMutationResolved,
    captureAccessGuard: _captureAccessGuard,
    submissions: _submissions,
    clock: _clock,
  );

  /// Balanced confirmation target used until product fee selection exists.
  static const standardFeeTargetBlocks =
      WalletPaymentOperations.standardFeeTargetBlocks;

  Future<AppResult<WalletRegistry>> load() =>
      _enqueueOperation(_profiles.read, requiresUnlocked: false);

  Future<AppResult<RgbWalletSetupReview>> prepareRgbWalletSetup() =>
      _enqueueOperation(() async {
        final gate = await _submissions.assertResolved();
        if (gate case AppFailureResult<void>(:final failure)) {
          return AppResult.failure(failure);
        }
        return _rgbSetup.prepare();
      });
  Future<AppResult<void>> cancelRgbWalletSetup(RgbWalletSetupReview review) =>
      _enqueueOperation(() => _rgbSetup.cancel(review));
  Future<AppResult<RgbWalletSetupStatus>> confirmRgbWalletSetup(
    RgbWalletSetupReview review,
  ) => _enqueueOperation(() async {
    final gate = await _submissions.assertResolved();
    if (gate case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(failure);
    }
    return _rgbSetup.confirm(review);
  });
  Future<AppResult<RgbWalletSetupStatus>> rgbWalletSetupStatus() =>
      _enqueueOperation(_rgbSetup.status);

  /// Product payment targets and whether this deployment can execute them.
  ///
  /// Bitcoin is always identified by the protocol. RGB USDT remains visible
  /// but unavailable until its environment-specific contract metadata exists.
  List<WalletPaymentCapability> get paymentCapabilities =>
      _payments.capabilities;

  /// Resolves an untrusted route identifier to deployment-owned asset data.
  AppResult<PaymentRoute> resolvePaymentTarget(WalletPaymentTarget target) =>
      _payments.resolveTarget(target);

  /// Restores the persisted active wallet during app bootstrap.
  Future<AppResult<WalletRegistry>> bootstrap() {
    return _enqueueOperation(_bootstrapUnsafe);
  }

  /// Resumes only persisted deletion authority, then restores the surviving
  /// selection. Does not ask for another delete grant or invent a new deletion.
  Future<AppResult<WalletRegistry>> recoverWalletDeletion() =>
      _enqueueOperation(_bootstrapUnsafe);

  Future<AppResult<WalletRegistry>> _bootstrapUnsafe() async {
    final registryResult = await _profiles.read();
    if (registryResult case AppFailureResult<WalletRegistry>()) {
      return registryResult;
    }
    var registry = (registryResult as AppSuccess<WalletRegistry>).value;
    final resumingDeletion = registry.deletingProfiles.isNotEmpty;
    // Deletion authority was committed before any resource was removed. Finish
    // only those exact records; never infer deletions from missing native data.
    for (final deleting in registry.deletingProfiles) {
      final cleanup = await _finishWalletDeletionUnsafe(deleting);
      if (cleanup case AppFailureResult<WalletRegistry>()) return cleanup;
      registry = (cleanup as AppSuccess<WalletRegistry>).value;
    }
    for (final pending in registry.provisioningProfiles) {
      final cleanup = await _runtime.rollbackProvision(
        pending.id,
        storageToken: pending.storageToken,
      );
      if (cleanup case AppFailureResult<void>(:final failure)) {
        return AppResult.failure(
          AppFailure(
            code: 'wallet_pending_recovery_failed',
            kind: AppFailureKind.storage,
            userMessage:
                'An interrupted wallet setup could not be cleaned up safely.',
            retryable: false,
            requiresReconciliation: true,
            outcomeUnknown: failure.outcomeUnknown,
            cause: failure,
          ),
        );
      }
      final removal = await _profiles.remove(pending.id);
      if (removal case AppFailureResult<WalletRegistry>(:final failure)) {
        return AppResult.failure(
          AppFailure(
            code: 'wallet_pending_registry_cleanup_failed',
            kind: AppFailureKind.storage,
            userMessage:
                'An interrupted wallet setup could not be cleaned up safely.',
            retryable: false,
            requiresReconciliation: true,
            outcomeUnknown: failure.outcomeUnknown,
            cause: failure,
          ),
        );
      }
      registry = (removal as AppSuccess<WalletRegistry>).value;
    }
    await _submissions.validateProfiles(registry.readyProfiles);
    final storageAudit = await _runtime.verifyStorage(registry.readyProfiles);
    if (storageAudit case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(failure);
    }
    final recoveredDeletion = await _runtime.recoverDeletionOwnership();
    if (recoveredDeletion case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(failure);
    }
    final active = registry.activeProfile;
    if (active == null) return AppResult.success(registry);
    final restore = await _runtime.restore(active);
    final result = restore is AppSuccess<void>
        ? await _restorePaymentFenceUnsafe()
        : restore;
    return switch (result) {
      AppSuccess<void>() => AppResult.success(registry),
      AppFailureResult<void>(:final failure)
          when resumingDeletion && failure.retryable =>
        AppResult.failure(
          _deletionRecoveryFailure(cause: failure, committed: true),
        ),
      AppFailureResult<void>(:final failure) => AppResult.failure(failure),
    };
  }

  Future<AppResult<String>> generateMnemonic() {
    return _enqueueOperation(_generateMnemonicUnsafe);
  }

  /// Validates a normalized 12-word phrase through the SDK's BIP39 checksum
  /// implementation. Per-word UI feedback does not replace this authority.
  Future<AppResult<void>> validateMnemonic(String mnemonic) {
    return _enqueueOperation(() => _validateMnemonicUnsafe(mnemonic));
  }

  Future<AppResult<String>> _generateMnemonicUnsafe() async {
    final String generated;
    try {
      generated = await _keyGenerator.generateMnemonic(_services.environment);
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }

    final normalized = _normalizeMnemonic(generated);
    try {
      if (normalized.split(' ').length != 12) {
        throw const FormatException(
          'Generated recovery phrase did not contain 12 words.',
        );
      }
      await _keyGenerator.validateMnemonic(normalized);
      return AppResult.success(normalized);
    } catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'wallet_mnemonic_generation_invalid',
          kind: AppFailureKind.protocol,
          userMessage: 'A recovery phrase could not be generated safely.',
          retryable: true,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<AppResult<void>> _validateMnemonicUnsafe(String mnemonic) async {
    final normalized = _normalizeMnemonic(mnemonic);
    if (normalized.isEmpty || normalized.split(' ').length != 12) {
      return AppResult.failure(_invalidMnemonicFailure());
    }
    try {
      await _keyGenerator.validateMnemonic(normalized);
      return const AppResult.success(null);
    } catch (error, stackTrace) {
      final mapped = FailureMapper.from(error, stackTrace);
      if (mapped.kind == AppFailureKind.validation) {
        return AppResult.failure(_invalidMnemonicFailure(cause: mapped));
      }
      return AppResult.failure(mapped);
    }
  }

  /// Creates or restores a native wallet from an already user-confirmed
  /// mnemonic and atomically registers its non-secret profile.
  Future<AppResult<WalletRegistry>> createFromMnemonic({
    required String mnemonic,
    required String name,
  }) {
    return _enqueueOperation(
      () => _createFromMnemonicUnsafe(mnemonic: mnemonic, name: name),
    );
  }

  Future<AppResult<WalletRegistry>> _createFromMnemonicUnsafe({
    required String mnemonic,
    required String name,
  }) async {
    final gate = await _submissions.assertResolved();
    if (gate case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(failure);
    }
    final normalizedMnemonic = _normalizeMnemonic(mnemonic);
    final normalizedName = name.trim();
    if (!WalletProfile.isValidName(normalizedName)) {
      return AppResult.failure(
        const AppFailure(
          code: 'wallet_name_invalid',
          kind: AppFailureKind.validation,
          userMessage: 'Enter a wallet name with at most 64 characters.',
          retryable: false,
        ),
      );
    }
    final validation = await _validateMnemonicUnsafe(normalizedMnemonic);
    if (validation case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(failure);
    }

    final beforeResult = await _profiles.read();
    if (beforeResult case AppFailureResult<WalletRegistry>()) {
      return AppResult.failure(beforeResult.failure);
    }
    final before = (beforeResult as AppSuccess<WalletRegistry>).value;
    final existingIds = before.profiles.map((profile) => profile.id).toSet();
    String? walletId;
    try {
      for (var attempt = 0; attempt < 8; attempt += 1) {
        final candidate = _identityGenerator.newWalletId();
        if (!existingIds.contains(candidate)) {
          walletId = candidate;
          break;
        }
      }
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
    if (walletId == null) {
      return AppResult.failure(
        const AppFailure(
          code: 'wallet_id_collision',
          kind: AppFailureKind.conflict,
          userMessage: 'A unique wallet could not be created. Try again.',
          retryable: true,
        ),
      );
    }
    late final String storageToken;
    late final String databasePassword;
    try {
      storageToken = _identityGenerator.newStorageToken();
      databasePassword = _identityGenerator.newDatabasePassword();
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
    late final WalletProfile profile;
    try {
      final now = _clock().toUtc();
      profile = WalletProfile(
        id: walletId,
        name: normalizedName,
        createdAt: now,
        updatedAt: now,
        environment: _services.environment,
        backend: _services.backend,
        signetDeployment: _services.environment == BlockchainEnvironment.signet
            ? _services.signetDeployment
            : null,
        state: WalletProfileState.provisioning,
        storageToken: storageToken,
      );
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
    final staged = await _profiles.stageProvision(profile);
    if (staged case AppFailureResult<WalletRegistry>(:final failure)) {
      return AppResult.failure(failure);
    }

    final provision = await _runtime.provision(
      profile: profile,
      mnemonic: normalizedMnemonic,
      databasePassword: databasePassword,
    );
    if (provision case AppFailureResult<void>(:final failure)) {
      if (failure.requiresReconciliation) {
        return AppResult.failure(failure);
      }
      final removal = await _profiles.remove(profile.id);
      if (removal is AppFailureResult<WalletRegistry>) {
        final removalFailure = removal.failure;
        return AppResult.failure(
          AppFailure(
            code: 'wallet_stage_rollback_failed',
            kind: AppFailureKind.storage,
            userMessage:
                'Wallet setup failed and its transaction record remains.',
            retryable: false,
            requiresReconciliation: true,
            outcomeUnknown:
                failure.outcomeUnknown || removalFailure.outcomeUnknown,
            cause: <Object>[failure, removalFailure],
          ),
        );
      }
      return AppResult.failure(failure);
    }

    final registration = await _profiles.commitProvision(profile.id);
    if (registration case AppSuccess<WalletRegistry>(:final value)) {
      return AppResult.success(value);
    }
    final registrationFailure =
        (registration as AppFailureResult<WalletRegistry>).failure;
    if (registrationFailure.requiresReconciliation) {
      return AppResult.failure(
        await _quarantineAfterCommitFailure(registrationFailure),
      );
    }
    final rollback = await _runtime.rollbackProvision(
      profile.id,
      storageToken: storageToken,
    );
    if (rollback case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(
        AppFailure(
          code: 'wallet_registration_rollback_failed',
          kind: AppFailureKind.storage,
          userMessage:
              'Wallet setup could not be committed or rolled back safely.',
          retryable: false,
          requiresReconciliation: true,
          outcomeUnknown:
              registrationFailure.outcomeUnknown || failure.outcomeUnknown,
          cause: <Object>[registrationFailure, failure],
        ),
      );
    }
    final removal = await _profiles.remove(profile.id);
    final previous = before.activeProfile;
    final restore = previous == null
        ? const AppResult<void>.success(null)
        : await _runtime.restore(previous);
    if (removal is AppFailureResult<WalletRegistry> ||
        restore is AppFailureResult<void>) {
      return AppResult.failure(
        AppFailure(
          code: 'wallet_registration_rollback_failed',
          kind: AppFailureKind.storage,
          userMessage:
              'Wallet setup could not be committed or rolled back safely.',
          retryable: false,
          requiresReconciliation: true,
          outcomeUnknown:
              registrationFailure.outcomeUnknown ||
              _outcomeUnknown(removal) ||
              _outcomeUnknown(restore),
          cause: <Object>[registrationFailure, removal, restore],
        ),
      );
    }
    return AppResult.failure(registrationFailure);
  }

  Future<AppResult<WalletRegistry>> switchWallet(String walletId) {
    return _enqueueOperation(() => _switchWalletUnsafe(walletId));
  }

  /// Removes only the selected wallet from this device. A fresh, wallet-bound
  /// authorization is consumed inside the serialized command. Once its deleting
  /// profile is durable, cleanup must finish even if the app is backgrounded.
  Future<AppResult<WalletRegistry>> deleteWallet(
    String walletId, {
    SensitiveAuthorization? authorization,
  }) {
    final assertAuthorized = _captureAccessGuard();
    return _enqueueOperation(() async {
      final controller = securityController;
      if (controller != null &&
          !controller.consume(
            authorization,
            SecurityPurpose.deleteWallet,
            walletId: walletId,
          )) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_deletion_authentication_required',
            kind: AppFailureKind.authentication,
            userMessage: 'Authenticate again to delete this wallet.',
            retryable: true,
          ),
        );
      }
      final result = await _profiles.read();
      if (result case AppFailureResult<WalletRegistry>(:final failure)) {
        return AppResult.failure(failure);
      }
      final registry = (result as AppSuccess<WalletRegistry>).value;
      final target = registry.readyProfiles
          .where((profile) => profile.id == walletId)
          .firstOrNull;
      if (target == null) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_profile_not_found',
            kind: AppFailureKind.notFound,
            userMessage: 'That wallet is no longer available.',
            retryable: false,
          ),
        );
      }
      if (registry.activeWalletId != walletId ||
          _runtime.activeProfile?.id != walletId) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_deletion_select_wallet',
            kind: AppFailureKind.conflict,
            userMessage: 'Select this wallet before deleting it.',
            retryable: true,
          ),
        );
      }
      if (registry.provisioningProfiles.isNotEmpty ||
          registry.deletingProfiles.isNotEmpty) {
        return AppResult.failure(_deletionRecoveryFailure());
      }
      final profiles = _profiles;
      if (profiles is! WalletDeletionPersistence || !_canRemoveScopedData) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_deletion_unavailable',
            kind: AppFailureKind.storage,
            userMessage: 'Wallet deletion is unavailable. Try again later.',
            retryable: false,
          ),
        );
      }
      final payment = await _submissions.assertWalletDeletionSafe(target);
      if (payment case AppFailureResult<void>(:final failure)) {
        return AppResult.failure(failure);
      }
      final setup = await _rgbSetup.assertWalletDeletionSafe(target);
      if (setup case AppFailureResult<void>(:final failure)) {
        return AppResult.failure(failure);
      }
      assertAuthorized?.call();
      final audit = await _runtime.readPaymentState((engine) async {
        if (engine is! WalletDeletionSafetyEngine) {
          throw const AppFailureException(
            AppFailure(
              code: 'wallet_deletion_audit_unavailable',
              kind: AppFailureKind.protocol,
              userMessage: 'Wallet assets could not be checked. Try again.',
              retryable: true,
            ),
          );
        }
        return (engine as WalletDeletionSafetyEngine).hasProtectedRgbState();
      }, authorize: assertAuthorized);
      if (audit case AppFailureResult<bool>(:final failure)) {
        return AppResult.failure(failure);
      }
      if ((audit as AppSuccess<bool>).value) {
        return AppResult.failure(
          const AppFailure(
            code: 'wallet_deletion_rgb_state_present',
            kind: AppFailureKind.conflict,
            userMessage:
                'Send all USDT/RGB assets and finish pending requests before '
                'deleting this wallet.',
            retryable: false,
          ),
        );
      }
      assertAuthorized?.call();
      final staged = await (profiles as WalletDeletionPersistence)
          .stageDeletion(walletId);
      if (staged case AppFailureResult<WalletRegistry>(:final failure)) {
        // An ambiguous durable commit may already contain the delete marker.
        // Do not reopen or erase anything until bootstrap reads its authority.
        if (failure.requiresReconciliation) {
          final quarantine = await _runtime.quarantineDeletion(target, failure);
          return AppResult.failure(
            quarantine is AppFailureResult<void>
                ? quarantine.failure
                : _deletionRecoveryFailure(cause: failure),
          );
        }
        return AppResult.failure(failure);
      }
      final deleting = (staged as AppSuccess<WalletRegistry>)
          .value
          .deletingProfiles
          .singleWhere((profile) => profile.id == walletId);
      final cleaned = await _finishWalletDeletionUnsafe(deleting);
      if (cleaned case AppFailureResult<WalletRegistry>()) return cleaned;
      final after = (cleaned as AppSuccess<WalletRegistry>).value;
      final next = after.activeProfile;
      if (next != null) {
        final opened = await _runtime.restore(next);
        if (opened case AppFailureResult<void>(:final failure)) {
          return AppResult.failure(
            _deletionRecoveryFailure(cause: failure, committed: true),
          );
        }
        final fence = await _restorePaymentFenceUnsafe();
        if (fence case AppFailureResult<void>(:final failure)) {
          return AppResult.failure(
            _deletionRecoveryFailure(cause: failure, committed: true),
          );
        }
      }
      return AppResult.success(after);
    });
  }

  bool get _canRemoveScopedData => <Object?>[
    paymentJournalStore,
    paymentReceiptStore,
    rgbSetupStore,
  ].every((store) => store == null || store is WalletScopedDataRemoval);

  Future<AppResult<WalletRegistry>> _finishWalletDeletionUnsafe(
    WalletProfile profile,
  ) async {
    if (!_canRemoveScopedData) {
      return AppResult.failure(_deletionRecoveryFailure());
    }
    final removed = await _runtime.deleteWallet(profile);
    if (removed case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(_deletionRecoveryFailure(cause: failure));
    }
    try {
      for (final store in <Object?>{
        paymentJournalStore,
        paymentReceiptStore,
        rgbSetupStore,
      }) {
        if (store is WalletScopedDataRemoval) {
          await store.removeWallet(profile.id);
        }
      }
    } catch (error, stackTrace) {
      return AppResult.failure(
        _deletionRecoveryFailure(cause: FailureMapper.from(error, stackTrace)),
      );
    }
    final result = await _profiles.remove(profile.id);
    if (result case AppFailureResult<WalletRegistry>(:final failure)) {
      return AppResult.failure(_deletionRecoveryFailure(cause: failure));
    }
    _submissions.forgetDeletedWallet(profile.id);
    return result;
  }

  static AppFailure _deletionRecoveryFailure({
    AppFailure? cause,
    bool committed = false,
  }) => AppFailure(
    code: committed
        ? 'wallet_deleted_activation_failed'
        : 'wallet_deletion_incomplete',
    kind: AppFailureKind.storage,
    userMessage: committed
        ? 'Wallet deleted. Try again to open the next wallet.'
        : 'Wallet removal could not finish. Try again to finish it.',
    retryable: false,
    requiresReconciliation: true,
    outcomeUnknown: cause?.outcomeUnknown ?? false,
    cause: cause,
  );

  Future<AppResult<WalletRegistry>> _switchWalletUnsafe(String walletId) async {
    final registryResult = await _profiles.read();
    if (registryResult case AppFailureResult<WalletRegistry>()) {
      return registryResult;
    }
    final registry = (registryResult as AppSuccess<WalletRegistry>).value;
    final target = registry.readyProfiles
        .where((profile) => profile.id == walletId)
        .firstOrNull;
    if (target == null) {
      return AppResult.failure(
        const AppFailure(
          code: 'wallet_profile_not_found',
          kind: AppFailureKind.notFound,
          userMessage: 'That wallet is no longer available.',
          retryable: false,
        ),
      );
    }
    if (registry.activeWalletId == walletId) {
      final activation = await _runtime.switchTo(target);
      if (activation is AppSuccess<void>) {
        final paymentFence = await _restorePaymentFenceUnsafe();
        if (paymentFence case AppFailureResult<void>(:final failure)) {
          return AppResult.failure(failure);
        }
      }
      return switch (activation) {
        AppSuccess<void>() => AppResult.success(registry),
        AppFailureResult<void>(:final failure) => AppResult.failure(failure),
      };
    }
    final activation = await _runtime.switchTo(target);
    if (activation case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(failure);
    }
    final persisted = await _profiles.setActive(walletId);
    if (persisted is AppSuccess<WalletRegistry>) {
      final paymentFence = await _restorePaymentFenceUnsafe();
      if (paymentFence case AppFailureResult<void>(:final failure)) {
        return AppResult.failure(failure);
      }
      return persisted;
    }

    final persistenceFailure =
        (persisted as AppFailureResult<WalletRegistry>).failure;
    if (persistenceFailure.requiresReconciliation) {
      return AppResult.failure(
        await _quarantineAfterCommitFailure(persistenceFailure),
      );
    }

    final previous = registry.activeProfile;
    final rollback = previous == null
        ? const AppResult<void>.success(null)
        : await _runtime.switchTo(previous);
    if (rollback case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(
        AppFailure(
          code: 'wallet_switch_commit_failed',
          kind: AppFailureKind.storage,
          userMessage: 'The selected wallet could not be saved safely.',
          retryable: false,
          requiresReconciliation: true,
          outcomeUnknown:
              persistenceFailure.outcomeUnknown || failure.outcomeUnknown,
          cause: <Object>[persistenceFailure, failure],
        ),
      );
    }
    final paymentFence = await _restorePaymentFenceUnsafe();
    if (paymentFence case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(failure);
    }
    return persisted;
  }

  Future<AppResult<void>> _restorePaymentFenceUnsafe() async {
    try {
      await _submissions.restoreFence();
      return const AppResult.success(null);
    } catch (error, stack) {
      // An unreadable journal must never leave a newly opened engine usable.
      // Its storage may contain an unresolved operation whose fence could not
      // be restored. Close the owner before releasing the repository queue.
      return AppResult.failure(
        await _quarantineAfterCommitFailure(
          AppFailure(
            code: 'wallet_payment_fence_restore_failed',
            kind: AppFailureKind.storage,
            userMessage: 'Wallet payment records could not be read safely.',
            retryable: false,
            requiresReconciliation: true,
            cause: FailureMapper.from(error, stack),
            stackTrace: stack,
          ),
        ),
      );
    }
  }

  Future<AppFailure> _quarantineAfterCommitFailure(AppFailure failure) async {
    final quarantine = await _runtime.dispose();
    if (quarantine is AppSuccess<void>) return failure;
    final quarantineFailure = (quarantine as AppFailureResult<void>).failure;
    return AppFailure(
      code: 'wallet_commit_quarantine_failed',
      kind: AppFailureKind.storage,
      userMessage:
          'A wallet change and cleanup could not be confirmed. Restart the '
          'app before continuing.',
      retryable: false,
      requiresReconciliation: true,
      outcomeUnknown:
          failure.outcomeUnknown || quarantineFailure.outcomeUnknown,
      cause: <AppFailure>[failure, quarantineFailure],
    );
  }

  Future<AppResult<WalletBalance>> balance(WalletAssetKind kind) =>
      _payments.balance(kind);

  /// Loads a bounded on-chain fee rate for a confirmation target.
  Future<AppResult<WalletFeeRateEstimate>> estimateFeeRate({
    int targetBlocks = standardFeeTargetBlocks,
  }) => _payments.estimateFeeRate(targetBlocks: targetBlocks);

  /// Loads cross-rail balances under one serialized native operation.
  Future<AppResult<WalletPortfolio>> portfolio() => _payments.portfolio();

  /// Loads one product asset's balance and normalized cross-rail activity.
  Future<AppResult<WalletActivityFeed>> activityFeed(WalletAssetKind kind) =>
      _payments.activityFeed(kind);

  /// Validates a destination and returns the route-bound payment preview.
  Future<AppResult<WalletPaymentPreview>> previewPayment(
    WalletPaymentTarget target,
    String destination,
  ) => _payments.preview(target, destination);

  /// Creates a receive request using canonical units for the selected target.
  ///
  /// Units are sats for Bitcoin on-chain, millisats for Bitcoin Lightning, and
  /// RGB smallest units for USDT. Omit [amountUnits] for an amountless request.
  /// RGB requests always use witness receipt and never prepare Bitcoin outputs.
  Future<AppResult<WalletReceiveRequest>> createReceiveRequest(
    WalletPaymentTarget target, {
    int? amountUnits,
  }) => _payments.createReceiveRequest(target, amountUnits: amountUnits);

  /// Submits one non-retryable payment mutation through the serialized owner.
  /// On-chain sends require [reviewedFeeRate]; changed or expired quotes must
  /// be refreshed and reviewed before another explicit submission.
  Future<AppResult<WalletSendResult>> sendPayment({
    required WalletPaymentTarget target,
    required String destination,
    required int amountUnits,
    RgbRecipientType? rgbRecipientType,
    int? witnessBitcoinAmountSats,
    WalletFeeRateEstimate? reviewedFeeRate,
    String? expectedWalletId,
  }) => _payments.send(
    target: target,
    destination: destination,
    amountUnits: amountUnits,
    rgbRecipientType: rgbRecipientType,
    witnessBitcoinAmountSats: witnessBitcoinAmountSats,
    reviewedFeeRate: reviewedFeeRate,
    // Capture before joining the repository queue: a queued wallet switch may
    // finish before this command gets its native lease.
    expectedWalletId: expectedWalletId ?? _runtime.activeProfile?.id,
  );

  /// Durable submission evidence never grants permission to repeat dispatch.
  Future<AppResult<WalletPaymentSubmission?>> paymentSubmissionStatus() =>
      _enqueueOperation(_submissions.status);

  /// Matches a durably recorded native transaction identity, never a guessed
  /// payment by amount/date or an empty history. This operation never sends.
  Future<AppResult<void>> reconcilePaymentSubmission() =>
      _enqueueOperation(_submissions.reconcile);

  /// Explicitly resumes only the saved, already-authorized native transaction.
  /// Separate from Check payment status; no screen invokes this automatically.
  Future<AppResult<void>> resumePaymentSubmission() =>
      _enqueueOperation(_submissions.resume);

  /// Capability and exact pending-entry observation only; never cancels.
  Future<AppResult<bool>> canRevokePaymentSubmission(
    WalletPaymentSubmission expected,
  ) => _enqueueOperation(() => _submissions.canRevoke(expected));

  /// User-confirmed revocation of one exact RGB handoff. No dispatch is retried.
  Future<AppResult<void>> revokePaymentSubmission(
    WalletPaymentSubmission expected,
  ) => _enqueueOperation(() => _submissions.revoke(expected));

  Future<AppResult<void>> sync() => _enqueueOperation(
    () => _runtime.readPaymentState((engine) => engine.sync()),
  );

  /// Suspends the native owner after all in-flight wallet metadata mutations.
  @override
  Future<AppResult<void>> suspend() =>
      _enqueueOperation(_runtime.suspend, requiresUnlocked: false);

  /// Resumes the native owner and recovers only a known-safe runtime failure
  /// from the durable active profile.
  @override
  Future<AppResult<void>> resume() => _enqueueOperation(_resumeUnsafe);

  Future<AppResult<void>> _resumeUnsafe() async {
    final resumed = await _runtime.resume();
    if (resumed is AppSuccess<void>) return resumed;
    if (resumed case AppFailureResult<void>(
      failure: AppFailure(requiresReconciliation: true),
    )) {
      return resumed;
    }

    final registryResult = await _profiles.read();
    if (registryResult case AppFailureResult<WalletRegistry>(:final failure)) {
      return AppResult.failure(failure);
    }
    final active =
        (registryResult as AppSuccess<WalletRegistry>).value.activeProfile;
    if (active == null) return resumed;
    return _runtime.switchTo(active);
  }

  /// Destroys the native owner after all repository mutations complete.
  @override
  Future<AppResult<void>> dispose() =>
      _enqueueOperation(_runtime.dispose, requiresUnlocked: false);

  Future<AppResult<WalletNetworkStatus>> networkStatus() => _enqueueOperation(
    () => _runtime.readPaymentState((engine) => engine.getNetworkStatus()),
  );

  /// Owns the same wallet and operation queue used by Send, wallet switching,
  /// native shutdown, and RGB-output preparation.
  Future<AppResult<T>> withHostedBridgeLease<T>(
    String walletId,
    Future<T> Function(RgbLibWalletEngine engine) operation,
    void Function() authorize, {
    required bool allowMutation,
  }) => _enqueueOperation(() async {
    final appAuthority = _captureAccessGuard();
    void guard() {
      appAuthority?.call();
      authorize();
      if (!_services.devBridgeEnabled ||
          _runtime.activeProfile?.id != walletId) {
        throw StateError('The active Dev wallet changed.');
      }
    }

    guard();
    if (allowMutation) {
      final pending = await _assertOnchainMutationResolved();
      if (pending case AppFailureResult<void>(:final failure)) {
        return AppResult.failure(failure);
      }
    }
    return _runtime.run((engine) {
      guard();
      if (engine is! RgbLibWalletEngine) {
        throw StateError('The Dev wallet is unavailable.');
      }
      return operation(engine);
    }, authorize: guard);
  });

  /// Each disclosure consumes a fresh authorization inside the serialized
  /// operation, after earlier wallet/lifecycle changes have settled.
  Future<AppResult<WalletPublicKeys>> publicKeys({
    SensitiveAuthorization? authorization,
    String? walletId,
  }) => _enqueueOperation(() async {
    final expectedWallet = walletId ?? _runtime.activeProfile?.id;
    if (!_authorizeDisclosure(
      authorization,
      SecurityPurpose.exportXpubs,
      expectedWallet,
    )) {
      return AppResult.failure(_disclosureAuthenticationFailure());
    }
    final generation = securityController?.generation;
    final assertAuthorized = _captureAccessGuard();
    final result = await _runtime.readPaymentState(
      (engine) => engine.getPublicKeys(),
      authorize: assertAuthorized,
    );
    if (!_disclosureStillCurrent(expectedWallet, generation)) {
      return AppResult.failure(_disclosureAuthenticationFailure());
    }
    return result;
  });

  Future<AppResult<String>> recoveryMnemonic(
    String walletId, {
    SensitiveAuthorization? authorization,
  }) => _enqueueOperation(() async {
    if (!_authorizeDisclosure(
      authorization,
      SecurityPurpose.revealSeed,
      walletId,
    )) {
      return AppResult.failure(_disclosureAuthenticationFailure());
    }
    final generation = securityController?.generation;
    final result = await _runtime.recoveryMnemonic(
      walletId,
      authorize: _captureAccessGuard(),
    );
    if (!_disclosureStillCurrent(walletId, generation)) {
      return AppResult.failure(_disclosureAuthenticationFailure());
    }
    return result;
  });

  bool _authorizeDisclosure(
    SensitiveAuthorization? authorization,
    SecurityPurpose purpose,
    String? walletId,
  ) {
    // Legacy repository fixtures without a security controller still exercise
    // the runtime's own identity/lifecycle checks. Production always injects
    // the controller at the application composition root.
    final controller = securityController;
    if (controller == null) return true;
    return walletId != null &&
        _runtime.activeProfile?.id == walletId &&
        controller.consume(authorization, purpose, walletId: walletId);
  }

  bool _disclosureStillCurrent(String? walletId, int? generation) {
    final controller = securityController;
    return controller == null ||
        (controller.sensitiveVisible &&
            controller.generation == generation &&
            _runtime.activeProfile?.id == walletId);
  }

  static AppFailure _disclosureAuthenticationFailure() => const AppFailure(
    code: 'wallet_disclosure_authentication_required',
    kind: AppFailureKind.authentication,
    userMessage: 'Unlock again to view this wallet information.',
    retryable: true,
  );

  Future<AppResult<void>> _assertOnchainMutationResolved() async {
    final payment = await _submissions.assertResolved();
    if (payment is AppFailureResult<void>) return payment;
    return _rgbSetup.assertResolved();
  }

  Future<AppResult<T>> _enqueueOperation<T>(
    Future<AppResult<T>> Function() operation, {
    bool requiresUnlocked = true,
  }) {
    // A foreground session cannot inherit work that was requested before a
    // background/lock, even if the device has been unlocked by execution time.
    final assertAuthorized = requiresUnlocked ? _captureAccessGuard() : null;
    final completer = Completer<AppResult<T>>();
    _operationTail = _operationTail.then((_) async {
      try {
        assertAuthorized?.call();
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.complete(
          AppResult.failure(FailureMapper.from(error, stackTrace)),
        );
      }
    });
    return completer.future;
  }

  void Function()? _captureAccessGuard() {
    final controller = securityController;
    if (controller == null) return null;
    final generation = controller.generation;
    return () {
      if (!controller.canAccessWallet || controller.generation != generation) {
        throw const AppFailureException(
          AppFailure(
            code: 'wallet_locked',
            kind: AppFailureKind.authentication,
            userMessage: 'Unlock Aster and try again.',
            retryable: true,
          ),
        );
      }
    };
  }

  static bool _outcomeUnknown<T>(AppResult<T> result) => switch (result) {
    AppSuccess<T>() => false,
    AppFailureResult<T>(:final failure) => failure.outcomeUnknown,
  };

  static String _normalizeMnemonic(String mnemonic) =>
      mnemonic.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  static AppFailure _invalidMnemonicFailure({Object? cause}) {
    return AppFailure(
      code: 'wallet_mnemonic_invalid',
      kind: AppFailureKind.validation,
      userMessage: 'The recovery phrase checksum is not valid.',
      retryable: false,
      cause: cause,
    );
  }

  static DateTime _utcNow() => DateTime.now().toUtc();
}
