/// Immutable fiat metadata shared by settings, market, and amount formatting.
abstract final class FiatCurrencyPolicy {
  /// Whether [code] is in the reviewed app/provider fiat intersection.
  ///
  /// This is the intersection of the bundled catalog and CoinGecko's official
  /// `/simple/supported_vs_currencies` response, verified on 2026-08-13.
  /// Runtime payload validation still fails closed if provider support changes.
  static bool supportsMarketQuote(String code) => _marketCodes.contains(code);

  /// ISO 4217 minor-unit precision for exact integer fiat values.
  static int minorUnitDigits(String code) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) {
      throw ArgumentError.value(code, 'code', 'Must be an ISO 4217 code.');
    }
    return switch (code) {
      'BIF' ||
      'CLP' ||
      'DJF' ||
      'GNF' ||
      'JPY' ||
      'KMF' ||
      'KRW' ||
      'PYG' ||
      'RWF' ||
      'UGX' ||
      'VND' ||
      'VUV' ||
      'XAF' ||
      'XOF' ||
      'XPF' => 0,
      'BHD' || 'IQD' || 'JOD' || 'KWD' || 'LYD' || 'OMR' || 'TND' => 3,
      _ => 2,
    };
  }

  static const _marketCodes = <String>{
    'AED',
    'ARS',
    'AUD',
    'BDT',
    'BMD',
    'BRL',
    'CAD',
    'CHF',
    'CLP',
    'CNY',
    'CZK',
    'DKK',
    'EUR',
    'GBP',
    'GEL',
    'HKD',
    'HUF',
    'IDR',
    'ILS',
    'INR',
    'JPY',
    'KRW',
    'KWD',
    'LKR',
    'MMK',
    'MXN',
    'MYR',
    'NGN',
    'NOK',
    'NZD',
    'PHP',
    'PKR',
    'PLN',
    'RUB',
    'SAR',
    'SEK',
    'SGD',
    'THB',
    'TRY',
    'UAH',
    'USD',
    'VND',
    'ZAR',
  };
}
