import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/config/evm_chain_validator.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/network/http_evm_chain_validator.dart';
import '../../../../core/platform/local_network_access.dart';
import '../../domain/models/models.dart';
import '../../domain/validation/validation.dart';
import '../validation/validation.dart';
import 'rgb_setup_wallet_engine.dart';
import 'rgb_wallet_activity_mapper.dart';
import 'rgb_wallet_balance_mapper.dart';
import 'rgb_wallet_native_value_parser.dart';
import 'wallet_deletion_safety_engine.dart';
import 'wallet_engine.dart';
import 'wallet_payment_recovery_engine.dart';

/// Resolves explicit deployment overrides and immutable-SDK endpoint defaults.
///
/// Composition must use the returned object for both runtime creation and
/// Settings presentation. This prevents the SDK adapter from contacting a
/// fallback endpoint that the app has neither validated nor disclosed.
abstract final class RgbWalletServiceConfigurationResolver {
  // The stable SDK exports indexer/proxy defaults, but not its LSP resolver.
  // Keep this app deployment policy explicit and visible in Network settings.
  static const _utexoSignetLspBaseUrl = 'https://lsp-signet.utexo.com';

  static WalletServiceConfiguration resolve(
    WalletServiceConfiguration configured, {
    bool allowInsecureDevelopmentEndpoints = !kReleaseMode,
  }) {
    configured.validate(
      allowInsecureDevelopmentEndpoints: allowInsecureDevelopmentEndpoints,
    );
    final defaults = getNetworkDefaults(configured.sdkNetwork);
    final indexerUrl = configured.indexerUrl ?? defaults?.indexerUrl;
    final rgbTransportProxy =
        configured.rgbTransportProxy ?? defaults?.proxyEndpoint;
    if (indexerUrl == null || rgbTransportProxy == null) {
      throw const AppConfigurationException();
    }
    final resolved = WalletServiceConfiguration(
      environment: configured.environment,
      sdkNetwork: configured.sdkNetwork,
      daemonListeningPort: configured.daemonListeningPort,
      ldkPeerListeningPort: configured.ldkPeerListeningPort,
      indexerUrl: indexerUrl,
      rgbTransportProxy: rgbTransportProxy,
      lspBaseUrl:
          configured.lspBaseUrl ??
          (configured.sdkNetwork == 'utexo' ? _utexoSignetLspBaseUrl : null),
      vssUrl: configured.vssUrl,
      ethRpcUrl: configured.ethRpcUrl,
      ethChainId: configured.ethChainId,
      explorerBaseUrl: configured.explorerBaseUrl,
      usdtAsset: configured.usdtAsset,
    );
    resolved.validate(
      allowInsecureDevelopmentEndpoints: allowInsecureDevelopmentEndpoints,
    );
    return resolved;
  }
}

/// Stable-public-API adapter for `rgb_sdk_flutter`.
final class RgbWalletEngineFactory implements WalletEngineFactory {
  const RgbWalletEngineFactory()
    : _sdk = const RgbSdkFlutter(),
      _bitcoinAddresses = const BitcoinPaymentInstructionParser(),
      _localNetworkAccess = null,
      _evmChainValidator = const HttpEvmChainValidator(),
      utcClock = null;

  /// Production constructor for sharing the app-owned validation boundary.
  const RgbWalletEngineFactory.withAddresses(
    this._bitcoinAddresses, {
    this.utcClock,
    this._localNetworkAccess,
    this._evmChainValidator = const HttpEvmChainValidator(),
  }) : _sdk = const RgbSdkFlutter();

  /// Test seam for proving stable-SDK forwarding without global state.
  const RgbWalletEngineFactory.withSdk(
    this._sdk, {
    this._bitcoinAddresses = const BitcoinPaymentInstructionParser(),
    this._localNetworkAccess,
    this._evmChainValidator = const HttpEvmChainValidator(),
  }) : utcClock = null;

  final RgbSdkFlutter _sdk;
  final BitcoinAddressValidator _bitcoinAddresses;
  final LocalNetworkAccess? _localNetworkAccess;
  final EvmChainValidator _evmChainValidator;

  /// UTC time source forwarded to each created adapter.
  final DateTime Function()? utcClock;

  @override
  WalletEngine create(WalletEngineConfiguration configuration) {
    final services = configuration.services..validate();
    if (services.indexerUrl == null || services.rgbTransportProxy == null) {
      throw const AppConfigurationException();
    }
    final wallet = _sdk.wallet(
      config: UtexoWalletConfig(
        storageDirPath: configuration.storageDirectory,
        network: services.sdkNetwork,
        daemonListeningPort: services.daemonListeningPort,
        ldkPeerListeningPort: services.ldkPeerListeningPort,
        vssUrl: services.vssUrl,
        vssAllowHttp: services.allowsInsecureLocalVss,
        lspBaseUrl: services.lspBaseUrl,
      ),
    );
    return RgbWalletEngine(
      wallet,
      services,
      UtexoUnlockConfig(
        indexerUrl: services.indexerUrl,
        proxyEndpoint: services.rgbTransportProxy,
        ethRpcUrl: services.ethRpcUrl,
      ),
      clock: utcClock,
      bitcoinAddresses: _bitcoinAddresses,
      localNetworkAccess: _localNetworkAccess,
      evmChainValidator: _evmChainValidator,
    );
  }
}

final class RgbWalletKeyGenerator implements WalletKeyGenerator {
  const RgbWalletKeyGenerator();

  @override
  Future<String> generateMnemonic(BlockchainEnvironment environment) async {
    final keys = await generateKeys(_sdkNetwork(environment));
    return keys.mnemonic;
  }

  @override
  Future<void> validateMnemonic(String mnemonic) async {
    validateBip39Mnemonic(mnemonic);
  }

  static String _sdkNetwork(BlockchainEnvironment environment) {
    return environment == BlockchainEnvironment.signet
        ? 'utexo'
        : environment.name;
  }
}

/// Converts SDK models to app-owned domain models at the repository boundary.
final class RgbWalletEngine
    implements
        WalletEngine,
        RgbSetupWalletEngine,
        WalletDeletionSafetyEngine,
        WalletPaymentRecoveryEngine,
        WalletPaymentDeadlineRecovery {
  RgbWalletEngine(
    this._wallet,
    this._services,
    this._unlockConfig, {
    DateTime Function()? clock,
    Stopwatch Function()? deletionAuditStopwatch,
    this._bitcoinAddresses = const BitcoinPaymentInstructionParser(),
    LocalNetworkAccess? localNetworkAccess,
    this._evmChainValidator = const HttpEvmChainValidator(),
  }) : _clock = clock ?? _utcNow,
       _deletionAuditStopwatch = deletionAuditStopwatch ?? Stopwatch.new,
       _localNetworkAccess = localNetworkAccess ?? PlatformLocalNetworkAccess();

  static const _receiveLifetime = Duration(hours: 1);
  static const _activities = RgbWalletActivityMapper();
  static const _balances = RgbWalletBalanceMapper();
  static const _nativeValues = RgbWalletNativeValueParser();

  final UtexoWallet _wallet;
  final WalletServiceConfiguration _services;
  final UtexoUnlockConfig _unlockConfig;
  final DateTime Function() _clock;
  final Stopwatch Function() _deletionAuditStopwatch;
  final BitcoinAddressValidator _bitcoinAddresses;
  final LocalNetworkAccess _localNetworkAccess;
  final EvmChainValidator _evmChainValidator;
  bool _requiresPaymentReopen = false;

  @override
  bool get requiresPaymentReopen => _requiresPaymentReopen;

  // RLN 0.17 has no Lightning runtime on mainnet; querying its Lightning-only
  // endpoints fails with 403. Never hide a real network error as an empty list.
  bool get _nativeLightningAvailable =>
      _services.environment != BlockchainEnvironment.mainnet;

  @override
  Future<void> provision({
    required String databasePassword,
    required String mnemonic,
  }) async {
    await _localNetworkAccess.ensureFor(_services);
    await _evmChainValidator.verify(_services);
    await _wallet.init(password: databasePassword, mnemonic: mnemonic);
    await _wallet.unlock(password: databasePassword, config: _unlockConfig);
    _requiresPaymentReopen = false;
  }

  @override
  Future<void> openPersisted({required String databasePassword}) async {
    await _localNetworkAccess.ensureFor(_services);
    await _evmChainValidator.verify(_services);
    await _wallet.reinit(
      password: databasePassword,
      unlockConfig: _unlockConfig,
    );
    _requiresPaymentReopen = false;
  }

  @override
  Future<void> sync() async {
    await _wallet.syncWallet();
    // RGB consignments and acknowledgements have their own state machine.
    // A chain sync alone cannot advance an incoming asset transfer.
    await _wallet.refreshWallet();
  }

  @override
  Future<void> shutdown() => _wallet.shutdown();

  @override
  Future<void> destroy() => _wallet.destroy();

  Future<int> _freeRgbAllocationCount() async {
    final List<CoreUnspent> unspents;
    try {
      unspents = await _wallet.listUnspents();
    } on FormatException catch (error, stack) {
      Error.throwWithStackTrace(
        NativeProtocolException(
          'Malformed native wallet output response.',
          field: 'listUnspents',
          cause: FailureMapper.diagnosticCause(error),
        ),
        stack,
      );
    } on TypeError catch (error, stack) {
      Error.throwWithStackTrace(
        NativeProtocolException(
          'Malformed native wallet output response.',
          field: 'listUnspents',
          cause: FailureMapper.diagnosticCause(error),
        ),
        stack,
      );
    }
    if (unspents.length > 10000) {
      throw const NativeProtocolException(
        'Too many wallet outputs.',
        field: 'unspents',
      );
    }
    final outpoints = <String>{};
    var available = 0;
    for (final item in unspents) {
      final outpoint = item.utxo.outpoint;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(outpoint.txid) ||
          outpoint.vout < 0 ||
          outpoint.vout > 0xffffffff ||
          !outpoints.add('${outpoint.txid}:${outpoint.vout}') ||
          item.pendingBlinded < 0 ||
          item.utxo.btcAmount < 0) {
        throw const NativeProtocolException(
          'Malformed wallet output inventory.',
          field: 'unspents',
        );
      }
      if (item.utxo.exists &&
          item.utxo.colorable &&
          item.rgbAllocations.isEmpty &&
          item.pendingBlinded == 0) {
        available += 1;
      }
    }
    return available;
  }

  @override
  Future<RgbWalletSetupInventory> rgbSetupInventory() async {
    final available = await _freeRgbAllocationCount();
    final bitcoin = await _wallet.getBtcBalance();
    _balances.validateBitcoin(bitcoin);
    final node = await _wallet.getNodeInfo();
    final artifact = await const RgbSdkFlutter().nativeArtifactInfo();
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'artifact': artifact.toMap(),
              'policy': 'aster-rgb-setup-v1',
            }),
          ),
        )
        .toString();
    return RgbWalletSetupInventory(
      freeAllocationCount: available,
      vanillaSpendableSats: bitcoin.vanilla.spendable,
      runtimeFingerprint: fingerprint,
      nodePublicKey: node.pubkey,
    );
  }

  @override
  Future<List<RgbWalletSetupTransaction>> rgbSetupTransactions() async =>
      (await _wallet.listTransactions())
          .where((tx) => tx.transactionType == 'CreateUtxos')
          .map(
            (tx) => RgbWalletSetupTransaction(
              txid: tx.txid,
              confirmed: tx.confirmationTime != null,
            ),
          )
          .toList(growable: false);

  @override
  Future<void> createRgbSetupOutputs(int feeRateSatPerVbyte) async {
    if (feeRateSatPerVbyte <= 0 ||
        feeRateSatPerVbyte > WalletFeeRateEstimate.maximumSatsPerVbyte) {
      throw ArgumentError('Invalid reviewed fee rate.');
    }
    await _wallet.createUtxos(
      upTo: false,
      num: RgbWalletSetupReview.outputCount,
      size: RgbWalletSetupReview.outputValueSats,
      feeRate: feeRateSatPerVbyte.toDouble(),
    );
  }

  /// The 60-second aggregate budget is checked between SDK operations. Each
  /// current call retains its own native deadline/queue; nothing is abandoned.
  static const deletionAuditBudget = Duration(seconds: 60);

  @override
  Future<bool> hasProtectedRgbState() async {
    try {
      return await _withPaymentDeadline(_auditWalletDeletionUnsafe);
    } on RlnOperationTimeoutException catch (error, stackTrace) {
      // No deletion has been staged, and this path never dispatches a send.
      // The SDK still owns/drains its native future; the next explicit action
      // reopens that owner before regular work, rather than clearing its queue.
      throw AppFailureException(
        AppFailure(
          code: 'wallet_deletion_audit_unavailable',
          kind: AppFailureKind.timeout,
          userMessage: 'Wallet assets could not be checked in time. Try again.',
          retryable: true,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    } on BadRequestError catch (error, stackTrace) {
      // Audit has no user-entered fields. A native contract rejection must
      // never incorrectly ask the user to correct wallet input.
      throw AppFailureException(
        AppFailure(
          code: 'wallet_deletion_audit_unavailable',
          kind: AppFailureKind.protocol,
          userMessage: 'Wallet assets could not be checked. Try again later.',
          retryable: false,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<bool> _auditWalletDeletionUnsafe() async {
    final stopwatch = _deletionAuditStopwatch()..start();
    void checkBudget() {
      if (stopwatch.elapsed >= deletionAuditBudget) {
        throw const AppFailureException(
          AppFailure(
            code: 'wallet_deletion_audit_unavailable',
            kind: AppFailureKind.timeout,
            userMessage:
                'Wallet assets could not be checked in time. Try again.',
            retryable: true,
          ),
        );
      }
    }

    Future<T> checked<T>(Future<T> Function() operation) async {
      checkBudget();
      final result = await operation();
      checkBudget();
      return result;
    }

    Future<RefreshTransfersResult> refresh() async {
      final result = await checked(() => _wallet.refreshTransfers());
      if (result.transfers.keys.any((index) => index < 0) ||
          result.transfers.values.any((transfer) => transfer.failure != null)) {
        throw const AppFailureException(
          AppFailure(
            code: 'wallet_deletion_audit_unavailable',
            kind: AppFailureKind.connectivity,
            userMessage: 'Wallet assets could not be checked. Try again.',
            retryable: true,
          ),
        );
      }
      return result;
    }

    Future<List<String>> assets() async {
      final inventory = await checked(() => _wallet.listAssets());
      final ids = inventory.assetIds.toList(growable: false);
      if (ids.length > 5000 || ids.toSet().length != ids.length) {
        throw const FormatException('RGB asset inventory is invalid.');
      }
      return ids;
    }

    bool terminal(String? status) =>
        status == CoreTransferStatuses.settled ||
        status == CoreTransferStatuses.failed;
    try {
      // RLN 0.17 rejects listTransfers without an asset or transaction ID.
      // Refresh is instead the native inventory of every waiting batch,
      // including a first receive whose asset is not imported yet. A null
      // updatedStatus means unchanged/pending, never an empty or safe result.
      var refreshed = await refresh();
      final ids = await assets();
      final transfers = <CoreTransfer>[];
      for (final id in ids) {
        transfers.addAll(
          await checked(() => _wallet.listTransfers(assetId: id)),
        );
      }
      final knownBatches = transfers
          .map((transfer) => transfer.batchTransferIdx)
          .whereType<int>()
          .toSet();
      var reconciled = false;
      if (refreshed.transfers.entries.any(
        (entry) =>
            !terminal(entry.value.updatedStatus) &&
            !knownBatches.contains(entry.key),
      )) {
        // The native bulk sweep selects ONLY expired, fallible batches with
        // no associated asset. It synchronizes and refreshes them first; a
        // progressed/funded transfer is preserved, and prepared transactions
        // cannot be swept. No app clock or guessed transaction proves expiry.
        await checked(() => _wallet.failTransfers(noAssetOnly: true));
        reconciled = true;
      }
      for (final transfer in transfers) {
        final expiry = transfer.expiration;
        if (transfer.status == CoreTransferStatuses.waitingCounterparty &&
            (transfer.kind == 'ReceiveWitness' ||
                transfer.kind == 'ReceiveBlind') &&
            transfer.assignments.isEmpty &&
            transfer.txid == null &&
            expiry != null &&
            expiry > 0 &&
            expiry <= _clock().toUtc().millisecondsSinceEpoch ~/ 1000 &&
            transfer.batchTransferIdx != null) {
          await checked(
            () => _wallet.failTransfers(
              batchTransferIdx: transfer.batchTransferIdx,
            ),
          );
          reconciled = true;
        }
      }
      if (reconciled) refreshed = await refresh();
      // Reconciliation may import the first incoming contract. Read inventory,
      // balances and scoped history again before authorizing any deletion.
      for (final id in await assets()) {
        final balance = await checked(() => _wallet.getAssetBalance(id));
        final amounts = [
          balance.settled,
          balance.future,
          balance.spendable,
          balance.offchainOutbound,
          balance.offchainInbound,
        ];
        if (amounts.any((amount) => amount < BigInt.zero)) {
          throw const FormatException('RGB balance is invalid.');
        }
        if (amounts.any((amount) => amount != BigInt.zero)) return true;
        final history = await checked(() => _wallet.listTransfers(assetId: id));
        if (history.any((transfer) => !terminal(transfer.status))) return true;
      }
      return refreshed.transfers.values.any(
        (transfer) => !terminal(transfer.updatedStatus),
      );
    } finally {
      stopwatch.stop();
    }
  }

  @override
  Future<WalletBalance> getBalance(WalletAsset asset) async {
    final channels = _nativeLightningAvailable
        ? await _wallet.listChannels()
        : const <LightningChannel>[];
    if (asset.id.protocol == WalletAssetProtocol.bitcoin) {
      final (balance, node) = await (
        _wallet.getBtcBalance(),
        _wallet.getNodeInfo(),
      ).wait;
      return _balances.bitcoin(asset, balance, node, channels);
    }
    final rgb = await _rgbBalanceOrZero(asset.id.value);
    return _balances.rgb(asset, rgb, channels);
  }

  @override
  Future<List<WalletActivity>> listActivity(WalletAsset asset) async {
    try {
      final activities = <WalletActivity>[];
      if (asset.kind == WalletAssetKind.bitcoin) {
        final transactions = await _wallet.listTransactions();
        activities.addAll(
          transactions.map((item) => _activities.bitcoin(asset, item)),
        );
      } else {
        try {
          final transfers = await _wallet.listTransfers(
            assetId: asset.id.value,
          );
          activities.addAll(
            transfers.map((item) => _activities.rgb(asset, item)),
          );
        } catch (error) {
          if (!_isUnknownAssetFailure(error) ||
              await _isRgbAssetImported(asset.id.value)) {
            rethrow;
          }
        }
      }
      final payments = _nativeLightningAvailable
          ? await _wallet.listPayments()
          : const <LightningPayment>[];
      activities.addAll(
        payments
            .where((item) => _activities.paymentBelongsToAsset(item, asset))
            .map((item) => _activities.lightning(asset, item)),
      );
      return _activities.normalize(activities);
    } on ArgumentError {
      throw const NativeProtocolException(
        'Native wallet returned malformed activity data.',
        field: 'WalletActivity',
      );
    }
  }

  @override
  Future<String> getBitcoinAddress() async {
    final address = await _wallet.getAddress();
    final normalized = _bitcoinAddresses.normalizeAddress(
      address,
      _services.environment,
    );
    if (normalized == null) {
      throw const NativeProtocolException(
        'Native wallet returned an invalid Bitcoin address.',
        field: 'address',
      );
    }
    return normalized;
  }

  @override
  Future<WalletFeeRateEstimate> estimateFeeRate(int targetBlocks) async {
    if (targetBlocks < WalletFeeRateEstimate.minimumTargetBlocks ||
        targetBlocks > WalletFeeRateEstimate.maximumTargetBlocks) {
      throw const WalletValidationException(
        'Confirmation target is outside the supported range.',
        field: 'targetBlocks',
      );
    }
    // A local regtest chain has no fee market and Esplora may return no fee
    // estimates. This is an explicit test-chain policy, never an error fallback.
    if (_services.environment == BlockchainEnvironment.regtest) {
      return WalletFeeRateEstimate(
        targetBlocks: targetBlocks,
        satsPerVbyte: 1,
        observedAt: _clock().toUtc(),
        source: WalletFeeRateSource.localRegtestPolicy,
      );
    }
    final response = await _wallet.estimateFeeRate(targetBlocks);
    final nativeRate = response.feeRate;
    if (!nativeRate.isFinite ||
        nativeRate <= 0 ||
        nativeRate > WalletFeeRateEstimate.maximumSatsPerVbyte) {
      throw const NativeProtocolException(
        'Native wallet returned an invalid fee-rate estimate.',
        field: 'feeRate',
      );
    }
    final roundedRate = nativeRate.ceil();
    if (roundedRate > WalletFeeRateEstimate.maximumSatsPerVbyte) {
      throw const NativeProtocolException(
        'Native wallet returned an out-of-range fee-rate estimate.',
        field: 'feeRate',
      );
    }
    return WalletFeeRateEstimate(
      targetBlocks: targetBlocks,
      satsPerVbyte: roundedRate,
      observedAt: _clock().toUtc(),
    );
  }

  @override
  Future<WalletPaymentPreview> decodeInvoice(
    PaymentRoute route,
    String invoice,
  ) async {
    _requireConfiguredRoute(route);
    _requirePaymentInput(invoice, 'invoice');
    return switch (route.target) {
      WalletPaymentTarget.bitcoinOnchain =>
        throw const WalletValidationException(
          'Bitcoin on-chain destinations are addresses, not invoices.',
          field: 'invoice',
        ),
      WalletPaymentTarget.usdtOnchain => _decodeRgbInvoice(route, invoice),
      WalletPaymentTarget.bitcoinLightning ||
      WalletPaymentTarget.usdtLightning => _decodeLightningInvoice(
        route,
        invoice,
      ),
    };
  }

  @override
  Future<WalletReceiveRequest> createReceiveRequest(
    PaymentRoute route, {
    WalletAmount? amount,
  }) async {
    _requireConfiguredRoute(route);
    _requireOptionalAmount(route, amount);
    return switch (route.target) {
      WalletPaymentTarget.bitcoinOnchain => _createBitcoinReceive(
        route,
        amount,
      ),
      WalletPaymentTarget.bitcoinLightning ||
      WalletPaymentTarget.usdtLightning => _createLightningReceive(
        route,
        amount,
      ),
      WalletPaymentTarget.usdtOnchain => _createRgbReceive(route, amount),
    };
  }

  @override
  Future<WalletSendResult> sendPayment(WalletSendCommand command) async {
    try {
      final route = command.route;
      _requireConfiguredRoute(route);
      return await (switch (route.target) {
        WalletPaymentTarget.bitcoinOnchain => _sendBitcoin(command),
        WalletPaymentTarget.usdtOnchain => _sendRgb(command),
        WalletPaymentTarget.bitcoinLightning ||
        WalletPaymentTarget.usdtLightning => _sendLightning(command),
      });
    } catch (error, stackTrace) {
      if (_isConfirmedPaymentRejection(error)) {
        Error.throwWithStackTrace(
          WalletPaymentRejectedBeforeDispatchException(
            FailureMapper.from(error, stackTrace),
          ),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  @override
  Future<String> paymentOperationRequest(
    String operationId,
    WalletSendCommand command,
  ) => _withPaymentDeadline(() async {
    final prepared = await _recoverableCommand(
      operationId,
      command,
      requireFreshReview: true,
    );
    // An older binary must fail before the app creates a pending marker.
    // This read also prevents accidental reuse of a native operation identity.
    final status = await _wallet.onchainSendStatus(prepared);
    if (status.phase != RecoverableOnchainSendPhase.absent) {
      throw const WalletValidationException(
        'The payment identity is already in use. Try again.',
        field: 'operationId',
      );
    }
    return prepared.requestJson;
  });

  @override
  Future<void> validatePaymentOperationRequest(
    String request,
    String operationId,
    WalletSendCommand command,
  ) => _withPaymentDeadline(() async {
    final restored = RecoverableOnchainSendCommand.fromJson(request);
    // Re-decode the original invoice and compare every reviewed input. These
    // pure SDK inspection calls stay serialized after a deadline and preserve
    // mutation quarantine; never weaken intent binding to bypass that fence.
    final expected = await _recoverableCommand(
      operationId,
      command,
      requireFreshReview: false,
    );
    if (restored.requestJson == expected.requestJson) return;
    if (command.route.asset.kind == WalletAssetKind.usdt) {
      final preview = await _decodeRgbInvoice(
        command.route,
        command.destination,
      );
      if (preview.expiresAt == null &&
          _withoutDerivedExpiry(restored.requestJson) ==
              _withoutDerivedExpiry(expected.requestJson)) {
        // An amount-only RGB invoice may have no expiry of its own. The SDK
        // binds a concrete preparation deadline on first creation. Restore
        // retains that original deadline, including when already expired; it
        // must never extend it by recreating the default from today's clock.
        return;
      }
    }
    throw const NativeProtocolException(
      'Saved payment request does not match its reviewed intent.',
      field: 'paymentOperation',
    );
  });

  static String _withoutDerivedExpiry(String encoded) {
    // Both inputs have already passed the SDK's strict canonical restoration
    // and fingerprint checks. Ignore only the fallback deadline and its hash
    // for comparison; dispatch/status still receive the saved original bytes.
    final value = jsonDecode(encoded) as Map<String, Object?>;
    final request = value['request']! as Map<String, Object?>;
    request.remove('expirationTimestamp');
    request.remove('fingerprint');
    return jsonEncode(value);
  }

  Future<RecoverableOnchainSendCommand> _recoverableCommand(
    String operationId,
    WalletSendCommand command, {
    required bool requireFreshReview,
  }) async {
    _requireConfiguredRoute(command.route);
    if (command.route.rail != PaymentRail.onchain) {
      throw const UnsupportedWalletFeatureException(
        'Durable payment recovery supports on-chain sends only.',
        feature: 'recoverableOnchainSend',
      );
    }
    if (requireFreshReview) _requireReviewedOnchainFee(command);
    final fee = command.feeRate;
    if (fee == null) {
      throw const AppFailureException(walletFeeReviewRequiredFailure);
    }
    if (command.route.asset.kind == WalletAssetKind.bitcoin) {
      final address = _bitcoinAddresses.normalizeAddress(
        command.destination,
        _services.environment,
      );
      if (address == null) {
        throw const WalletValidationException(
          'Check the Bitcoin recipient.',
          field: 'destination',
        );
      }
      return _wallet.createRecoverableBtcSendCommand(
        operationId: operationId,
        amount: command.amount.units,
        address: address,
        feeRate: fee.satsPerVbyte.toDouble(),
      );
    }
    final preview = await _decodeRgbInvoice(command.route, command.destination);
    _requireMatchingAmount(preview, command.amount);
    if (requireFreshReview) _requireNotExpired(preview);
    if (command.rgbRecipientType != preview.rgbRecipientType ||
        command.witnessBitcoinAmountSats != preview.witnessBitcoinAmountSats) {
      throw const WalletValidationException(
        'The RGB recipient no longer matches the reviewed payment.',
        field: 'recipientType',
      );
    }
    return _wallet.createRecoverableRgbSendCommand(
      operationId: operationId,
      request: RgbSendRequest(
        invoice: command.destination,
        assetId: command.route.asset.id.value,
        amount: command.amount.units,
        feeRate: fee.satsPerVbyte.toDouble(),
        witnessAmountSat: command.witnessBitcoinAmountSats,
      ),
    );
  }

  @override
  Future<WalletPaymentRecoveryStatus> preparePaymentOperation(String request) =>
      _withPaymentDeadline(
        () async => _recoveryStatus(
          await _wallet.prepareOnchainSend(
            RecoverableOnchainSendCommand.fromJson(request),
          ),
        ),
      );

  @override
  Future<WalletPaymentRecoveryStatus> commitPaymentOperation(String request) =>
      _withPaymentDeadline(
        () async => _recoveryStatus(
          await _wallet.commitOnchainSend(
            RecoverableOnchainSendCommand.fromJson(request),
          ),
        ),
      );

  Future<T> _withPaymentDeadline<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on RlnOperationTimeoutException {
      _requiresPaymentReopen = true;
      rethrow;
    }
  }

  @override
  Future<WalletPaymentRecoveryStatus> inspectPaymentOperation(String request) =>
      _withPaymentDeadline(
        () async => _recoveryStatus(
          await _wallet.onchainSendStatus(
            RecoverableOnchainSendCommand.fromJson(request),
          ),
        ),
      );

  @override
  Future<WalletPaymentRecoveryStatus> cancelPaymentOperation(String request) =>
      _withPaymentDeadline(
        () async => _recoveryStatus(
          await _wallet.cancelOnchainSend(
            RecoverableOnchainSendCommand.fromJson(request),
          ),
        ),
      );

  static WalletPaymentRecoveryStatus _recoveryStatus(
    RecoverableOnchainSendStatus status,
  ) => WalletPaymentRecoveryStatus(
    phase: WalletPaymentRecoveryPhase.values.byName(status.phase.name),
    endAuthorized: status.endAuthorized,
    referenceId: status.txid,
    batchTransferIndex: status.batchTransferIndex,
    failureCode: status.failureCode,
  );

  Future<WalletReceiveRequest> _createBitcoinReceive(
    PaymentRoute route,
    WalletAmount? amount,
  ) async {
    final address = await getBitcoinAddress();
    final encoded = amount == null
        ? address
        : Uri(
            scheme: 'bitcoin',
            path: address,
            queryParameters: <String, String>{
              'amount': _formatBitcoinUriAmount(amount.units),
            },
          ).toString();
    return WalletReceiveRequest(
      route: route,
      encodedRequest: _nativeQrPaymentValue(
        encoded,
        'BitcoinReceiveRequest.encodedRequest',
      ),
      displayValue: address,
      amount: amount,
    );
  }

  Future<WalletReceiveRequest> _createLightningReceive(
    PaymentRoute route,
    WalletAmount? amount,
  ) async {
    final WalletAmount? requestedAmount = amount;
    final LightningReceiveRequest response;
    if (route.asset.kind == WalletAssetKind.bitcoin) {
      if (requestedAmount != null && requestedAmount.subSatoshiRemainder != 0) {
        throw const WalletValidationException(
          'Lightning invoice creation requires whole satoshis.',
          field: 'amount',
        );
      }
      response = await _wallet.createLightningInvoice(
        amountSats: requestedAmount?.wholeAssetUnits,
        expirySeconds: _receiveLifetime.inSeconds,
      );
    } else {
      response = await _wallet.createLightningInvoice(
        asset: requestedAmount == null
            ? null
            : LightningAsset(
                assetId: route.asset.id.value,
                amount: requestedAmount.units,
              ),
        expirySeconds: _receiveLifetime.inSeconds,
      );
    }
    final invoice = _nativeQrPaymentValue(
      response.lnInvoice,
      'LightningReceiveRequest.lnInvoice',
    );
    final preview = await _decodeLightningInvoice(route, invoice);
    if (preview.amount != requestedAmount) {
      throw const NativeProtocolException(
        'Created Lightning invoice amount does not match the request.',
        field: 'DecodedLightningInvoice.amount',
      );
    }
    return WalletReceiveRequest(
      route: route,
      encodedRequest: preview.encodedDestination,
      displayValue: preview.displayDestination,
      amount: preview.amount,
      expiresAt: preview.expiresAt,
      referenceId: preview.referenceId,
    );
  }

  Future<WalletReceiveRequest> _createRgbReceive(
    PaymentRoute route,
    WalletAmount? amount,
  ) async {
    final assetImported = await _isRgbAssetImported(route.asset.id.value);
    // Receiving never spends Bitcoin or requires pre-existing allocation slots.
    // The sender creates the witness output. Blind recipient decoding remains
    // supported for sends to other wallets and historical receive records.
    final response = await _wallet.onchainReceive(
      RgbInvoiceRequest(
        assetId: assetImported ? route.asset.id.value : null,
        amount: assetImported ? amount?.units : null,
        durationSeconds: _receiveLifetime.inSeconds,
        witness: true,
      ),
    );
    final invoice = _nativeQrPaymentValue(
      response.invoice,
      'OnchainReceiveResponse.invoice',
    );
    final nativeRecipient = _nativeValues.optionalIdentifier(
      response.recipientId,
      'OnchainReceiveResponse.recipientId',
    );
    final batchTransferIndex = _nativeValues.optionalIndex(
      response.batchTransferIdx,
      'OnchainReceiveResponse.batchTransferIdx',
    );
    final preview = await _decodeRgbInvoice(route, invoice);
    if (preview.rgbRecipientType != RgbRecipientType.witness ||
        (assetImported ? preview.amount != amount : preview.amount != null) ||
        (nativeRecipient != null && preview.referenceId != nativeRecipient)) {
      throw const NativeProtocolException(
        'Created RGB invoice does not match the request.',
        field: 'CoreInvoiceData',
      );
    }
    final responseExpiry = _nativeValues.optionalUnixSeconds(
      response.expirationTimestamp,
      'OnchainReceiveResponse.expirationTimestamp',
    );
    if (responseExpiry != null && responseExpiry != preview.expiresAt) {
      throw const NativeProtocolException(
        'Created RGB invoice expiry is inconsistent.',
        field: 'OnchainReceiveResponse.expirationTimestamp',
      );
    }
    return WalletReceiveRequest(
      route: route,
      encodedRequest: preview.encodedDestination,
      displayValue: preview.displayDestination,
      // A first-transfer invoice cannot bind an asset or amount until the
      // receiver imports the contract from its first consignment.
      amount: assetImported ? preview.amount : null,
      expiresAt: preview.expiresAt ?? responseExpiry,
      referenceId: preview.referenceId,
      batchTransferIndex: batchTransferIndex,
    );
  }

  Future<WalletPaymentPreview> _decodeRgbInvoice(
    PaymentRoute route,
    String invoice,
  ) async {
    final decoded = await _wallet.decodeRgbInvoice(invoice);
    final recipientType = switch (decoded.recipientType) {
      'Blind' => RgbRecipientType.blind,
      'Witness' => RgbRecipientType.witness,
      _ => throw const NativeProtocolException(
        'Unknown RGB recipient type.',
        field: 'CoreInvoiceData.recipientType',
      ),
    };
    _requireNativeEnvironment(decoded.network, 'CoreInvoiceData.network');
    if (decoded.assignment.type != 'Fungible' &&
        decoded.assignment.type != 'Any') {
      throw const WalletValidationException(
        'This wallet only supports fungible USDT payments.',
        field: 'CoreInvoiceData.assignment.type',
      );
    }
    final encodedAssetId = decoded.assetId;
    if (encodedAssetId != null && encodedAssetId != route.asset.id.value) {
      throw const WalletValidationException(
        'RGB invoice asset does not match the selected asset.',
        field: 'CoreInvoiceData.assetId',
      );
    }
    if (encodedAssetId == null && decoded.assignment.amount != null) {
      throw const NativeProtocolException(
        'Asset-less RGB invoice unexpectedly binds an amount.',
        field: 'CoreInvoiceData.assignment.amount',
      );
    }
    final amount = decoded.assignment.amount == null
        ? null
        : _nativeValues.amount(
            route,
            _nativeValues.exactUnits(
              decoded.assignment.amount!,
              'CoreInvoiceData.assignment.amount',
            ),
            'CoreInvoiceData.assignment.amount',
          );
    return WalletPaymentPreview(
      route: route,
      encodedDestination: invoice,
      displayDestination: invoice,
      rgbRecipientType: recipientType,
      amount: amount,
      expiresAt: _nativeValues.optionalUnixSeconds(
        decoded.expirationTimestamp,
        'CoreInvoiceData.expirationTimestamp',
      ),
      referenceId: _nativeValues.optionalIdentifier(
        decoded.recipientId,
        'CoreInvoiceData.recipientId',
      ),
    );
  }

  Future<CoreAssetBalance> _rgbBalanceOrZero(String assetId) async {
    try {
      return await _wallet.getAssetBalance(assetId);
    } catch (error) {
      if (!_isUnknownAssetFailure(error) ||
          await _isRgbAssetImported(assetId)) {
        rethrow;
      }
      return CoreAssetBalance(
        settled: BigInt.zero,
        future: BigInt.zero,
        spendable: BigInt.zero,
        offchainOutbound: BigInt.zero,
        offchainInbound: BigInt.zero,
      );
    }
  }

  Future<bool> _isRgbAssetImported(String assetId) async {
    final assets = await _wallet.listAssets();
    return assets.assetIds.contains(assetId);
  }

  static bool _isUnknownAssetFailure(Object error) =>
      error is NotFoundError || error is RgbNodeError;

  Future<WalletPaymentPreview> _decodeLightningInvoice(
    PaymentRoute route,
    String invoice,
  ) async {
    final decoded = await _wallet.decodeLnInvoice(invoice);
    _requireNativeEnvironment(
      decoded.network,
      'DecodedLightningInvoice.network',
    );
    final WalletAmount? amount;
    if (route.asset.kind == WalletAssetKind.bitcoin) {
      if (decoded.assetId != null || decoded.assetAmount != null) {
        throw const WalletValidationException(
          'RGB Lightning invoice does not match Bitcoin.',
          field: 'DecodedLightningInvoice.assetId',
        );
      }
      amount = decoded.amtMsat == null
          ? null
          : _nativeValues.amount(
              route,
              decoded.amtMsat!,
              'DecodedLightningInvoice.amtMsat',
            );
    } else {
      if (decoded.assetId != route.asset.id.value ||
          decoded.assetAmount == null) {
        throw const WalletValidationException(
          'Lightning invoice asset does not match the selected asset.',
          field: 'DecodedLightningInvoice.assetId',
        );
      }
      amount = _nativeValues.amount(
        route,
        _nativeValues.exactUnits(
          decoded.assetAmount!,
          'DecodedLightningInvoice.assetAmount',
        ),
        'DecodedLightningInvoice.assetAmount',
      );
    }
    final createdAt = _nativeValues.unixSeconds(
      decoded.timestamp,
      'DecodedLightningInvoice.timestamp',
    );
    final expiresAt = _nativeValues.addSeconds(
      createdAt,
      decoded.expirySec,
      'DecodedLightningInvoice.expirySec',
    );
    return WalletPaymentPreview(
      route: route,
      encodedDestination: invoice,
      displayDestination: invoice,
      amount: amount,
      expiresAt: expiresAt,
      referenceId: _nativeValues.identifier(
        decoded.paymentHash,
        'DecodedLightningInvoice.paymentHash',
      ),
    );
  }

  Future<WalletSendResult> _sendBitcoin(WalletSendCommand command) async {
    final address = _bitcoinAddresses.normalizeAddress(
      command.destination,
      _services.environment,
    );
    if (address == null) {
      throw const WalletValidationException(
        'Bitcoin destination is malformed or belongs to another network.',
        field: 'destination',
      );
    }
    _requireReviewedOnchainFee(command);
    return _runPaymentMutation(() async {
      final txid = await _wallet.sendBtc(
        amount: command.amount.units,
        address: address,
        feeRate: command.feeRate!.satsPerVbyte.toDouble(),
      );
      return WalletSendResult(
        route: command.route,
        amount: command.amount,
        referenceId: _nativeValues.identifier(txid, 'sendBtc.txid'),
        status: WalletPaymentStatus.pending,
      );
    });
  }

  Future<T> _runPaymentMutation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      if (_isConfirmedPaymentRejection(error)) rethrow;
      Error.throwWithStackTrace(
        WalletMutationOutcomeUnknownException(
          FailureMapper.diagnosticCause(error),
        ),
        stackTrace,
      );
    }
  }

  static bool _isConfirmedPaymentRejection(Object error) {
    return error is WalletValidationException ||
        (error is UnsupportedWalletFeatureException && error.cause == null) ||
        error is AppConfigurationException;
  }

  void _requireReviewedOnchainFee(WalletSendCommand command) {
    final fee = command.feeRate;
    if (fee == null ||
        fee.isStaleAt(_clock()) ||
        (fee.source == WalletFeeRateSource.localRegtestPolicy &&
            _services.environment != BlockchainEnvironment.regtest)) {
      throw const AppFailureException(walletFeeReviewRequiredFailure);
    }
  }

  Future<WalletSendResult> _sendRgb(WalletSendCommand command) async {
    final preview = await _decodeRgbInvoice(command.route, command.destination);
    _requireMatchingAmount(preview, command.amount);
    _requireNotExpired(preview);
    if (command.rgbRecipientType != preview.rgbRecipientType ||
        command.witnessBitcoinAmountSats != preview.witnessBitcoinAmountSats) {
      throw const WalletValidationException(
        'The RGB recipient or reviewed Bitcoin output changed. Review the payment again.',
        field: 'recipientType',
      );
    }
    _requireReviewedOnchainFee(command);
    return _runPaymentMutation(() async {
      final response = await _wallet.onchainSend(
        RgbSendRequest(
          invoice: command.destination,
          assetId: command.route.asset.id.value,
          amount: command.amount.units,
          feeRate: command.feeRate!.satsPerVbyte.toDouble(),
          witnessAmountSat: command.witnessBitcoinAmountSats,
        ),
      );
      return WalletSendResult(
        route: command.route,
        amount: command.amount,
        referenceId: _nativeValues.identifier(
          response.txid,
          'OnchainSendResponse.txid',
        ),
        status: WalletPaymentStatus.pending,
        batchTransferIndex: _nativeValues.optionalIndex(
          response.batchTransferIdx,
          'OnchainSendResponse.batchTransferIdx',
        ),
      );
    });
  }

  Future<WalletSendResult> _sendLightning(WalletSendCommand command) async {
    final preview = await _decodeLightningInvoice(
      command.route,
      command.destination,
    );
    _requireMatchingAmount(preview, command.amount);
    _requireNotExpired(preview);
    final isBitcoin = command.route.asset.kind == WalletAssetKind.bitcoin;
    if (isBitcoin &&
        preview.amount == null &&
        command.amount.subSatoshiRemainder != 0) {
      throw const WalletValidationException(
        'Amountless Lightning invoices require whole satoshis.',
        field: 'amount',
      );
    }
    return _runPaymentMutation(() async {
      final response = await _wallet.payLightningInvoice(
        lnInvoice: command.destination,
        amount: isBitcoin && preview.amount == null
            ? command.amount.wholeAssetUnits
            : null,
        assetId: isBitcoin ? null : command.route.asset.id.value,
        assetAmount: isBitcoin ? null : command.amount.units,
      );
      return WalletSendResult(
        route: command.route,
        amount: command.amount,
        referenceId: _nativeValues.identifier(
          response.txid,
          'LightningSendRequest.txid',
        ),
        status: _nativeValues.paymentStatus(response.status),
      );
    });
  }

  void _requireConfiguredRoute(PaymentRoute route) {
    if (route.asset.kind == WalletAssetKind.bitcoin) {
      if (route.asset != WalletAsset.bitcoin) {
        throw const AppConfigurationException();
      }
      return;
    }
    final configured = _services.usdtAsset;
    if (configured == null ||
        route.asset.id.value != configured.contractId ||
        route.asset.precision != configured.precision) {
      throw const AppConfigurationException();
    }
  }

  static void _requireOptionalAmount(PaymentRoute route, WalletAmount? amount) {
    if (amount == null) {
      if (route.target.requiresReceiveAmount) {
        throw const WalletValidationException(
          'RGB Lightning invoices require an asset amount.',
          field: 'amount',
        );
      }
      return;
    }
    if (amount.assetId != route.asset.id || amount.rail != route.rail) {
      throw const WalletValidationException(
        'Payment amount does not match the selected route.',
        field: 'amount',
      );
    }
    if (amount.isZero) {
      throw const WalletValidationException(
        'Payment amount must be positive when provided.',
        field: 'amount',
      );
    }
  }

  static void _requirePaymentInput(String value, String field) {
    if (!_isValidPaymentValue(value)) {
      throw WalletValidationException(
        'Payment destination is malformed.',
        field: field,
      );
    }
  }

  static String _nativeQrPaymentValue(String value, String field) {
    if (!WalletProtocolText.isQrPayload(value)) {
      throw NativeProtocolException(
        'Native wallet returned a payment request that cannot be encoded as QR.',
        field: field,
      );
    }
    return value;
  }

  static bool _isValidPaymentValue(String value) =>
      WalletProtocolText.isEncodedValue(value);

  static void _requireMatchingAmount(
    WalletPaymentPreview preview,
    WalletAmount amount,
  ) {
    final encodedAmount = preview.amount;
    if (encodedAmount != null && encodedAmount != amount) {
      throw const WalletValidationException(
        'Entered amount does not match the invoice.',
        field: 'amount',
      );
    }
  }

  void _requireNotExpired(WalletPaymentPreview preview) {
    if (preview.isExpiredAt(_clock())) {
      throw const WalletValidationException(
        'The payment request has expired.',
        field: 'invoice',
      );
    }
  }

  void _requireNativeEnvironment(String raw, String field) {
    if (raw.isEmpty || raw != raw.trim()) {
      throw NativeProtocolException(
        'Native payment request has a malformed network.',
        field: field,
      );
    }
    final BlockchainEnvironment environment;
    try {
      environment = _nativeValues.environment(raw);
    } on AppConfigurationException {
      throw NativeProtocolException(
        'Native payment request has an unknown network.',
        field: field,
      );
    }
    if (environment != _services.environment) {
      throw WalletValidationException(
        'Payment request belongs to a different network.',
        field: field,
      );
    }
  }

  static String _formatBitcoinUriAmount(int satoshis) {
    const satsPerBitcoin = 100000000;
    final whole = satoshis ~/ satsPerBitcoin;
    final remainder = satoshis.remainder(satsPerBitcoin);
    if (remainder == 0) return whole.toString();
    final fraction = remainder
        .toString()
        .padLeft(8, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '$whole.$fraction';
  }

  static DateTime _utcNow() => DateTime.now().toUtc();

  @override
  Future<WalletNetworkStatus> getNetworkStatus() async {
    final network = await _wallet.getNetworkInfo();
    if (network.network.isEmpty || network.network != network.network.trim()) {
      throw const NativeProtocolException(
        'Native wallet returned a malformed network.',
        field: 'WalletNetworkInfo.network',
      );
    }
    final BlockchainEnvironment nativeEnvironment;
    try {
      nativeEnvironment = _nativeValues.environment(network.network);
    } on AppConfigurationException {
      throw NativeProtocolException(
        'Native wallet returned an unknown network.',
        field: 'WalletNetworkInfo.network',
      );
    }
    if (nativeEnvironment != _services.environment) {
      throw NativeProtocolException(
        'Native wallet network does not match app configuration.',
        field: 'WalletNetworkInfo.network',
      );
    }
    final node = await _wallet.getNodeInfo();
    try {
      return WalletNetworkStatus(
        environment: nativeEnvironment,
        blockHeight: network.height,
        nodePublicKey: node.pubkey,
        channelCount: node.numChannels,
        usableChannelCount: node.numUsableChannels,
        peerCount: node.numPeers,
      );
    } on ArgumentError {
      throw const NativeProtocolException(
        'Native wallet returned invalid network or node metadata.',
        field: 'WalletNetworkStatus',
      );
    }
  }

  @override
  Future<WalletPublicKeys> getPublicKeys() async {
    final node = await _wallet.getNodeInfo();
    final bitcoin = node.accountXpubVanilla;
    final rgb = node.accountXpubColored;
    if (bitcoin == null || rgb == null) {
      throw const NativeProtocolException(
        'Wallet node did not return both account xpubs.',
        field: 'WalletNodeInfo.accountXpubs',
      );
    }
    try {
      return WalletPublicKeys(bitcoin: bitcoin, rgb: rgb);
    } on ArgumentError {
      throw const NativeProtocolException(
        'Wallet node returned malformed account xpubs.',
        field: 'WalletNodeInfo.accountXpubs',
      );
    }
  }
}
