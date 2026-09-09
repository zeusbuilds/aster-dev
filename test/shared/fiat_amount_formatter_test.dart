import 'package:aster/shared/formatting/fiat_amount_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('headline rounding does not change exact balance formatting', () {
    final formatter = FiatAmountFormatter(locale: 'en_US');
    String format(int value, {bool headline = false}) => formatter.format(
      minorUnits: value,
      symbol: r'$',
      code: 'USD',
      minorUnitDigits: 2,
      includeCurrencyCode: !headline,
      wholeUnitsOnly: headline,
    );
    expect(format(7891849, headline: true), r'$78,918');
    expect(format(7891850, headline: true), r'$78,919');
    expect(format(7891850), r'$78,918.50 USD');
    expect(format(0, headline: true), r'$0');
    expect(format(9007199254740993), r'$90,071,992,547,409.93 USD');
  });
}
