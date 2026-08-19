import 'package:flutter/foundation.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/models/models.dart';
import '../../domain/validation/validation.dart';
import '../validation/validation.dart';
import 'rgb_wallet_activity_mapper.dart';
import 'rgb_wallet_balance_mapper.dart';
import 'rgb_wallet_native_value_parser.dart';
import 'wallet_engine.dart';

/// Resolves explicit deployment overrides and immutable-SDK endpoint defaults.
///
/// Composition must use the returned object for both runtime creation and
/// Settings presentation. This prevents the SDK adapter from contacting a
/// fallback endpoint that the app has neither validated nor disclosed.
abstract final class RgbWalletServiceConfigurationResolver {
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
      indexerUrl: indexerUrl,
      rgbTransportProxy: rgbTransportProxy,
      lspBaseUrl:
          configured.lspBaseUrl ??
          (configured.sdkNetwork == 'utexo' ? _utexoSignetLspBaseUrl : null),
      vssUrl: configured.vssUrl,
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
      utcClock = null;

  /// Production constructor for sharing the app-owned validation boundary.
  const RgbWalletEngineFactory.withAddresses(
    this._bitcoinAddresses, {
    this.utcClock,
  }) : _sdk = const RgbSdkFlutter();

  /// Test seam for proving stable-SDK forwarding without global state.
  const RgbWalletEngineFactory.withSdk(
    this._sdk, [
    this._bitcoinAddresses = const BitcoinPaymentInstructionParser(),
  ]) : utcClock = null;

  final RgbSdkFlutter _sdk;
  final BitcoinAddressValidator _bitcoinAddresses;

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
      ),
      clock: utcClock,
      bitcoinAddresses: _bitcoinAddresses,
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
final class RgbWalletEngine implements WalletEngine {
  RgbWalletEngine(
    this._wallet,
    this._services,
    this._unlockConfig, {
    DateTime Function()? clock,
    this._bitcoinAddresses = const BitcoinPaymentInstructionParser(),
  }) : _clock = clock ?? _utcNow;

  static const _receiveLifetime = Duration(hours: 1);
  static const _activities = RgbWalletActivityMapper();
  static const _balances = RgbWalletBalanceMapper();
  static const _nativeValues = RgbWalletNativeValueParser();

  final UtexoWallet _wallet;
  final WalletServiceConfiguration _services;
  final UtexoUnlockConfig _unlockConfig;
  final DateTime Function() _clock;
  final BitcoinAddressValidator _bitcoinAddresses;

  @override
  Future<void> initialize({
    required String databasePassword,
    String? mnemonic,
  }) async {
    await _wallet.init(password: databasePassword, mnemonic: mnemonic);
    await _wallet.unlock(password: databasePassword, config: _unlockConfig);
  }

  @override
  Future<void> reinitialize({required String databasePassword}) {
    return _wallet.reinit(
      password: databasePassword,
      unlockConfig: _unlockConfig,
    );
  }

  @override
  Future<void> sync() => _wallet.syncWallet();

  @override
  Future<void> shutdown() => _wallet.shutdown();

  @override
  Future<void> destroy() => _wallet.destroy();

  @override
  Future<WalletBalance> getBalance(WalletAsset asset) async {
    final channels = await _wallet.listChannels();
    if (asset.id.protocol == WalletAssetProtocol.bitcoin) {
      final (balance, node) = await (
        _wallet.getBtcBalance(),
        _wallet.getNodeInfo(),
      ).wait;
      return _balances.bitcoin(asset, balance, node, channels);
    }
    final rgb = await _wallet.getAssetBalance(asset.id.value);
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
        final transfers = await _wallet.listTransfers(assetId: asset.id.value);
        activities.addAll(
          transfers.map((item) => _activities.rgb(asset, item)),
        );
      }
      final payments = await _wallet.listPayments();
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
    final route = command.route;
    _requireConfiguredRoute(route);
    return switch (route.target) {
      WalletPaymentTarget.bitcoinOnchain => _sendBitcoin(command),
      WalletPaymentTarget.usdtOnchain => _sendRgb(command),
      WalletPaymentTarget.bitcoinLightning ||
      WalletPaymentTarget.usdtLightning => _sendLightning(command),
    };
  }

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
    final response = await _wallet.onchainReceive(
      RgbInvoiceRequest(
        assetId: route.asset.id.value,
        amount: amount?.units,
        durationSeconds: _receiveLifetime.inSeconds,
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
    if (preview.amount != amount ||
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
      amount: preview.amount,
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
    _requireNativeEnvironment(decoded.network, 'CoreInvoiceData.network');
    if (decoded.assetId != route.asset.id.value) {
      throw const WalletValidationException(
        'RGB invoice asset does not match the selected asset.',
        field: 'CoreInvoiceData.assetId',
      );
    }
    final amount = decoded.assignment.amount == null
        ? null
        : _nativeValues.amount(
            route,
            decoded.assignment.amount!,
            'CoreInvoiceData.assignment.amount',
          );
    return WalletPaymentPreview(
      route: route,
      encodedDestination: invoice,
      displayDestination: invoice,
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
        decoded.assetAmount!,
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

  Future<WalletSendResult> _sendRgb(WalletSendCommand command) async {
    final preview = await _decodeRgbInvoice(command.route, command.destination);
    _requireMatchingAmount(preview, command.amount);
    _requireNotExpired(preview);
    return _runPaymentMutation(() async {
      final response = await _wallet.onchainSend(
        RgbSendRequest(
          invoice: command.destination,
          assetId: command.route.asset.id.value,
          amount: command.amount.units,
          feeRate: command.feeRate!.satsPerVbyte.toDouble(),
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
