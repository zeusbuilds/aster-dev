/// User-selected display unit for Bitcoin-denominated amounts.
enum BitcoinUnit {
  bitcoin(storageValue: 'btc', label: 'BTC', displayName: 'Bitcoin'),
  sats(storageValue: 'sats', label: 'sats', displayName: 'Satoshis');

  const BitcoinUnit({
    required this.storageValue,
    required this.label,
    required this.displayName,
  });

  /// Stable value persisted in app preferences.
  final String storageValue;

  /// Short unit label rendered beside an amount.
  final String label;

  /// Human-readable option name used by settings UI.
  final String displayName;

  /// Parses a persisted value, rejecting unknown future values.
  static BitcoinUnit parse(String value) => switch (value) {
    'btc' => BitcoinUnit.bitcoin,
    'sats' => BitcoinUnit.sats,
    _ => throw const FormatException('Unknown Bitcoin display unit.'),
  };
}
