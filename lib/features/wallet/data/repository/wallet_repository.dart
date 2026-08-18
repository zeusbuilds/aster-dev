import 'dart:async';

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';
import '../../domain/validation/validation.dart';
import '../runtime/runtime.dart';
import '../storage/storage.dart';
import '../validation/validation.dart';
import 'wallet_lifecycle_repository.dart';

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
    this._services,
    this._legacySeedPreflight, {
    this._bitcoinInstructions = const BitcoinPaymentInstructionParser(),
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow {
    _services.validate();
  }

  final WalletProfilePersistence _profiles;
  final WalletRuntime _runtime;
  final WalletKeyGenerator _keyGenerator;
  final WalletIdentityGenerator _identityGenerator;
  final WalletServiceConfiguration _services;
  final LegacyWalletSeedPreflight _legacySeedPreflight;
  final BitcoinPaymentInstructionDecoder _bitcoinInstructions;
  final DateTime Function() _clock;
  Future<void> _operationTail = Future<void>.value();

  /// Balanced confirmation target used until product fee selection exists.
  static const standardFeeTargetBlocks = 6;

  Future<AppResult<WalletRegistry>> load() => _enqueueOperation(_profiles.read);

  /// Product payment targets and whether this deployment can execute them.
  ///
  /// Bitcoin is always identified by the protocol. RGB USDT remains visible
  /// but unavailable until its environment-specific contract metadata exists.
  List<WalletPaymentCapability> get paymentCapabilities {
    final usdt = _services.usdtAsset;
    final capabilities = <WalletPaymentCapability>[
      WalletPaymentCapability.available(
        const PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.onchain,
        ),
      ),
      WalletPaymentCapability.available(
        const PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.lightning,
        ),
      ),
      if (usdt == null) ...const [
        WalletPaymentCapability.unavailable(WalletPaymentTarget.usdtOnchain),
        WalletPaymentCapability.unavailable(WalletPaymentTarget.usdtLightning),
      ] else ...[
        WalletPaymentCapability.available(
          PaymentRoute(
            asset: WalletAsset.rgbUsdt(
              assetId: usdt.contractId,
              precision: usdt.precision,
            ),
            rail: PaymentRail.onchain,
          ),
        ),
        WalletPaymentCapability.available(
          PaymentRoute(
            asset: WalletAsset.rgbUsdt(
              assetId: usdt.contractId,
              precision: usdt.precision,
            ),
            rail: PaymentRail.lightning,
          ),
        ),
      ],
    ];
    return List<WalletPaymentCapability>.unmodifiable(capabilities);
  }

  /// Resolves an untrusted route identifier to deployment-owned asset data.
  AppResult<PaymentRoute> resolvePaymentTarget(WalletPaymentTarget target) {
    for (final capability in paymentCapabilities) {
      if (capability.target != target) continue;
      final route = capability.route;
      if (route != null) return AppResult.success(route);
      return AppResult.failure(
        const AppFailure(
          code: 'rgb_usdt_not_configured',
          kind: AppFailureKind.configuration,
          userMessage: 'USDT is not configured for this network.',
          retryable: false,
        ),
      );
    }
    return AppResult.failure(
      const AppFailure(
        code: 'payment_target_unknown',
        kind: AppFailureKind.validation,
        userMessage: 'Choose a supported asset and payment rail.',
        retryable: false,
      ),
    );
  }

  /// Restores the persisted active wallet during app bootstrap.
  Future<AppResult<WalletRegistry>> bootstrap() {
    return _enqueueOperation(_bootstrapUnsafe);
  }

  Future<AppResult<WalletRegistry>> _bootstrapUnsafe() async {
    final legacyPreflight = await _legacySeedPreflight.verify();
    if (legacyPreflight case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(failure);
    }
    final registryResult = await _profiles.read();
    if (registryResult case AppFailureResult<WalletRegistry>()) {
      return registryResult;
    }
    var registry = (registryResult as AppSuccess<WalletRegistry>).value;
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
    final storageAudit = await _runtime.verifyStorage(registry.readyProfiles);
    if (storageAudit case AppFailureResult<void>(:final failure)) {
      return AppResult.failure(failure);
    }
    final active = registry.activeProfile;
    if (active == null) return AppResult.success(registry);
    final restore = await _runtime.restore(active);
    return switch (restore) {
      AppSuccess<void>() => AppResult.success(registry),
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
    if (persisted is AppSuccess<WalletRegistry>) return persisted;

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
    return persisted;
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

  Future<AppResult<WalletBalance>> balance(WalletAssetKind kind) {
    final routeResult = resolvePaymentTarget(
      kind == WalletAssetKind.bitcoin
          ? WalletPaymentTarget.bitcoinOnchain
          : WalletPaymentTarget.usdtOnchain,
    );
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      return Future<AppResult<WalletBalance>>.value(AppResult.failure(failure));
    }
    final route = (routeResult as AppSuccess<PaymentRoute>).value;
    return _enqueueOperation(
      () => _runtime.run((engine) => engine.getBalance(route.asset)),
    );
  }

  /// Loads a bounded on-chain fee rate for a confirmation target.
  Future<AppResult<WalletFeeRateEstimate>> estimateFeeRate({
    int targetBlocks = standardFeeTargetBlocks,
  }) {
    if (targetBlocks < WalletFeeRateEstimate.minimumTargetBlocks ||
        targetBlocks > WalletFeeRateEstimate.maximumTargetBlocks) {
      return Future<AppResult<WalletFeeRateEstimate>>.value(
        AppResult.failure(_invalidFeeTargetFailure()),
      );
    }
    return _enqueueOperation(
      () => _runtime.run((engine) => engine.estimateFeeRate(targetBlocks)),
    );
  }

  /// Loads cross-rail balances under one serialized native operation.
  Future<AppResult<WalletPortfolio>> portfolio() {
    final usdtRoute = resolvePaymentTarget(WalletPaymentTarget.usdtOnchain);
    return _enqueueOperation(
      () => _runtime.run((engine) async {
        final bitcoin = await engine.getBalance(WalletAsset.bitcoin);
        final WalletBalance? usdt;
        if (usdtRoute case AppSuccess<PaymentRoute>(:final value)) {
          usdt = await engine.getBalance(value.asset);
        } else {
          usdt = null;
        }
        return WalletPortfolio(bitcoin: bitcoin, usdt: usdt);
      }),
    );
  }

  /// Loads one product asset's real balance and normalized cross-rail
  /// activity under the repository's single serialized native owner.
  Future<AppResult<WalletActivityFeed>> activityFeed(WalletAssetKind kind) {
    final routeResult = resolvePaymentTarget(
      kind == WalletAssetKind.bitcoin
          ? WalletPaymentTarget.bitcoinOnchain
          : WalletPaymentTarget.usdtOnchain,
    );
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      return Future<AppResult<WalletActivityFeed>>.value(
        AppResult.failure(failure),
      );
    }
    final asset = (routeResult as AppSuccess<PaymentRoute>).value.asset;
    return _enqueueOperation(
      () => _runtime.run((engine) async {
        final networkStatus = await engine.getNetworkStatus();
        final balance = await engine.getBalance(asset);
        final activities = await engine.listActivity(asset);
        return WalletActivityFeed(
          balance: balance,
          networkStatus: networkStatus,
          activities: activities,
        );
      }),
    );
  }

  /// Validates a destination and returns the route-bound payment preview.
  Future<AppResult<WalletPaymentPreview>> previewPayment(
    WalletPaymentTarget target,
    String destination,
  ) {
    final routeResult = resolvePaymentTarget(target);
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      return Future<AppResult<WalletPaymentPreview>>.value(
        AppResult.failure(failure),
      );
    }
    final route = (routeResult as AppSuccess<PaymentRoute>).value;
    if (target == WalletPaymentTarget.bitcoinOnchain) {
      final parsed = _bitcoinInstructions.decodeOnchain(
        destination,
        _services.environment,
      );
      return Future<AppResult<WalletPaymentPreview>>.value(switch (parsed) {
        AppSuccess<BitcoinDestination>(:final value) => AppResult.success(
          WalletPaymentPreview(
            route: route,
            encodedDestination: value.address,
            displayDestination: value.address,
            amount: value.amount,
            recipientLabel: value.recipientLabel,
            message: value.message,
          ),
        ),
        AppFailureResult<BitcoinDestination>(:final failure) =>
          AppResult.failure(failure),
      });
    }
    if (target == WalletPaymentTarget.bitcoinLightning) {
      final parsed = _bitcoinInstructions.extractLightning(destination);
      if (parsed case AppFailureResult<BitcoinLightningInstruction>(
        :final failure,
      )) {
        return Future<AppResult<WalletPaymentPreview>>.value(
          AppResult.failure(failure),
        );
      }
      final instruction =
          (parsed as AppSuccess<BitcoinLightningInstruction>).value;
      return _enqueueOperation(() async {
        final decoded = await _runtime.run(
          (engine) => engine.decodeInvoice(route, instruction.invoice),
        );
        return switch (decoded) {
          AppSuccess<WalletPaymentPreview>(:final value) => AppResult.success(
            value.withDisplayMetadata(
              recipientLabel: instruction.recipientLabel,
              message: instruction.message,
            ),
          ),
          AppFailureResult<WalletPaymentPreview>(:final failure) =>
            AppResult.failure(failure),
        };
      });
    }
    if (!_isValidPaymentString(destination)) {
      return Future<AppResult<WalletPaymentPreview>>.value(
        AppResult.failure(_invalidDestinationFailure()),
      );
    }
    return _enqueueOperation(
      () => _runtime.run((engine) => engine.decodeInvoice(route, destination)),
    );
  }

  /// Creates a receive request using canonical units for the selected target.
  ///
  /// Units are sats for Bitcoin on-chain, millisats for Bitcoin Lightning, and
  /// RGB smallest units for USDT. Omit [amountUnits] for an amountless request.
  Future<AppResult<WalletReceiveRequest>> createReceiveRequest(
    WalletPaymentTarget target, {
    int? amountUnits,
  }) {
    final routeResult = resolvePaymentTarget(target);
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      return Future<AppResult<WalletReceiveRequest>>.value(
        AppResult.failure(failure),
      );
    }
    final route = (routeResult as AppSuccess<PaymentRoute>).value;
    if (amountUnits == null && target.requiresReceiveAmount) {
      return Future<AppResult<WalletReceiveRequest>>.value(
        AppResult.failure(_receiveAmountRequiredFailure()),
      );
    }
    final amountResult = _amountForRoute(route, amountUnits);
    if (amountResult case AppFailureResult<WalletAmount?>(:final failure)) {
      return Future<AppResult<WalletReceiveRequest>>.value(
        AppResult.failure(failure),
      );
    }
    final amount = (amountResult as AppSuccess<WalletAmount?>).value;
    return _enqueueOperation(
      () => _runtime.run(
        (engine) => engine.createReceiveRequest(route, amount: amount),
      ),
    );
  }

  /// Submits one non-retryable payment mutation through the serialized owner.
  Future<AppResult<WalletSendResult>> sendPayment({
    required WalletPaymentTarget target,
    required String destination,
    required int amountUnits,
  }) {
    final routeResult = resolvePaymentTarget(target);
    if (routeResult case AppFailureResult<PaymentRoute>(:final failure)) {
      return Future<AppResult<WalletSendResult>>.value(
        AppResult.failure(failure),
      );
    }
    final route = (routeResult as AppSuccess<PaymentRoute>).value;
    final amountResult = _amountForRoute(route, amountUnits);
    if (amountResult case AppFailureResult<WalletAmount?>(:final failure)) {
      return Future<AppResult<WalletSendResult>>.value(
        AppResult.failure(failure),
      );
    }
    final amount = (amountResult as AppSuccess<WalletAmount?>).value;
    if (amount == null) {
      return Future<AppResult<WalletSendResult>>.value(
        AppResult.failure(_invalidAmountFailure()),
      );
    }
    final String submissionDestination;
    if (target == WalletPaymentTarget.bitcoinOnchain) {
      final parsed = _bitcoinInstructions.decodeOnchain(
        destination,
        _services.environment,
      );
      if (parsed case AppFailureResult<BitcoinDestination>(:final failure)) {
        return Future<AppResult<WalletSendResult>>.value(
          AppResult.failure(failure),
        );
      }
      final bitcoinDestination =
          (parsed as AppSuccess<BitcoinDestination>).value;
      final encodedAmount = bitcoinDestination.amount;
      if (encodedAmount != null && encodedAmount != amount) {
        return Future<AppResult<WalletSendResult>>.value(
          AppResult.failure(_amountMismatchFailure()),
        );
      }
      submissionDestination = bitcoinDestination.address;
    } else if (target == WalletPaymentTarget.bitcoinLightning) {
      final parsed = _bitcoinInstructions.extractLightning(destination);
      if (parsed case AppFailureResult<BitcoinLightningInstruction>(
        :final failure,
      )) {
        return Future<AppResult<WalletSendResult>>.value(
          AppResult.failure(failure),
        );
      }
      submissionDestination =
          (parsed as AppSuccess<BitcoinLightningInstruction>).value.invoice;
    } else {
      if (!_isValidPaymentString(destination)) {
        return Future<AppResult<WalletSendResult>>.value(
          AppResult.failure(_invalidDestinationFailure()),
        );
      }
      submissionDestination = destination;
    }
    if (route.rail == PaymentRail.onchain) {
      return _enqueueOperation(() async {
        final feeResult = await _runtime.run(
          (engine) => engine.estimateFeeRate(standardFeeTargetBlocks),
        );
        if (feeResult case AppFailureResult<WalletFeeRateEstimate>(
          :final failure,
        )) {
          return AppResult.failure(failure);
        }
        final command = WalletSendCommand(
          route: route,
          destination: submissionDestination,
          amount: amount,
          feeRate: (feeResult as AppSuccess<WalletFeeRateEstimate>).value,
        );
        return _runtime.run((engine) => engine.sendPayment(command));
      });
    }
    final command = WalletSendCommand(
      route: route,
      destination: submissionDestination,
      amount: amount,
    );
    return _enqueueOperation(
      () => _runtime.run((engine) => engine.sendPayment(command)),
    );
  }

  Future<AppResult<void>> sync() => _enqueueOperation(_runtime.sync);

  /// Suspends the native owner after all in-flight wallet metadata mutations.
  @override
  Future<AppResult<void>> suspend() => _enqueueOperation(_runtime.suspend);

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
  Future<AppResult<void>> dispose() => _enqueueOperation(_runtime.dispose);

  Future<AppResult<WalletNetworkStatus>> networkStatus() => _enqueueOperation(
    () => _runtime.run((engine) => engine.getNetworkStatus()),
  );

  Future<AppResult<WalletPublicKeys>> publicKeys() =>
      _enqueueOperation(() => _runtime.run((engine) => engine.getPublicKeys()));

  Future<AppResult<String>> recoveryMnemonic(String walletId) =>
      _enqueueOperation(() => _runtime.recoveryMnemonic(walletId));

  Future<AppResult<T>> _enqueueOperation<T>(
    Future<AppResult<T>> Function() operation,
  ) {
    final completer = Completer<AppResult<T>>();
    _operationTail = _operationTail.then((_) async {
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

  static AppResult<WalletAmount?> _amountForRoute(
    PaymentRoute route,
    int? units,
  ) {
    if (units == null) return const AppResult.success(null);
    if (units <= 0 || units > WalletAmount.maxNativeUnits) {
      return AppResult.failure(_invalidAmountFailure());
    }
    final amount = route.rail == PaymentRail.onchain
        ? WalletAmount.onchain(assetId: route.asset.id, units: units)
        : WalletAmount.lightning(assetId: route.asset.id, units: units);
    return AppResult.success(amount);
  }

  static bool _isValidPaymentString(String value) =>
      WalletProtocolText.isEncodedValue(value);

  static AppFailure _invalidAmountFailure() => const AppFailure(
    code: 'payment_amount_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'Enter a valid amount greater than zero.',
    retryable: false,
  );

  static AppFailure _receiveAmountRequiredFailure() => const AppFailure(
    code: 'payment_receive_amount_required',
    kind: AppFailureKind.validation,
    userMessage: 'Enter an amount to create this payment request.',
    retryable: false,
  );

  static AppFailure _invalidDestinationFailure() => const AppFailure(
    code: 'payment_destination_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'Enter a valid payment destination.',
    retryable: false,
  );

  static AppFailure _invalidFeeTargetFailure() => const AppFailure(
    code: 'payment_fee_target_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'Choose a valid confirmation target.',
    retryable: false,
  );

  static AppFailure _amountMismatchFailure() => const AppFailure(
    code: 'payment_amount_mismatch',
    kind: AppFailureKind.validation,
    userMessage: 'The entered amount does not match the payment request.',
    retryable: false,
  );

  static DateTime _utcNow() => DateTime.now().toUtc();
}
