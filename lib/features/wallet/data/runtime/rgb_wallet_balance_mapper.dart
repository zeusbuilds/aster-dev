import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../domain/models/models.dart';
import 'rgb_wallet_native_value_parser.dart';

/// Maps native on-chain and channel balances into exact app-owned amounts.
///
/// The mapper is kept behind [RgbWalletEngine] so SDK DTOs cannot cross the
/// repository boundary.
final class RgbWalletBalanceMapper {
  const RgbWalletBalanceMapper([
    this._values = const RgbWalletNativeValueParser(),
  ]);

  final RgbWalletNativeValueParser _values;

  WalletBalance bitcoin(
    WalletAsset asset,
    CoreBtcBalance balance,
    WalletNodeInfo node,
    List<LightningChannel> channels,
  ) {
    _validateCoreBalance(balance.vanilla, 'bitcoin.vanilla');
    _validateCoreBalance(balance.colored, 'bitcoin.colored');
    _values.requireNonNegative(node.localBalanceSat, 'node.localBalanceSat');
    final outboundMsat = _values.sum(
      channels
          .where((channel) => channel.ready && channel.isUsable == true)
          .map(
            (channel) => _values.requirePresent(
              channel.outboundBalanceMsat,
              'channel.outboundBalanceMsat',
            ),
          ),
      'channel.outboundBalanceMsat',
    );
    final inboundMsat = _values.sum(
      channels
          .where((channel) => channel.ready && channel.isUsable == true)
          .map(
            (channel) => _values.requirePresent(
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
        units: _values.checkedAdd(
          balance.vanilla.settled,
          balance.colored.settled,
          'bitcoin.settled',
        ),
      ),
      onchainFuture: WalletAmount.onchain(
        assetId: asset.id,
        units: _values.checkedAdd(
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
        units: _values.checkedSubtract(
          _values.checkedAdd(
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
        units: _values.checkedMultiply(
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

  WalletBalance rgb(
    WalletAsset asset,
    CoreAssetBalance balance,
    List<LightningChannel> channels,
  ) {
    final settled = _values.exactUnits(balance.settled, 'rgb.settled');
    final future = _values.exactUnits(balance.future, 'rgb.future');
    final spendable = _values.exactUnits(balance.spendable, 'rgb.spendable');
    _validateCoreBalance(
      CoreBalance(settled: settled, future: future, spendable: spendable),
      'rgb',
    );
    final outbound = _values.exactUnits(
      balance.offchainOutbound,
      'rgb.offchainOutbound',
    );
    final inbound = _values.exactUnits(
      balance.offchainInbound,
      'rgb.offchainInbound',
    );
    final assetChannels = channels.where(
      (channel) => channel.assetId == asset.id.value,
    );
    final local = _values.sum(
      assetChannels.map(
        (channel) => _values.requireExactUnits(
          channel.assetLocalAmount,
          'channel.assetLocalAmount',
        ),
      ),
      'channel.assetLocalAmount',
    );
    return WalletBalance(
      asset: asset,
      onchainSettled: WalletAmount.onchain(assetId: asset.id, units: settled),
      onchainFuture: WalletAmount.onchain(assetId: asset.id, units: future),
      onchainSpendable: WalletAmount.onchain(
        assetId: asset.id,
        units: spendable,
      ),
      onchainLocked: WalletAmount.onchain(
        assetId: asset.id,
        units: _values.checkedSubtract(settled, spendable, 'rgb.locked'),
      ),
      lightningOwned: WalletAmount.lightning(assetId: asset.id, units: local),
      lightningSpendable: WalletAmount.lightning(
        assetId: asset.id,
        units: outbound,
      ),
      lightningReceivable: WalletAmount.lightning(
        assetId: asset.id,
        units: inbound,
      ),
    );
  }

  void _validateCoreBalance(CoreBalance balance, String field) {
    _values.requireNonNegative(balance.settled, '$field.settled');
    _values.requireNonNegative(balance.future, '$field.future');
    _values.requireNonNegative(balance.spendable, '$field.spendable');
    if (balance.spendable > balance.settled) {
      throw NativeProtocolException(
        'Spendable balance exceeds settled balance.',
        field: '$field.spendable',
      );
    }
  }
}
