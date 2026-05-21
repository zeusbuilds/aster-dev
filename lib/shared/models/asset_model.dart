import 'package:flutter/material.dart';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../theme/theme.dart';

part 'asset_model.freezed.dart';
part 'asset_model.g.dart';

/// Asset model representing a cryptocurrency token
@freezed
class AssetModel with _$AssetModel {
  const factory AssetModel({
    required String token,
    required String chain,
    required String icon,
    required String unit,
  }) = _AssetModel;

  factory AssetModel.fromJson(Map<String, dynamic> json) =>
      _$AssetModelFromJson(json);

  // Predefined asset instances
  /// Bitcoin (BTC) asset
  static const bitcoin = AssetModel(
    token: 'BTC',
    chain: 'Bitcoin',
    icon: 'assets/icons/tokens/btc.svg',
    unit: 'sats',
  );

  /// Liquid Bitcoin (LBTC) asset
  static const liquidBitcoin = AssetModel(
    token: 'LBTC',
    chain: 'Liquid',
    icon: 'assets/icons/tokens/lbtc.svg',
    unit: 'lsats',
  );

  /// Tether USD (USDt) asset on Liquid
  static const usdt = AssetModel(
    token: 'USDT',
    chain: 'Tether',
    icon: 'assets/icons/tokens/usdt.svg',
    unit: 'USDt',
  );

  /// Get all predefined assets
  static List<AssetModel> get all => [bitcoin, liquidBitcoin, usdt];

  /// Find asset by token name (case-insensitive)
  static AssetModel? findByName(String name) {
    try {
      return all.firstWhere(
        (asset) => asset.token.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Find asset by unit (case-insensitive)
  static AssetModel? findByUnit(String unit) {
    try {
      return all.firstWhere(
        (asset) => asset.unit.toLowerCase() == unit.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Extension to add convenience methods to AssetModel
extension AssetModelExtension on AssetModel {
  Color themedColor(BuildContext context) {
    final colors = context.appColors;
    return switch (token.toUpperCase()) {
      'BTC' => colors.bitcoin,
      'LBTC' => colors.liquid,
      'USDT' => colors.success,
      _ => context.colorScheme.primary,
    };
  }
}
