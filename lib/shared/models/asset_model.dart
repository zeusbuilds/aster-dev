/// Asset model representing a cryptocurrency token
class AssetModel {
  const AssetModel({
    required this._token,
    required this._chain,
    required this._icon,
    required this._unit,
  });

  factory AssetModel.fromJson(Map<String, Object?> json) {
    return AssetModel(
      token: json['token']! as String,
      chain: json['chain']! as String,
      icon: json['icon']! as String,
      unit: json['unit']! as String,
    );
  }

  final String _token;
  final String _chain;
  final String _icon;
  final String _unit;

  String get token => _token;
  String get chain => _chain;
  String get icon => _icon;
  String get unit => _unit;

  // Predefined asset instances
  /// Bitcoin (BTC) asset
  static const bitcoin = AssetModel(
    token: 'BTC',
    chain: 'Bitcoin',
    icon: 'assets/icons/tokens/btc.svg',
    unit: 'sats',
  );

  /// Tether USD issued as an RGB asset.
  static const usdt = AssetModel(
    token: 'USDT',
    chain: 'RGB',
    icon: 'assets/icons/tokens/usdt.svg',
    unit: 'USDt',
  );

  /// Get all predefined assets
  static List<AssetModel> get all => const [bitcoin, usdt];

  Map<String, Object?> toJson() => {
    'token': token,
    'chain': chain,
    'icon': icon,
    'unit': unit,
  };

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

  @override
  bool operator ==(Object other) {
    return other is AssetModel &&
        other.token == token &&
        other.chain == chain &&
        other.icon == icon &&
        other.unit == unit;
  }

  @override
  int get hashCode => Object.hash(token, chain, icon, unit);
}
