part of 'rgb_wallet_engine.dart';

/// On-chain-only adapter. Factory and release qualification remain gated.
///
/// Signing material is available only during a runtime-owned activation. The
/// SDK's reader cannot reopen a session after that scope has ended.
final class RgbLibWalletEngine
    implements
        WalletEngine,
        WalletMnemonicOpenEngine,
        WalletPaymentRecoveryEngine,
        WalletPaymentDiscoveryEngine,
        WalletDeletionSafetyEngine,
        RgbSetupWalletEngine {
  RgbLibWalletEngine(
    this._services, {
    required String storageDirectory,
    RgbLibWallet Function(RgbLibKeys keys)? walletFactory,
    DateTime Function()? clock,
    this._bitcoinAddresses = const BitcoinPaymentInstructionParser(),
    LocalNetworkAccess? localNetworkAccess,
    this._evmChainValidator = const HttpEvmChainValidator(),
  }) : _clock = clock ?? RgbWalletEngine._utcNow,
       _localNetworkAccess =
           localNetworkAccess ?? PlatformLocalNetworkAccess() {
    _services.validate();
    if (_services.backend != WalletBackend.rgbL1 ||
        _services.indexerUrl == null ||
        _services.rgbTransportProxy == null) {
      throw const AppConfigurationException();
    }
    final keys = RgbLibKeys.reader(() => _openingMnemonic);
    _wallet =
        walletFactory?.call(keys) ??
        RgbLibWallet(
          params: RgbLibWalletParams(
            network: _services.sdkNetwork,
            storageDirPath: storageDirectory,
          ),
          keys: keys,
        );
  }

  final WalletServiceConfiguration _services;
  final DateTime Function() _clock;
  final BitcoinAddressValidator _bitcoinAddresses;
  final LocalNetworkAccess _localNetworkAccess;
  final EvmChainValidator _evmChainValidator;
  late final RgbLibWallet _wallet;
  String? _openingMnemonic;
  bool _assetReady = false;
  bool _activating = false;

  @override
  Future<void> provision({
    required String databasePassword,
    required String mnemonic,
  }) => _activate(mnemonic, reopen: false);

  @override
  Future<void> openPersisted({required String databasePassword}) =>
      Future.error(
        const AppFailureException(
          AppFailure(
            code: 'wallet_signing_material_required',
            kind: AppFailureKind.authentication,
            userMessage: 'The wallet must be reopened securely.',
            retryable: false,
          ),
        ),
      );

  @override
  Future<void> openPersistedWithMnemonic({
    required String databasePassword,
    required String mnemonic,
  }) => _activate(mnemonic, reopen: true);

  Future<void> _activate(String mnemonic, {required bool reopen}) async {
    if (_activating) throw const AppConfigurationException();
    _activating = true;
    _assetReady = false;
    try {
      await _localNetworkAccess.ensureFor(_services);
      await _evmChainValidator.verify(_services);
      final runtime = await RgbLibWallet.getRuntimeInfo();
      if (!runtime.durableOnchainRecovery ||
          (_services.usdtAsset != null && !runtime.contractRegistration)) {
        throw const AppFailureException(
          AppFailure(
            code: 'wallet_backend_capability_unavailable',
            kind: AppFailureKind.configuration,
            userMessage: 'This wallet format is unavailable in this build.',
            retryable: false,
          ),
        );
      }
      _openingMnemonic = mnemonic;
      try {
        if (reopen) {
          await _wallet.reinit();
        } else {
          await _wallet.init();
        }
      } finally {
        // Registration/online RPC work needs the native owner, not another
        // read of the recovery phrase. End the reader scope immediately.
        _openingMnemonic = null;
      }
      // Import verifies public genesis only; it never authorizes a payment or
      // credits an allocation. Exact native metadata is checked again below.
      await _bootstrapContract();
      final chain = _services.ethChainId;
      final rpc = _services.ethRpcUrl;
      final policy = _services.bfaMintLockPolicy;
      await _wallet.unlock(
        RgbLibUnlockParams(
          indexerUrl: _services.indexerUrl,
          proxyEndpoint: _services.rgbTransportProxy,
          evmChains: chain == null || rpc == null || policy == null
              ? const {}
              : {
                  chain: RgbLibEvmChain(
                    rpcUrl: rpc,
                    minMintLockBlocks: policy.minimumBlocks,
                    maxMintLockBlocks: policy.maximumBlocks,
                  ),
                },
        ),
      );
      _assetReady = _services.usdtAsset != null;
    } finally {
      _openingMnemonic = null;
      _activating = false;
    }
  }

  Future<void> _bootstrapContract() async {
    final asset = _services.usdtAsset;
    if (asset == null) return;
    final approved = asset.canonicalContract;
    if (approved == null) throw const AppConfigurationException();
    approved.validate();
    RgbLibAssetMetadata? metadata;
    try {
      metadata = await _wallet.getAssetMetadata(asset.contractId);
    } on RgbLibWalletException catch (error) {
      if (error.code != 'ASSET_NOT_FOUND') rethrow;
    }
    if (metadata == null) {
      final imported = await _wallet.importContract(
        contractBase64: approved.contractBase64,
        expectedAssetId: asset.contractId,
      );
      if (imported.assetId != asset.contractId ||
          imported.assetSchema != 'Bfa' ||
          imported.name != approved.nativeName ||
          imported.ticker != approved.nativeTicker ||
          imported.precision != asset.precision) {
        throw const NativeProtocolException(
          'Imported contract does not match the approved asset.',
          field: 'importContract',
        );
      }
      metadata = await _wallet.getAssetMetadata(asset.contractId);
    }
    if (metadata.assetSchema != RgbLibAssetSchema.bfa ||
        metadata.name != approved.nativeName ||
        metadata.ticker != approved.nativeTicker ||
        metadata.precision != asset.precision) {
      throw const NativeProtocolException(
        'Native metadata does not match the approved asset.',
        field: 'getAssetMetadata',
      );
    }
  }

  @override
  Future<void> sync() async {
    await _wallet.syncWallet();
    await _wallet.refreshWallet();
  }

  @override
  Future<void> shutdown() async {
    _assetReady = false;
    await _wallet.shutdown();
  }

  @override
  Future<void> destroy() async {
    _assetReady = false;
    _openingMnemonic = null;
    await _wallet.destroy();
  }

  @override
  Future<WalletBalance> getBalance(WalletAsset asset) async {
    _requireAsset(asset);
    final WalletAmount settled;
    final WalletAmount future;
    final WalletAmount spendable;
    final WalletAmount locked;
    if (asset.kind == WalletAssetKind.bitcoin) {
      final value = await _wallet.getBtcBalance();
      RgbWalletEngine._balances.validateBitcoin(value);
      final total = RgbWalletEngine._nativeValues.checkedAdd(
        value.vanilla.future,
        value.colored.future,
        'bitcoin.future',
      );
      settled = WalletAmount.onchain(
        assetId: asset.id,
        units: RgbWalletEngine._nativeValues.checkedAdd(
          value.vanilla.settled,
          value.colored.settled,
          'bitcoin.settled',
        ),
      );
      future = WalletAmount.onchain(assetId: asset.id, units: total);
      spendable = WalletAmount.onchain(
        assetId: asset.id,
        units: value.vanilla.spendable,
      );
      locked = WalletAmount.onchain(
        assetId: asset.id,
        units: RgbWalletEngine._nativeValues.checkedSubtract(
          total,
          value.vanilla.spendable,
          'bitcoin.locked',
        ),
      );
    } else {
      final value = await _wallet.getAssetBalance(asset.id.value);
      return RgbWalletEngine._balances.rgb(asset, value, const []);
    }
    final noLightning = WalletAmount.lightning(assetId: asset.id, units: 0);
    return WalletBalance(
      asset: asset,
      onchainSettled: settled,
      onchainFuture: future,
      onchainSpendable: spendable,
      onchainLocked: locked,
      lightningOwned: noLightning,
      lightningSpendable: noLightning,
      lightningReceivable: noLightning,
    );
  }

  @override
  Future<List<WalletActivity>> listActivity(WalletAsset asset) async {
    _requireAsset(asset);
    final activities = asset.kind == WalletAssetKind.bitcoin
        ? (await _wallet.listTransactions()).map(
            (row) => RgbWalletEngine._activities.bitcoin(asset, row),
          )
        : (await _wallet.listTransfers(assetId: asset.id.value))
              .map((row) => RgbWalletEngine._activities.rgb(asset, row));
    final normalized = RgbWalletEngine._activities.normalize(activities);
    return _withNativeAcceptedAmounts(asset, normalized);
  }

  /// Accepted native receipts preserve an approved gross self-send amount even
  /// if the independently stored app receipt is missing. They never create a
  /// history row or override native chain status, ownership, time or fees.
  Future<List<WalletActivity>> _withNativeAcceptedAmounts(
    WalletAsset asset,
    List<WalletActivity> activities,
  ) async {
    final receipts = await _acceptedNativeReceipts();
    final matches = <String, RgbLibOnchainSendReceipt>{};
    for (final receipt in receipts) {
      final belongs = asset.kind == WalletAssetKind.bitcoin
          ? receipt.kind == RecoverableOnchainSendKind.bitcoin
          : receipt.kind == RecoverableOnchainSendKind.rgb &&
                receipt.assetId == asset.id.value;
      if (belongs) {
        matches[_nativeReceiptKey(
              receipt.kind,
              receipt.assetId,
              receipt.txid,
              receipt.batchTransferIndex,
            )] =
            receipt;
      }
    }
    final used = <String>{};
    final result = <WalletActivity>[];
    for (final activity in activities) {
      final isSend =
          activity.rail == PaymentRail.onchain &&
          ((asset.kind == WalletAssetKind.bitcoin &&
                  activity.source == WalletActivitySource.bitcoinTransaction &&
                  (activity.operation == WalletActivityOperation.bitcoinSend ||
                      activity.operation ==
                          WalletActivityOperation.bitcoinSelfTransfer)) ||
              (asset.kind != WalletAssetKind.bitcoin &&
                  activity.source == WalletActivitySource.rgbTransfer &&
                  activity.operation == WalletActivityOperation.rgbSend));
      final receipt = isSend
          ? matches[_nativeReceiptKey(
              asset.kind == WalletAssetKind.bitcoin
                  ? RecoverableOnchainSendKind.bitcoin
                  : RecoverableOnchainSendKind.rgb,
              asset.kind == WalletAssetKind.bitcoin ? null : asset.id.value,
              activity.txid,
              activity.batchTransferIndex,
            )]
          : null;
      result.add(
        receipt == null
            ? activity
            : _withNativeReceipt(activity, receipt, used),
      );
    }
    return List.unmodifiable(result);
  }

  WalletActivity _withNativeReceipt(
    WalletActivity activity,
    RgbLibOnchainSendReceipt receipt,
    Set<String> used,
  ) {
    if (!used.add(receipt.operationId) ||
        (activity.recipientId != null &&
            activity.recipientId != receipt.recipientId)) {
      throw const NativeProtocolException(
        'Native accepted receipt conflicts with chain history.',
        field: 'sendReceipts',
      );
    }
    final amount = WalletAmount.onchain(
      assetId: activity.asset.id,
      units: RgbWalletEngine._nativeValues.exactUnits(
        receipt.amount,
        'sendReceipts.amount',
      ),
    );
    if (activity.amount != null && activity.amount != amount) {
      throw const NativeProtocolException(
        'Native accepted amount conflicts with chain history.',
        field: 'sendReceipts.amount',
      );
    }
    return activity.withReviewedAmount(amount);
  }

  static String _nativeReceiptKey(
    RecoverableOnchainSendKind kind,
    String? assetId,
    String? txid,
    int? batch,
  ) => jsonEncode([kind.name, assetId, txid, batch]);

  Future<List<RgbLibOnchainSendReceipt>> _acceptedNativeReceipts() async {
    const pageSize = 500;
    // Snapshot retries only repeat reads. They never prepare or dispatch.
    for (var attempt = 0; attempt < 2; attempt++) {
      final first = await _wallet.listOnchainSendReceipts(limit: pageSize);
      final receipts = [...first.receipts];
      var consistent = true;
      for (var offset = pageSize; offset < first.total; offset += pageSize) {
        final page = await _wallet.listOnchainSendReceipts(
          offset: offset,
          limit: pageSize,
        );
        if (page.revision != first.revision ||
            page.total != first.total ||
            page.walletBinding != first.walletBinding ||
            page.recoveryCohort != first.recoveryCohort ||
            page.restoredSnapshot != first.restoredSnapshot ||
            page.offset != offset) {
          consistent = false;
          break;
        }
        receipts.addAll(page.receipts);
      }
      if (!consistent) continue;
      final operations = <String>{};
      final identities = <String>{};
      for (final receipt in receipts) {
        if (!operations.add(receipt.operationId) ||
            !identities.add(
              _nativeReceiptKey(
                receipt.kind,
                receipt.assetId,
                receipt.txid,
                receipt.batchTransferIndex,
              ),
            )) {
          throw const NativeProtocolException(
            'Duplicate native accepted receipt identity.',
            field: 'sendReceipts',
          );
        }
      }
      return List.unmodifiable(receipts);
    }
    throw const AppFailureException(walletActivityConsistencyFailure);
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
    final local = _services.environment == BlockchainEnvironment.regtest;
    final rate = local ? 1 : await _wallet.estimateFeeRate(targetBlocks);
    return WalletFeeRateEstimate(
      targetBlocks: targetBlocks,
      satsPerVbyte: rate,
      observedAt: _clock().toUtc(),
      source: local
          ? WalletFeeRateSource.localRegtestPolicy
          : WalletFeeRateSource.networkEstimate,
    );
  }

  @override
  Future<String> getBitcoinAddress() async {
    final address = _bitcoinAddresses.normalizeAddress(
      await _wallet.getAddress(),
      _services.environment,
    );
    if (address == null) {
      throw const NativeProtocolException(
        'Native wallet returned an invalid Bitcoin address.',
        field: 'address',
      );
    }
    return address;
  }

  @override
  Future<WalletPaymentPreview> decodeInvoice(
    PaymentRoute route,
    String invoice,
  ) async {
    _requireRoute(route);
    if (route.target != WalletPaymentTarget.usdtOnchain) {
      throw const WalletValidationException(
        'Bitcoin destinations must be addresses.',
        field: 'invoice',
      );
    }
    RgbWalletEngine._requirePaymentInput(invoice, 'invoice');
    final decoded = await _wallet.decodeRgbInvoice(invoice);
    final environment = RgbWalletEngine._nativeValues.environment(
      decoded.network,
    );
    if (environment != _services.environment) {
      throw const WalletValidationException(
        'Payment request belongs to a different network.',
        field: 'network',
      );
    }
    if ((decoded.assetId != null && decoded.assetId != route.asset.id.value) ||
        (decoded.assignment.type != 'Any' &&
            decoded.assignment.type != 'Fungible') ||
        (decoded.assetId == null && decoded.assignment.amount != null)) {
      throw const WalletValidationException(
        'Invoice does not match the selected asset.',
        field: 'assetId',
      );
    }
    final recipientType = switch (decoded.recipientType) {
      'Witness' => RgbRecipientType.witness,
      'Blind' => RgbRecipientType.blind,
      _ => throw const NativeProtocolException(
        'Native invoice recipient is invalid.',
        field: 'recipientType',
      ),
    };
    final rawAmount = decoded.assignment.amount;
    return WalletPaymentPreview(
      route: route,
      encodedDestination: invoice,
      displayDestination: invoice,
      rgbRecipientType: recipientType,
      amount: rawAmount == null
          ? null
          : RgbWalletEngine._nativeValues.amount(
              route,
              RgbWalletEngine._nativeValues.exactUnits(rawAmount, 'amount'),
              'amount',
            ),
      expiresAt: RgbWalletEngine._nativeValues.optionalUnixSeconds(
        decoded.expirationTimestamp,
        'expirationTimestamp',
      ),
      referenceId: RgbWalletEngine._nativeValues.identifier(
        decoded.recipientId,
        'recipientId',
      ),
    );
  }

  @override
  Future<WalletReceiveRequest> createReceiveRequest(
    PaymentRoute route, {
    WalletAmount? amount,
  }) async {
    _requireRoute(route);
    RgbWalletEngine._requireOptionalAmount(route, amount);
    if (route.target == WalletPaymentTarget.bitcoinOnchain) {
      final address = await getBitcoinAddress();
      final encoded = amount == null
          ? address
          : Uri(
              scheme: 'bitcoin',
              path: address,
              queryParameters: {
                'amount': RgbWalletEngine._formatBitcoinUriAmount(amount.units),
              },
            ).toString();
      return WalletReceiveRequest(
        route: route,
        encodedRequest: RgbWalletEngine._nativeQrPaymentValue(
          encoded,
          'invoice',
        ),
        displayValue: address,
        amount: amount,
      );
    }
    final response = await _wallet.witnessReceive(
      assetId: route.asset.id.value,
      amount: amount == null ? null : BigInt.from(amount.units),
      durationSeconds: RgbWalletEngine._receiveLifetime.inSeconds,
    );
    final invoice = RgbWalletEngine._nativeQrPaymentValue(
      response.invoice,
      'invoice',
    );
    final preview = await decodeInvoice(route, invoice);
    final decoded = await _wallet.decodeRgbInvoice(invoice);
    if (decoded.assetId != route.asset.id.value ||
        preview.rgbRecipientType != RgbRecipientType.witness ||
        preview.amount != amount ||
        preview.referenceId != response.recipientId ||
        preview.expiresAt !=
            RgbWalletEngine._nativeValues.optionalUnixSeconds(
              response.expirationTimestamp,
              'expirationTimestamp',
            )) {
      throw const NativeProtocolException(
        'Created invoice does not match the requested payment.',
        field: 'receive',
      );
    }
    return WalletReceiveRequest(
      route: route,
      encodedRequest: invoice,
      displayValue: invoice,
      amount: amount,
      expiresAt: preview.expiresAt,
      referenceId: preview.referenceId,
      batchTransferIndex: RgbWalletEngine._nativeValues.optionalIndex(
        response.batchTransferIdx,
        'batchTransferIdx',
      ),
    );
  }

  /// Product sending always uses the app's durable orchestration; a direct
  /// one-shot call cannot bypass the persisted prepare/commit/recovery flow.
  @override
  Future<WalletSendResult> sendPayment(WalletSendCommand command) =>
      Future.error(
        const UnsupportedWalletFeatureException(
          'Use the durable payment operation flow.',
          feature: 'oneShotOnchainSend',
        ),
      );

  Future<RecoverableOnchainSendCommand> _command(
    String operationId,
    WalletSendCommand command, {
    required bool fresh,
  }) async {
    _requireRoute(command.route);
    final fee = command.feeRate;
    if (fee == null ||
        (fresh && fee.isStaleAt(_clock())) ||
        (fee.source == WalletFeeRateSource.localRegtestPolicy &&
            _services.environment != BlockchainEnvironment.regtest)) {
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
        address: address,
        amount: command.amount.units,
        feeRate: fee.satsPerVbyte.toDouble(),
      );
    }
    final preview = await decodeInvoice(command.route, command.destination);
    RgbWalletEngine._requireMatchingAmount(preview, command.amount);
    if (fresh && preview.isExpiredAt(_clock())) {
      throw const WalletValidationException(
        'The payment request has expired.',
        field: 'invoice',
      );
    }
    if (preview.rgbRecipientType != command.rgbRecipientType ||
        preview.witnessBitcoinAmountSats != command.witnessBitcoinAmountSats) {
      throw const WalletValidationException(
        'The recipient does not match the reviewed payment.',
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
      requireFreshInvoice: fresh,
    );
  }

  @override
  Future<String> paymentOperationRequest(
    String operationId,
    WalletSendCommand command,
  ) async {
    final request = await _command(operationId, command, fresh: true);
    final status = await _wallet.onchainSendStatus(request);
    if (status.phase != RecoverableOnchainSendPhase.absent) {
      throw const WalletValidationException(
        'Payment identity is already in use.',
        field: 'operationId',
      );
    }
    return request.requestJson;
  }

  @override
  Future<void> validatePaymentOperationRequest(
    String request,
    String operationId,
    WalletSendCommand command,
  ) async {
    final restored = RecoverableOnchainSendCommand.fromJson(request);
    final expected = await _command(operationId, command, fresh: false);
    if (restored.requestJson == expected.requestJson) return;
    if (command.route.asset.kind == WalletAssetKind.usdt &&
        (await decodeInvoice(command.route, command.destination)).expiresAt ==
            null &&
        RgbWalletEngine._withoutDerivedExpiry(restored.requestJson) ==
            RgbWalletEngine._withoutDerivedExpiry(expected.requestJson)) {
      return;
    }
    throw const NativeProtocolException(
      'Saved payment does not match its approved intent.',
      field: 'paymentOperation',
    );
  }

  @override
  Future<WalletPaymentRecoveryStatus> preparePaymentOperation(String request) =>
      _recover(request, _wallet.prepareOnchainSend);

  @override
  Future<WalletPaymentRecoveryStatus> commitPaymentOperation(String request) =>
      _recover(request, _wallet.commitOnchainSend);

  @override
  Future<WalletPaymentRecoveryStatus> inspectPaymentOperation(String request) =>
      _recover(request, _wallet.onchainSendStatus);

  @override
  Future<WalletPaymentRecoveryStatus> cancelPaymentOperation(String request) =>
      _recover(request, _wallet.cancelOnchainSend);

  Future<WalletPaymentRecoveryStatus> _recover(
    String request,
    Future<RecoverableOnchainSendStatus> Function(
      RecoverableOnchainSendCommand command,
    )
    operation,
  ) async => RgbWalletEngine._recoveryStatus(
    await operation(RecoverableOnchainSendCommand.fromJson(request)),
  );

  @override
  Future<List<WalletDiscoveredPaymentOperation>>
  discoverPendingPaymentOperations() async {
    final native = await _wallet.listPendingOnchainSends();
    return List.unmodifiable([
      for (final operation in native)
        WalletDiscoveredPaymentOperation(
          operationId: operation.operationId,
          request: operation.commandJson,
          command: _discoveredCommand(
            operation.command,
            observedAt: _clock().toUtc(),
          ),
          status: RgbWalletEngine._recoveryStatus(operation.status),
        ),
    ]);
  }

  @override
  Future<void> validateDiscoveredPaymentOperation(
    String request,
    String operationId,
    WalletSendCommand command,
  ) async {
    final restored = RecoverableOnchainSendCommand.fromJson(request);
    final identity = await _wallet.getWalletIdentity();
    if (restored.version != 3 ||
        restored.backend != 'RGB_L1' ||
        restored.operationId != operationId ||
        restored.network != _services.sdkNetwork ||
        restored.walletBinding != identity.id ||
        restored.recoveryCohort != identity.recoveryCohort ||
        command.feeRate?.source != WalletFeeRateSource.nativeRecovery ||
        _discoveredCommand(restored, observedAt: command.feeRate!.observedAt) !=
            command) {
      throw const NativeProtocolException(
        'Discovered payment does not match its native approval.',
        field: 'paymentOperation',
      );
    }
  }

  WalletSendCommand _discoveredCommand(
    RecoverableOnchainSendCommand command, {
    required DateTime observedAt,
  }) {
    final envelope = jsonDecode(command.requestJson) as Map<String, Object?>;
    final request = envelope['request']! as Map<String, Object?>;
    int units(String key) => RgbWalletEngine._nativeValues.exactUnits(
      BigInt.parse(request[key]! as String),
      'nativeRecovery.$key',
    );
    final rgb = command.kind == RecoverableOnchainSendKind.rgb;
    final WalletAsset asset;
    if (rgb) {
      final configured = _services.usdtAsset;
      if (configured == null || request['assetId'] != configured.contractId) {
        throw const AppConfigurationException();
      }
      asset = WalletAsset.rgbUsdt(
        assetId: configured.contractId,
        precision: configured.precision,
      );
      _requireAsset(asset);
    } else {
      asset = WalletAsset.bitcoin;
    }
    final witness = rgb && request['witnessAmountSat'] != null;
    return WalletSendCommand(
      route: PaymentRoute(asset: asset, rail: PaymentRail.onchain),
      destination: request[rgb ? 'recipientId' : 'address']! as String,
      amount: WalletAmount.onchain(assetId: asset.id, units: units('amount')),
      feeRate: WalletFeeRateEstimate(
        targetBlocks: null,
        satsPerVbyte: units('feeRate'),
        observedAt: observedAt,
        source: WalletFeeRateSource.nativeRecovery,
      ),
      rgbRecipientType: rgb
          ? (witness ? RgbRecipientType.witness : RgbRecipientType.blind)
          : null,
      witnessBitcoinAmountSats: witness ? units('witnessAmountSat') : null,
    );
  }

  @override
  Future<WalletNetworkStatus> getNetworkStatus() async {
    final network = await _wallet.getNetworkInfo();
    if (network.network != _services.sdkNetwork) {
      throw const NativeProtocolException(
        'Native wallet belongs to a different chain.',
        field: 'network',
      );
    }
    final identity = await _wallet.getWalletIdentity();
    return WalletNetworkStatus(
      environment: _services.environment,
      blockHeight: network.blockHeight,
      nodePublicKey: null,
      channelCount: null,
      usableChannelCount: null,
      peerCount: null,
      walletIdentity: identity.id,
    );
  }

  @override
  Future<WalletPublicKeys> getPublicKeys() async {
    final keys = await _wallet.getPublicKeys();
    return WalletPublicKeys(
      bitcoin: keys.accountXpubVanilla,
      rgb: keys.accountXpubColored,
    );
  }

  @override
  Future<RgbWalletSetupInventory> rgbSetupInventory() async {
    final unspents = await _wallet.listUnspents();
    if (unspents.length > 10000) {
      throw const NativeProtocolException(
        'Native output inventory is too large.',
        field: 'unspents',
      );
    }
    final outpoints = <String>{};
    var available = 0;
    for (final unspent in unspents) {
      final outpoint = unspent.utxo.outpoint;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(outpoint.txid) ||
          outpoint.vout < 0 ||
          outpoint.vout > 0xffffffff ||
          !outpoints.add('${outpoint.txid}:${outpoint.vout}') ||
          unspent.pendingBlinded < 0 ||
          unspent.utxo.btcAmount < 0) {
        throw const NativeProtocolException(
          'Native output inventory is invalid.',
          field: 'unspents',
        );
      }
      if (unspent.utxo.exists &&
          unspent.utxo.colorable &&
          unspent.rgbAllocations.isEmpty &&
          unspent.pendingBlinded == 0) {
        available++;
      }
    }
    final balance = await _wallet.getBtcBalance();
    RgbWalletEngine._balances.validateBitcoin(balance);
    final identity = await _wallet.getWalletIdentity();
    final runtime = await RgbLibWallet.getRuntimeInfo();
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'policy': 'aster-rgb-l1-setup-v1',
              'version': runtime.version,
              'revision': runtime.sourceRevision,
              'bridge': runtime.bridgeVersion,
              'integrationTree': runtime.integrationTree,
              'sourceManifest': runtime.sourceManifestSha256,
              'cohort': identity.recoveryCohort,
              'walletBinding': identity.id,
            }),
          ),
        )
        .toString();
    return RgbWalletSetupInventory(
      freeAllocationCount: available,
      vanillaSpendableSats: balance.vanilla.spendable,
      runtimeFingerprint: fingerprint,
      nodePublicKey: identity.id,
      identityKind: RgbSetupIdentityKind.nativeWallet,
    );
  }

  @override
  Future<List<RgbWalletSetupTransaction>> rgbSetupTransactions() async =>
      (await _wallet.listTransactions())
          .where((transaction) => transaction.transactionType == 'CreateUtxos')
          .map(
            (transaction) => RgbWalletSetupTransaction(
              txid: transaction.txid,
              confirmed: transaction.confirmationTime != null,
            ),
          )
          .toList(growable: false);

  @override
  Future<void> createRgbSetupOutputs(int feeRateSatPerVbyte) async {
    if (feeRateSatPerVbyte < 1 ||
        feeRateSatPerVbyte > WalletFeeRateEstimate.maximumSatsPerVbyte) {
      throw ArgumentError('Invalid reviewed fee rate.');
    }
    await _wallet.createUtxos(
      upTo: false,
      num: RgbWalletSetupReview.outputCount,
      size: RgbWalletSetupReview.outputValueSats,
      feeRate: feeRateSatPerVbyte,
    );
  }

  @override
  Future<bool> hasProtectedRgbState() async {
    final stopwatch = Stopwatch()..start();
    Future<T> checked<T>(Future<T> Function() read) async {
      void budget() {
        if (stopwatch.elapsed >= RgbWalletEngine.deletionAuditBudget) {
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

      budget();
      final value = await read();
      budget();
      return value;
    }

    bool terminal(String? status) =>
        status == CoreTransferStatuses.settled ||
        status == CoreTransferStatuses.failed;
    Future<RefreshTransfersResult> refresh() async {
      final value = await checked(_wallet.refreshTransfers);
      if (value.transfers.values.any((transfer) => transfer.failure != null)) {
        throw const NativeProtocolException(
          'Native transfers could not be checked.',
          field: 'refresh',
        );
      }
      return value;
    }

    Future<List<String>> assets() async {
      final inventory = await checked(_wallet.listAssets);
      final ids = inventory.assetIds.toList(growable: false);
      if (ids.length > 5000 || ids.toSet().length != ids.length) {
        throw const NativeProtocolException(
          'Native asset inventory is invalid.',
          field: 'assets',
        );
      }
      return ids;
    }

    Future<bool> allocations({bool includeReservations = true}) async {
      final unspents = await checked(_wallet.listUnspents);
      if (unspents.length > 10000) {
        throw const NativeProtocolException(
          'Native output inventory is too large.',
          field: 'unspents',
        );
      }
      final outpoints = <String>{};
      for (final unspent in unspents) {
        final point = unspent.utxo.outpoint;
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(point.txid) ||
            point.vout < 0 ||
            point.vout > 0xffffffff ||
            !outpoints.add('${point.txid}:${point.vout}') ||
            unspent.utxo.btcAmount < 0 ||
            unspent.pendingBlinded < 0) {
          throw const NativeProtocolException(
            'Native output inventory is invalid.',
            field: 'unspents',
          );
        }
        // Mint/inflation rights have zero fungible balance but still require
        // their local RGB state. Protect every allocation, including foreign
        // assets and incoming/unconfirmed assignments.
        if (unspent.rgbAllocations.isNotEmpty ||
            (includeReservations && unspent.pendingBlinded > 0)) {
          return true;
        }
      }
      return false;
    }

    try {
      if (await checked(_wallet.hasPendingOnchainSends)) return true;
      if (await allocations(includeReservations: false)) return true;
      var refreshed = await refresh();
      final transfers = <CoreTransfer>[];
      for (final id in await assets()) {
        transfers.addAll(
          await checked(() => _wallet.listTransfers(assetId: id)),
        );
      }
      final known = transfers
          .map((transfer) => transfer.batchTransferIdx)
          .whereType<int>()
          .toSet();
      var reconciled = false;
      if (refreshed.transfers.entries.any(
        (entry) =>
            !terminal(entry.value.updatedStatus) && !known.contains(entry.key),
      )) {
        // Native chooses only expired unfunded orphan receives. It cannot
        // resume, cancel or reauthorize any prepared/committing payment.
        await checked(() => _wallet.failTransfers(noAssetOnly: true));
        reconciled = true;
      }
      for (final transfer in transfers) {
        final expiry = transfer.expiration;
        if (transfer.status == CoreTransferStatuses.waitingCounterparty &&
            const {'ReceiveWitness', 'ReceiveBlind'}.contains(transfer.kind) &&
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
      for (final id in await assets()) {
        final balance = await checked(() => _wallet.getAssetBalance(id));
        final amounts = [balance.settled, balance.future, balance.spendable];
        if (amounts.any((amount) => amount < BigInt.zero)) {
          throw const NativeProtocolException(
            'Native asset balance is invalid.',
            field: 'balance',
          );
        }
        if (amounts.any((amount) => amount > BigInt.zero)) return true;
        if ((await checked(() => _wallet.listTransfers(assetId: id)))
            .any((transfer) => !terminal(transfer.status))) {
          return true;
        }
      }
      if (refreshed.transfers.values.any(
        (value) => !terminal(value.updatedStatus),
      )) {
        return true;
      }
      return await allocations() ||
          await checked(_wallet.hasPendingOnchainSends);
    } finally {
      stopwatch.stop();
    }
  }

  void _requireAsset(WalletAsset asset) {
    if (asset.kind == WalletAssetKind.bitcoin) {
      if (asset != WalletAsset.bitcoin) throw const AppConfigurationException();
      return;
    }
    final expected = _services.usdtAsset;
    if (!_assetReady ||
        expected == null ||
        expected.canonicalContract == null ||
        asset.id.value != expected.contractId ||
        asset.precision != expected.precision) {
      throw const AppConfigurationException();
    }
  }

  void _requireRoute(PaymentRoute route) {
    if (route.rail != PaymentRail.onchain) {
      throw const UnsupportedWalletFeatureException(
        'This wallet supports on-chain payments only.',
        feature: 'lightning',
      );
    }
    _requireAsset(route.asset);
  }
}
