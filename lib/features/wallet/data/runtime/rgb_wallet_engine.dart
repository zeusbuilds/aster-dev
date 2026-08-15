import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/models/models.dart';
import '../../domain/validation/validation.dart';
import '../validation/validation.dart';
import 'wallet_engine.dart';

/// Resolves explicit deployment overrides and immutable-SDK endpoint defaults.
///
/// Composition must use the returned object for both runtime creation and
/// Settings presentation. This prevents the SDK adapter from contacting a
/// fallback endpoint that the app has neither validated nor disclosed.
abstract final class RgbWalletServiceConfigurationResolver {
  static const _utexoSignetLspBaseUrl = 'https://lsp-signet.utexo.com';

  static WalletServiceConfiguration resolve(
    WalletServiceConfiguration configured,
  ) {
    configured.validate();
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
    resolved.validate();
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
  static const _maximumUnixSeconds = 253402300799;

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
      return _bitcoinBalance(asset, balance, node, channels);
    }
    final rgb = await _wallet.getAssetBalance(asset.id.value);
    return _rgbBalance(asset, rgb, channels);
  }

  @override
  Future<List<WalletActivity>> listActivity(WalletAsset asset) async {
    try {
      final activities = <WalletActivity>[];
      if (asset.kind == WalletAssetKind.bitcoin) {
        final transactions = await _wallet.listTransactions();
        activities.addAll(
          transactions.map((item) => _bitcoinActivity(asset, item)),
        );
      } else {
        final transfers = await _wallet.listTransfers(assetId: asset.id.value);
        activities.addAll(transfers.map((item) => _rgbActivity(asset, item)));
      }
      final payments = await _wallet.listPayments();
      activities.addAll(
        payments
            .where((item) => _paymentBelongsToAsset(item, asset))
            .map((item) => _lightningActivity(asset, item)),
      );
      return _normalizeActivities(activities);
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
      encodedRequest: encoded,
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
    final invoice = _nativePaymentValue(
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
    final invoice = _nativePaymentValue(
      response.invoice,
      'OnchainReceiveResponse.invoice',
    );
    final nativeRecipient = _optionalNativeIdentifier(
      response.recipientId,
      'OnchainReceiveResponse.recipientId',
    );
    final batchTransferIndex = _optionalNativeIndex(
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
    final responseExpiry = _optionalUnixSeconds(
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
        : _nativeAmount(
            route,
            decoded.assignment.amount!,
            'CoreInvoiceData.assignment.amount',
          );
    return WalletPaymentPreview(
      route: route,
      encodedDestination: invoice,
      displayDestination: invoice,
      amount: amount,
      expiresAt: _optionalUnixSeconds(
        decoded.expirationTimestamp,
        'CoreInvoiceData.expirationTimestamp',
      ),
      referenceId: _optionalNativeIdentifier(
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
          : _nativeAmount(
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
      amount = _nativeAmount(
        route,
        decoded.assetAmount!,
        'DecodedLightningInvoice.assetAmount',
      );
    }
    final createdAt = _unixSeconds(
      decoded.timestamp,
      'DecodedLightningInvoice.timestamp',
    );
    if (decoded.expirySec < 0) {
      throw const NativeProtocolException(
        'Lightning invoice expiry must not be negative.',
        field: 'DecodedLightningInvoice.expirySec',
      );
    }
    final expiryMicros =
        BigInt.from(createdAt.microsecondsSinceEpoch) +
        BigInt.from(decoded.expirySec) * BigInt.from(1000000);
    if (expiryMicros >
        BigInt.from(_maximumUnixSeconds) * BigInt.from(1000000)) {
      throw const NativeProtocolException(
        'Lightning invoice expiry is outside supported bounds.',
        field: 'DecodedLightningInvoice.expirySec',
      );
    }
    final expiresAt = DateTime.fromMicrosecondsSinceEpoch(
      expiryMicros.toInt(),
      isUtc: true,
    );
    return WalletPaymentPreview(
      route: route,
      encodedDestination: invoice,
      displayDestination: invoice,
      amount: amount,
      expiresAt: expiresAt,
      referenceId: _nativeIdentifier(
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
        referenceId: _nativeIdentifier(txid, 'sendBtc.txid'),
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
        referenceId: _nativeIdentifier(
          response.txid,
          'OnchainSendResponse.txid',
        ),
        status: WalletPaymentStatus.pending,
        batchTransferIndex: _optionalNativeIndex(
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
        referenceId: _nativeIdentifier(
          response.txid,
          'LightningSendRequest.txid',
        ),
        status: _paymentStatus(response.status),
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
      if (route.target == WalletPaymentTarget.usdtLightning) {
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

  static String _nativePaymentValue(String value, String field) {
    if (!_isValidPaymentValue(value)) {
      throw NativeProtocolException(
        'Native wallet returned a malformed payment request.',
        field: field,
      );
    }
    return value;
  }

  static bool _isValidPaymentValue(String value) =>
      WalletProtocolText.isEncodedValue(value);

  static String _nativeIdentifier(String value, String field) {
    if (!WalletProtocolText.isIdentifier(value)) {
      throw NativeProtocolException(
        'Native wallet returned a malformed payment identifier.',
        field: field,
      );
    }
    return value;
  }

  static String? _optionalNativeIdentifier(String? value, String field) =>
      value == null ? null : _nativeIdentifier(value, field);

  static int? _optionalNativeIndex(int? value, String field) {
    if (value != null && value < 0) {
      throw NativeProtocolException(
        'Native wallet returned an invalid transfer index.',
        field: field,
      );
    }
    return value;
  }

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
      environment = BlockchainEnvironment.parse(raw);
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

  static WalletAmount _nativeAmount(
    PaymentRoute route,
    int units,
    String field,
  ) {
    try {
      return route.rail == PaymentRail.onchain
          ? WalletAmount.onchain(assetId: route.asset.id, units: units)
          : WalletAmount.lightning(assetId: route.asset.id, units: units);
    } on ArgumentError {
      throw NativeProtocolException(
        'Native payment amount is outside supported bounds.',
        field: field,
      );
    }
  }

  static DateTime? _optionalUnixSeconds(int? value, String field) =>
      value == null ? null : _unixSeconds(value, field);

  static DateTime _unixSeconds(int value, String field) {
    if (value < 0 || value > _maximumUnixSeconds) {
      throw NativeProtocolException(
        'Native timestamp is outside supported bounds.',
        field: field,
      );
    }
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }

  static WalletPaymentStatus _paymentStatus(String? value) => switch (value) {
    null ||
    RlnPaymentStatuses.pending ||
    RlnPaymentStatuses.claimable ||
    RlnPaymentStatuses.claiming => WalletPaymentStatus.pending,
    RlnPaymentStatuses.succeeded => WalletPaymentStatus.succeeded,
    RlnPaymentStatuses.cancelled => WalletPaymentStatus.cancelled,
    RlnPaymentStatuses.failed => WalletPaymentStatus.failed,
    _ => throw const NativeProtocolException(
      'Native payment returned an unknown status.',
      field: 'LightningSendRequest.status',
    ),
  };

  static WalletActivity _bitcoinActivity(
    WalletAsset asset,
    CoreTransaction transaction,
  ) {
    final txid = _nativeIdentifier(transaction.txid, 'CoreTransaction.txid');
    _requireNonNegative(transaction.received, 'CoreTransaction.received');
    _requireNonNegative(transaction.sent, 'CoreTransaction.sent');
    _requireNonNegative(transaction.fee, 'CoreTransaction.fee');
    final confirmation = transaction.confirmationTime;
    final confirmedAt = confirmation == null
        ? null
        : _unixSeconds(
            confirmation.timestamp,
            'CoreTransaction.confirmationTime.timestamp',
          );
    if (confirmation != null && confirmation.height < 0) {
      throw const NativeProtocolException(
        'Native transaction confirmation height must not be negative.',
        field: 'CoreTransaction.confirmationTime.height',
      );
    }
    final (
      operation,
      direction,
      amountUnits,
    ) = switch (transaction.transactionType) {
      'Incoming' => (
        WalletActivityOperation.bitcoinReceive,
        WalletActivityDirection.received,
        transaction.received,
      ),
      'SendBtc' => (
        WalletActivityOperation.bitcoinSend,
        WalletActivityDirection.sent,
        _externalBitcoinAmount(transaction),
      ),
      'Drain' => (
        WalletActivityOperation.bitcoinDrain,
        WalletActivityDirection.sent,
        _externalBitcoinAmount(transaction),
      ),
      'CreateUtxos' => (
        WalletActivityOperation.bitcoinUtxoCreation,
        WalletActivityDirection.internal,
        0,
      ),
      'RgbSend' => (
        WalletActivityOperation.rgbAnchor,
        WalletActivityDirection.internal,
        0,
      ),
      _ => throw const NativeProtocolException(
        'Native wallet returned an unknown transaction type.',
        field: 'CoreTransaction.transactionType',
      ),
    };
    return WalletActivity(
      id: _activityId('bitcoin-transaction', asset, txid),
      source: WalletActivitySource.bitcoinTransaction,
      operation: operation,
      asset: asset,
      rail: PaymentRail.onchain,
      direction: direction,
      status: confirmation == null
          ? WalletActivityStatus.pending
          : WalletActivityStatus.succeeded,
      amount: amountUnits == 0
          ? null
          : WalletAmount.onchain(assetId: asset.id, units: amountUnits),
      fee: transaction.fee == 0
          ? null
          : WalletAmount.onchain(
              assetId: WalletAsset.bitcoin.id,
              units: transaction.fee,
            ),
      occurredAt: confirmedAt,
      confirmedAt: confirmedAt,
      confirmationHeight: confirmation?.height,
      txid: txid,
    );
  }

  static WalletActivity _rgbActivity(WalletAsset asset, CoreTransfer transfer) {
    if (transfer.idx < 0) {
      throw const NativeProtocolException(
        'Native RGB transfer index must not be negative.',
        field: 'CoreTransfer.idx',
      );
    }
    final (operation, direction) = switch (transfer.kind) {
      'Send' => (WalletActivityOperation.rgbSend, WalletActivityDirection.sent),
      'ReceiveBlind' || 'ReceiveWitness' => (
        WalletActivityOperation.rgbReceive,
        WalletActivityDirection.received,
      ),
      'Issuance' => (
        WalletActivityOperation.rgbIssuance,
        WalletActivityDirection.received,
      ),
      'Inflation' => (
        WalletActivityOperation.rgbInflation,
        WalletActivityDirection.received,
      ),
      'Burn' => (WalletActivityOperation.rgbBurn, WalletActivityDirection.sent),
      _ => throw const NativeProtocolException(
        'Native wallet returned an unknown RGB transfer kind.',
        field: 'CoreTransfer.kind',
      ),
    };
    final createdAt = _optionalUnixSeconds(
      transfer.createdAt,
      'CoreTransfer.createdAt',
    );
    final updatedAt = _optionalUnixSeconds(
      transfer.updatedAt,
      'CoreTransfer.updatedAt',
    );
    final endpoints = transfer.transportEndpoints;
    final transportTypes =
        endpoints
            .map((endpoint) => endpoint.transportType)
            .toSet()
            .toList(growable: false)
          ..sort();
    return WalletActivity(
      id: _activityId('rgb-transfer', asset, transfer.idx.toString()),
      source: WalletActivitySource.rgbTransfer,
      operation: operation,
      asset: asset,
      rail: PaymentRail.onchain,
      direction: direction,
      status: _transferStatus(transfer.status),
      amount: WalletAmount.onchain(
        assetId: asset.id,
        units: _transferAmount(transfer.assignments),
      ),
      occurredAt: createdAt ?? updatedAt,
      updatedAt: updatedAt,
      expiresAt: _optionalUnixSeconds(
        transfer.expiration,
        'CoreTransfer.expiration',
      ),
      txid: _optionalNativeIdentifier(transfer.txid, 'CoreTransfer.txid'),
      recipientId: _optionalNativeIdentifier(
        transfer.recipientId,
        'CoreTransfer.recipientId',
      ),
      transferIndex: transfer.idx,
      batchTransferIndex: _optionalNativeIndex(
        transfer.batchTransferIdx,
        'CoreTransfer.batchTransferIdx',
      ),
      receiveOutpoint: _outpoint(
        transfer.receiveUtxo,
        'CoreTransfer.receiveUtxo',
      ),
      changeOutpoint: _outpoint(transfer.changeUtxo, 'CoreTransfer.changeUtxo'),
      transportEndpointCount: endpoints.length,
      usedTransportEndpointCount: endpoints
          .where((endpoint) => endpoint.used)
          .length,
      transportTypes: transportTypes,
    );
  }

  static WalletActivity _lightningActivity(
    WalletAsset asset,
    LightningPayment payment,
  ) {
    final paymentHash = _nativeIdentifier(
      payment.paymentHash,
      'LightningPayment.paymentHash',
    );
    final amountUnits = asset.kind == WalletAssetKind.bitcoin
        ? payment.amtMsat
        : payment.assetAmount;
    if (asset.kind == WalletAssetKind.bitcoin && payment.assetAmount != null) {
      throw const NativeProtocolException(
        'Bitcoin Lightning payment unexpectedly contains an RGB amount.',
        field: 'LightningPayment.assetAmount',
      );
    }
    if (amountUnits != null && amountUnits <= 0) {
      throw const NativeProtocolException(
        'Native Lightning payment amount must be positive.',
        field: 'LightningPayment.amount',
      );
    }
    final createdAt = _optionalUnixSeconds(
      payment.createdAt,
      'LightningPayment.createdAt',
    );
    final updatedAt = _optionalUnixSeconds(
      payment.updatedAt,
      'LightningPayment.updatedAt',
    );
    return WalletActivity(
      id: _activityId('lightning-payment', asset, paymentHash),
      source: WalletActivitySource.lightningPayment,
      operation: WalletActivityOperation.lightningPayment,
      asset: asset,
      rail: PaymentRail.lightning,
      direction: switch (payment.inbound) {
        true => WalletActivityDirection.received,
        false => WalletActivityDirection.sent,
        null => WalletActivityDirection.unknown,
      },
      status: _lightningStatus(payment.status),
      amount: amountUnits == null
          ? null
          : WalletAmount.lightning(assetId: asset.id, units: amountUnits),
      occurredAt: createdAt ?? updatedAt,
      updatedAt: updatedAt,
      paymentHash: paymentHash,
      invoice: payment.invoice,
      payeePublicKey: _optionalNativeIdentifier(
        payment.payeePubkey,
        'LightningPayment.payeePubkey',
      ),
    );
  }

  static bool _paymentBelongsToAsset(
    LightningPayment payment,
    WalletAsset asset,
  ) {
    final nativeAssetId = payment.assetId;
    if (asset.kind == WalletAssetKind.bitcoin) return nativeAssetId == null;
    return nativeAssetId == asset.id.value;
  }

  static List<WalletActivity> _normalizeActivities(
    Iterable<WalletActivity> activities,
  ) {
    final byId = <String, WalletActivity>{};
    for (final activity in activities) {
      final existing = byId[activity.id];
      if (existing == null) {
        byId[activity.id] = activity;
      } else if (existing != activity) {
        throw const NativeProtocolException(
          'Native wallet returned conflicting duplicate activity.',
          field: 'WalletActivity.id',
        );
      }
    }
    final normalized = byId.values.toList(growable: false)
      ..sort(WalletActivityFeed.compareByRecency);
    return List<WalletActivity>.unmodifiable(normalized);
  }

  static int _externalBitcoinAmount(CoreTransaction transaction) {
    final value =
        BigInt.from(transaction.sent) -
        BigInt.from(transaction.received) -
        BigInt.from(transaction.fee);
    if (value.isNegative || value > BigInt.from(WalletAmount.maxNativeUnits)) {
      throw const NativeProtocolException(
        'Native Bitcoin transaction amounts are inconsistent.',
        field: 'CoreTransaction.sent',
      );
    }
    return value.toInt();
  }

  static int _transferAmount(List<Assignment> assignments) {
    var total = BigInt.zero;
    var foundAmount = false;
    for (final assignment in assignments) {
      final amount = assignment.amount;
      if (amount == null) continue;
      foundAmount = true;
      if (amount < 0) {
        throw const NativeProtocolException(
          'Native RGB assignment amount must not be negative.',
          field: 'CoreTransfer.assignments.amount',
        );
      }
      total += BigInt.from(amount);
      if (total > BigInt.from(WalletAmount.maxNativeUnits)) {
        throw const NativeProtocolException(
          'Native RGB transfer amount exceeds supported bounds.',
          field: 'CoreTransfer.assignments.amount',
        );
      }
    }
    if (!foundAmount || total == BigInt.zero) {
      throw const NativeProtocolException(
        'Native fungible RGB transfer has no positive amount.',
        field: 'CoreTransfer.assignments.amount',
      );
    }
    return total.toInt();
  }

  static WalletActivityStatus _transferStatus(String status) =>
      switch (status) {
        'Initiated' => WalletActivityStatus.pending,
        'WaitingCounterparty' => WalletActivityStatus.waitingCounterparty,
        'WaitingSafeHeight' => WalletActivityStatus.waitingSafeHeight,
        'WaitingConfirmations' => WalletActivityStatus.waitingConfirmations,
        'Settled' => WalletActivityStatus.succeeded,
        'Failed' => WalletActivityStatus.failed,
        _ => throw const NativeProtocolException(
          'Native wallet returned an unknown RGB transfer status.',
          field: 'CoreTransfer.status',
        ),
      };

  static WalletActivityStatus _lightningStatus(String status) =>
      switch (status) {
        RlnPaymentStatuses.pending => WalletActivityStatus.pending,
        RlnPaymentStatuses.claimable => WalletActivityStatus.claimable,
        RlnPaymentStatuses.claiming => WalletActivityStatus.claiming,
        RlnPaymentStatuses.succeeded => WalletActivityStatus.succeeded,
        RlnPaymentStatuses.cancelled => WalletActivityStatus.cancelled,
        RlnPaymentStatuses.failed => WalletActivityStatus.failed,
        RlnInvoiceStatuses.expired => WalletActivityStatus.expired,
        _ => throw const NativeProtocolException(
          'Native wallet returned an unknown Lightning payment status.',
          field: 'LightningPayment.status',
        ),
      };

  static String? _outpoint(Outpoint? outpoint, String field) {
    if (outpoint == null) return null;
    final txid = _nativeIdentifier(outpoint.txid, '$field.txid');
    if (outpoint.vout < 0) {
      throw NativeProtocolException(
        'Native RGB outpoint index must not be negative.',
        field: '$field.vout',
      );
    }
    return '$txid:${outpoint.vout}';
  }

  static String _activityId(String source, WalletAsset asset, String nativeId) {
    final digest = sha256.convert(
      utf8.encode('v1|$source|${asset.id.value}|$nativeId'),
    );
    return 'activity-$digest';
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
      nativeEnvironment = BlockchainEnvironment.parse(network.network);
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

  static WalletBalance _bitcoinBalance(
    WalletAsset asset,
    CoreBtcBalance balance,
    WalletNodeInfo node,
    List<LightningChannel> channels,
  ) {
    _validateCoreBalance(balance.vanilla, 'bitcoin.vanilla');
    _validateCoreBalance(balance.colored, 'bitcoin.colored');
    _requireNonNegative(node.localBalanceSat, 'node.localBalanceSat');
    final outboundMsat = _sum(
      channels
          .where((channel) => channel.ready && channel.isUsable == true)
          .map(
            (channel) => _requirePresent(
              channel.outboundBalanceMsat,
              'channel.outboundBalanceMsat',
            ),
          ),
      'channel.outboundBalanceMsat',
    );
    final inboundMsat = _sum(
      channels
          .where((channel) => channel.ready && channel.isUsable == true)
          .map(
            (channel) => _requirePresent(
              channel.inboundBalanceMsat,
              'channel.inboundBalanceMsat',
            ),
          ),
      'channel.inboundBalanceMsat',
    );
    return WalletBalance(
      asset: asset,
      onchainSettled: WalletAmount.onchain(
        assetId: asset.id,
        units: _checkedAdd(
          balance.vanilla.settled,
          balance.colored.settled,
          'bitcoin.settled',
        ),
      ),
      onchainFuture: WalletAmount.onchain(
        assetId: asset.id,
        units: _checkedAdd(
          balance.vanilla.future,
          balance.colored.future,
          'bitcoin.future',
        ),
      ),
      onchainSpendable: WalletAmount.onchain(
        assetId: asset.id,
        units: balance.vanilla.spendable,
      ),
      onchainLocked: WalletAmount.onchain(
        assetId: asset.id,
        units: _checkedSubtract(
          _checkedAdd(
            balance.vanilla.settled,
            balance.colored.settled,
            'bitcoin.settled',
          ),
          balance.vanilla.spendable,
          'bitcoin.locked',
        ),
      ),
      lightningOwned: WalletAmount.lightning(
        assetId: asset.id,
        units: _checkedMultiply(
          node.localBalanceSat,
          1000,
          'node.localBalanceSat',
        ),
      ),
      lightningSpendable: WalletAmount.lightning(
        assetId: asset.id,
        units: outboundMsat,
      ),
      lightningReceivable: WalletAmount.lightning(
        assetId: asset.id,
        units: inboundMsat,
      ),
    );
  }

  static WalletBalance _rgbBalance(
    WalletAsset asset,
    CoreAssetBalance balance,
    List<LightningChannel> channels,
  ) {
    _validateCoreBalance(balance, 'rgb');
    _requireNonNegative(balance.offchainOutbound, 'rgb.offchainOutbound');
    _requireNonNegative(balance.offchainInbound, 'rgb.offchainInbound');
    final assetChannels = channels.where(
      (channel) => channel.assetId == asset.id.value,
    );
    final local = _sum(
      assetChannels.map(
        (channel) => _requirePresent(
          channel.assetLocalAmount,
          'channel.assetLocalAmount',
        ),
      ),
      'channel.assetLocalAmount',
    );
    return WalletBalance(
      asset: asset,
      onchainSettled: WalletAmount.onchain(
        assetId: asset.id,
        units: balance.settled,
      ),
      onchainFuture: WalletAmount.onchain(
        assetId: asset.id,
        units: balance.future,
      ),
      onchainSpendable: WalletAmount.onchain(
        assetId: asset.id,
        units: balance.spendable,
      ),
      onchainLocked: WalletAmount.onchain(
        assetId: asset.id,
        units: _checkedSubtract(
          balance.settled,
          balance.spendable,
          'rgb.locked',
        ),
      ),
      lightningOwned: WalletAmount.lightning(assetId: asset.id, units: local),
      lightningSpendable: WalletAmount.lightning(
        assetId: asset.id,
        units: balance.offchainOutbound,
      ),
      lightningReceivable: WalletAmount.lightning(
        assetId: asset.id,
        units: balance.offchainInbound,
      ),
    );
  }

  static void _validateCoreBalance(CoreBalance balance, String field) {
    _requireNonNegative(balance.settled, '$field.settled');
    _requireNonNegative(balance.future, '$field.future');
    _requireNonNegative(balance.spendable, '$field.spendable');
    if (balance.spendable > balance.settled) {
      throw NativeProtocolException(
        'Spendable balance exceeds settled balance.',
        field: '$field.spendable',
      );
    }
  }

  static int _sum(Iterable<int> values, String field) {
    var total = BigInt.zero;
    for (final value in values) {
      _requireNonNegative(value, field);
      total += BigInt.from(value);
      if (total > BigInt.from(WalletAmount.maxNativeUnits)) {
        throw NativeProtocolException(
          'Native monetary aggregate exceeds supported bounds.',
          field: field,
        );
      }
    }
    return total.toInt();
  }

  static int _checkedAdd(int left, int right, String field) {
    final value = BigInt.from(left) + BigInt.from(right);
    return _checkedNativeValue(value, field);
  }

  static int _checkedSubtract(int left, int right, String field) {
    final value = BigInt.from(left) - BigInt.from(right);
    return _checkedNativeValue(value, field);
  }

  static int _checkedMultiply(int left, int right, String field) {
    final value = BigInt.from(left) * BigInt.from(right);
    return _checkedNativeValue(value, field);
  }

  static int _checkedNativeValue(BigInt value, String field) {
    if (value.isNegative || value > BigInt.from(WalletAmount.maxNativeUnits)) {
      throw NativeProtocolException(
        'Native monetary value exceeds supported bounds.',
        field: field,
      );
    }
    return value.toInt();
  }

  static int _requirePresent(int? value, String field) {
    if (value == null) {
      throw NativeProtocolException(
        'Native monetary value is missing.',
        field: field,
      );
    }
    return value;
  }

  static void _requireNonNegative(int value, String field) {
    if (value < 0) {
      throw NativeProtocolException(
        'Native monetary value must not be negative.',
        field: field,
      );
    }
  }
}
