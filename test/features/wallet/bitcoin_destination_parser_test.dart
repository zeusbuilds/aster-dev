import 'dart:typed_data';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/validation/validation.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:dart_bech32/dart_bech32.dart' as bech32_codec;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = BitcoinDestinationParser();

  test('accepts official BIP173 and BIP350 witness vectors', () {
    const mainnetVectors = <String>[
      'BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4',
      'bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y',
      'BC1SW50QGDZ25J',
      'bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs',
      'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0',
    ];
    const testnetVectors = <String>[
      'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7',
      'tb1qqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesrxh6hy',
      'tb1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesf3hn0c',
    ];

    for (final address in mainnetVectors) {
      final destination = _success(
        parser.decode(address, BlockchainEnvironment.mainnet),
      );
      expect(destination.address, address.toLowerCase());
      expect(destination.wasUri, isFalse);
    }
    for (final address in testnetVectors) {
      expect(
        parser.decode(address, BlockchainEnvironment.signet),
        isA<AppSuccess<BitcoinDestination>>(),
      );
    }
  });

  test('rejects the official BIP350 invalid witness vectors', () {
    const vectors = <String>[
      'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd',
      'tb1z0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqglt7rf',
      'BC1S0XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ54WELL',
      'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh',
      'bc1p38j9r5y49hruaue7wxjce0updqjuyyx0kh56v8s25huc6995vvpql3jow4',
      'BC130XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ7ZWS8R',
      'bc1pw5dgrnzv',
      'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v8n0nx0muaewav253zgeav',
      'BC1QR508D6QEJXTDG4Y5R3ZARVARYV98GJ9P',
      'tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq47Zagq',
      'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v07qwwzcrf',
      'tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vpggkg4j',
      'bc1gmk9yu',
    ];

    for (final address in vectors) {
      final result = parser.decode(address, BlockchainEnvironment.mainnet);
      expect(result, isA<AppFailureResult<BitcoinDestination>>());
    }
  });

  test('supports regtest HRP and enforces every configured network', () {
    final regtestAddress = _regtestAddress();

    expect(
      parser.normalizeAddress(regtestAddress, BlockchainEnvironment.regtest),
      regtestAddress,
    );
    expect(
      parser.normalizeAddress(
        'bitcoin:$regtestAddress',
        BlockchainEnvironment.regtest,
      ),
      isNull,
    );
    expect(
      parser.decode(regtestAddress, BlockchainEnvironment.regtest),
      isA<AppSuccess<BitcoinDestination>>(),
    );
    expect(
      _failureCode(parser.decode(regtestAddress, BlockchainEnvironment.signet)),
      'bitcoin_destination_network_mismatch',
    );
    expect(
      _failureCode(
        parser.decode(
          'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
          BlockchainEnvironment.regtest,
        ),
      ),
      'bitcoin_destination_network_mismatch',
    );
  });

  test('validates legacy P2PKH and P2SH checksums and versions', () {
    const mainnet = <String>[
      '1BoatSLRHtKNngkdXEeobR76b53LETtpyT',
      '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy',
    ];
    const testnet = <String>[
      'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
      '2N2JD6wb56AfK4tfmM6PwdVmoYk2dCKf4Br',
    ];

    for (final address in mainnet) {
      expect(
        parser.decode(address, BlockchainEnvironment.mainnet),
        isA<AppSuccess<BitcoinDestination>>(),
      );
      expect(
        _failureCode(parser.decode(address, BlockchainEnvironment.regtest)),
        'bitcoin_destination_network_mismatch',
      );
    }
    for (final address in testnet) {
      expect(
        parser.decode(address, BlockchainEnvironment.signet),
        isA<AppSuccess<BitcoinDestination>>(),
      );
      expect(
        parser.decode(address, BlockchainEnvironment.regtest),
        isA<AppSuccess<BitcoinDestination>>(),
      );
    }
    expect(
      _failureCode(
        parser.decode(
          '1BoatSLRHtKNngkdXEeobR76b53LETtpyU',
          BlockchainEnvironment.mainnet,
        ),
      ),
      'bitcoin_destination_invalid',
    );
  });

  test('parses BIP321 metadata and amount with exact integer arithmetic', () {
    const address = '1BoatSLRHtKNngkdXEeobR76b53LETtpyT';
    final destination = _success(
      parser.decode(
        'BITCOIN:$address?AMOUNT=20.3&LABEL=Luke-Jr&'
        'MESSAGE=Donation%20for%20UTEXO&lightning=lnbc1ignored',
        BlockchainEnvironment.mainnet,
      ),
    );

    expect(destination.address, address);
    expect(destination.amount?.units, 2030000000);
    expect(destination.amount?.unit, WalletAmountUnit.satoshi);
    expect(destination.recipientLabel, 'Luke-Jr');
    expect(destination.message, 'Donation for UTEXO');
    expect(destination.wasUri, isTrue);
    expect(destination.toString(), isNot(contains(address)));

    final blankMetadata = _success(
      parser.decode(
        'bitcoin:$address?label=&message=',
        BlockchainEnvironment.mainnet,
      ),
    );
    expect(blankMetadata.recipientLabel, isNull);
    expect(blankMetadata.message, isNull);
  });

  test('accepts unknown optional instructions with an onchain fallback', () {
    final result = parser.decode(
      'bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT?future=a&future=b',
      BlockchainEnvironment.mainnet,
    );

    expect(result, isA<AppSuccess<BitcoinDestination>>());
  });

  test('rejects duplicate and unsupported required instructions', () {
    const address = '1BoatSLRHtKNngkdXEeobR76b53LETtpyT';

    expect(
      _failureCode(
        parser.decode(
          'bitcoin:$address?amount=1&AMOUNT=1',
          BlockchainEnvironment.mainnet,
        ),
      ),
      'bitcoin_destination_invalid',
    );
    expect(
      _failureCode(
        parser.decode(
          'bitcoin:$address?req-pop=callback%3A',
          BlockchainEnvironment.mainnet,
        ),
      ),
      'bitcoin_destination_instruction_unsupported',
    );
    expect(
      _failureCode(
        parser.decode(
          'bitcoin:?lightning=lnbc1invoice',
          BlockchainEnvironment.mainnet,
        ),
      ),
      'bitcoin_destination_onchain_missing',
    );
  });

  test('rejects malformed or out-of-range URI amounts', () {
    const address = '1BoatSLRHtKNngkdXEeobR76b53LETtpyT';
    const amounts = <String>[
      '',
      '-1',
      '+1',
      '1e-8',
      '1.',
      '1,000',
      '0.000000001',
      '21000000.00000001',
    ];

    for (final amount in amounts) {
      expect(
        _failureCode(
          parser.decode(
            'bitcoin:$address?amount=$amount',
            BlockchainEnvironment.mainnet,
          ),
        ),
        'bitcoin_destination_amount_invalid',
      );
    }
    final zero = _success(
      parser.decode(
        'bitcoin:$address?amount=0.00000000',
        BlockchainEnvironment.mainnet,
      ),
    );
    expect(zero.amount, isNull);
  });

  test('rejects unsafe display metadata and malformed URI structure', () {
    const address = '1BoatSLRHtKNngkdXEeobR76b53LETtpyT';
    const values = <String>[
      'bitcoin://1BoatSLRHtKNngkdXEeobR76b53LETtpyT',
      'bitcoin:%31BoatSLRHtKNngkdXEeobR76b53LETtpyT',
      'bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT#fragment',
      'bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT?label=Main%0AWallet',
      'bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT?label=Main%E2%80%AEWallet',
      'bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT?label=Main%E2%80%8BWallet',
      'bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT?label=Main%E2%81%A0Wallet',
      'bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT?label=Main%EF%BB%BFWallet',
      'bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT?label=a&&message=b',
    ];

    for (final value in values) {
      expect(
        parser.decode(value, BlockchainEnvironment.mainnet),
        isA<AppFailureResult<BitcoinDestination>>(),
      );
    }
    expect(
      parser.decode(
        'bitcoin:$address?label=${List<String>.filled(257, 'a').join()}',
        BlockchainEnvironment.mainnet,
      ),
      isA<AppFailureResult<BitcoinDestination>>(),
    );
  });
}

BitcoinDestination _success(AppResult<BitcoinDestination> result) {
  expect(result, isA<AppSuccess<BitcoinDestination>>());
  return (result as AppSuccess<BitcoinDestination>).value;
}

String _failureCode(AppResult<BitcoinDestination> result) {
  expect(result, isA<AppFailureResult<BitcoinDestination>>());
  return (result as AppFailureResult<BitcoinDestination>).failure.code;
}

String _regtestAddress() {
  final program = Uint8List.fromList(List<int>.generate(20, (index) => index));
  final words = Uint8List.fromList(<int>[
    0,
    ...bech32_codec.bech32.toWords(program),
  ]);
  return bech32_codec.bech32.encode(
    bech32_codec.Decoded(prefix: 'bcrt', words: words),
  );
}
