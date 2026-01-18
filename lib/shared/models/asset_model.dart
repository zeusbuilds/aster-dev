import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/material.dart';

part 'asset_model.freezed.dart';
part 'asset_model.g.dart';

/// Asset model representing a cryptocurrency token
@freezed
class AssetModel with _$AssetModel {
  const factory AssetModel({
    required String token,
    required String chain,
    required String icon,
    required int color,
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
    color: 0xFFFF9500, // Orange color for Bitcoin
    unit: 'sats',
  );

  /// Liquid Bitcoin (LBTC) asset
  static const liquidBitcoin = AssetModel(
    token: 'LBTC',
    chain: 'Liquid',
    icon: 'assets/icons/tokens/lbtc.svg',
    color: 0xFF00D4AA, // Teal color for Liquid
    unit: 'lsats',
  );

  /// Tether USD (USDt) asset on Liquid
  static const usdt = AssetModel(
    token: 'USDT',
    chain: 'Tether',
    icon: 'assets/icons/tokens/usdt.svg',
    color: 0xFF26A17B, // Green color for Tether
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
  /// Get color as Color object
  Color get color => Color(this.color);

  /// Get icon as string
  String get icon => this.icon;

  /// Get token name as string
  String get token => this.token;

  /// Get chain name as string
  String get chain => this.chain;

  /// Get unit as string
  String get unit => this.unit;
}
