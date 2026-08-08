import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/app_failure.dart';
import '../../domain/models/models.dart';
import 'wallet_engine.dart';

/// Stable-public-API adapter for `rgb_sdk_flutter`.
final class RgbWalletEngineFactory implements WalletEngineFactory {
  const RgbWalletEngineFactory([this._sdk = const RgbSdkFlutter()]);

  final RgbSdkFlutter _sdk;

  @override
  WalletEngine create(WalletEngineConfiguration configuration) {
    final services = configuration.services..validate();
    final wallet = _sdk.wallet(
      config: UtexoWalletConfig(
        storageDirPath: configuration.storageDirectory,
        network: services.sdkNetwork,
        vssUrl: services.vssUrl,
        vssAllowHttp: services.allowsInsecureLocalVss,
        lspBaseUrl: services.lspBaseUrl,
      ),
    );
    return RgbWalletEngine(wallet, services, _unlockConfiguration(services));
  }

  static UtexoUnlockConfig _unlockConfiguration(
    WalletServiceConfiguration services,
  ) {
    final defaults = getNetworkDefaults(services.sdkNetwork);
    return UtexoUnlockConfig(
      indexerUrl: services.indexerUrl ?? defaults?.indexerUrl,
      proxyEndpoint: services.rgbTransportProxy ?? defaults?.proxyEndpoint,
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
  RgbWalletEngine(this._wallet, this._services, this._unlockConfig);

  final UtexoWallet _wallet;
  final WalletServiceConfiguration _services;
  final UtexoUnlockConfig _unlockConfig;

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
  Future<String> getBitcoinAddress() async {
    final address = await _wallet.getAddress();
    if (!_isBitcoinAddressForEnvironment(address, _services.environment)) {
      throw const NativeProtocolException(
        'Native wallet returned an invalid Bitcoin address.',
        field: 'address',
      );
    }
    return address;
  }

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

  static bool _isBitcoinAddressForEnvironment(
    String address,
    BlockchainEnvironment environment,
  ) {
    if (address.isEmpty ||
        address.length > 128 ||
        address != address.trim() ||
        address.contains(RegExp(r'\s'))) {
      return false;
    }
    final normalized = address.toLowerCase();
    return switch (environment) {
      BlockchainEnvironment.mainnet =>
        normalized.startsWith('bc1') ||
            normalized.startsWith('1') ||
            normalized.startsWith('3'),
      BlockchainEnvironment.signet =>
        normalized.startsWith('tb1') ||
            normalized.startsWith('m') ||
            normalized.startsWith('n') ||
            normalized.startsWith('2'),
      BlockchainEnvironment.regtest =>
        normalized.startsWith('bcrt1') ||
            normalized.startsWith('m') ||
            normalized.startsWith('n') ||
            normalized.startsWith('2'),
    };
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
