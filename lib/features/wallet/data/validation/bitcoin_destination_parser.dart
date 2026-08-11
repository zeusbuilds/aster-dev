import 'package:bs58check/bs58check.dart' as base58check;
import 'package:dart_bech32/dart_bech32.dart' as bech32_codec;
import 'package:flutter/foundation.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';

/// Validates and canonicalizes a plain Bitcoin address for one environment.
///
/// Returns `null` when [value] is malformed, has an invalid checksum, or belongs
/// to another network. Payment URIs are deliberately outside this narrow
/// contract and must be passed to [BitcoinDestinationDecoder.decode].
abstract interface class BitcoinAddressValidator {
  String? normalizeAddress(String value, BlockchainEnvironment environment);
}

/// Decodes Bitcoin addresses and modern `bitcoin:` payment instructions.
abstract interface class BitcoinDestinationDecoder
    implements BitcoinAddressValidator {
  AppResult<BitcoinDestination> decode(
    String value,
    BlockchainEnvironment environment,
  );
}

/// Checksum-validating BIP173, BIP350, and BIP321 destination parser.
///
/// The parser accepts the on-chain fallback address from BIP321. Optional
/// payment instructions are ignored only when a valid fallback exists, while
/// every unsupported `req-*` instruction fails closed.
final class BitcoinDestinationParser implements BitcoinDestinationDecoder {
  const BitcoinDestinationParser();

  static const _maximumInputLength = 8192;
  static const _maximumBitcoinSatoshis = 2100000000000000;
  static const _satoshisPerBitcoin = 100000000;

  @override
  String? normalizeAddress(String value, BlockchainEnvironment environment) {
    try {
      return _validateAddress(value, environment);
    } on _DestinationRejection {
      return null;
    }
  }

  @override
  AppResult<BitcoinDestination> decode(
    String value,
    BlockchainEnvironment environment,
  ) {
    if (value.isEmpty ||
        value != value.trim() ||
        value.length > _maximumInputLength ||
        value.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
      return AppResult.failure(_invalidDestination());
    }

    try {
      final input = _parseInput(value);
      final address = _validateAddress(input.address, environment);
      final amount = _parseAmount(input.amount);
      return AppResult.success(
        BitcoinDestination._(
          address: address,
          wasUri: input.wasUri,
          amount: amount,
          recipientLabel: input.label,
          message: input.message,
        ),
      );
    } on _DestinationRejection catch (rejection) {
      return AppResult.failure(rejection.failure);
    }
  }

  static _DestinationInput _parseInput(String value) {
    if (!value.toLowerCase().startsWith('bitcoin:')) {
      return _DestinationInput(address: value, wasUri: false);
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'bitcoin' ||
        uri.hasAuthority ||
        uri.fragment.isNotEmpty) {
      throw _DestinationRejection(_invalidDestination());
    }
    final colon = value.indexOf(':');
    final queryStart = value.indexOf('?', colon + 1);
    final rawAddress = value.substring(
      colon + 1,
      queryStart == -1 ? value.length : queryStart,
    );
    if (rawAddress.contains('%') || uri.path != rawAddress) {
      throw _DestinationRejection(_invalidDestination());
    }

    String? amount;
    String? label;
    String? message;
    final uniqueKeys = <String>{};
    if (queryStart != -1 && queryStart + 1 < value.length) {
      final rawQuery = value.substring(queryStart + 1);
      for (final segment in rawQuery.split('&')) {
        if (segment.isEmpty) {
          throw _DestinationRejection(_invalidDestination());
        }
        final equals = segment.indexOf('=');
        final rawKey = equals == -1 ? segment : segment.substring(0, equals);
        final rawValue = equals == -1 ? '' : segment.substring(equals + 1);
        final String key;
        final String decodedValue;
        try {
          key = Uri.decodeQueryComponent(rawKey).toLowerCase();
          decodedValue = Uri.decodeQueryComponent(rawValue);
        } on FormatException {
          throw _DestinationRejection(_invalidDestination());
        }
        if (key.isEmpty ||
            key.length > 128 ||
            key.contains(RegExp(r'[\u0000-\u0020\u007f]'))) {
          throw _DestinationRejection(_invalidDestination());
        }
        if (key.startsWith('req-')) {
          throw _DestinationRejection(_unsupportedRequiredInstruction());
        }
        if (_mustBeUnique(key) && !uniqueKeys.add(key)) {
          throw _DestinationRejection(_invalidDestination());
        }
        switch (key) {
          case 'amount':
            amount = decodedValue;
          case 'label':
            label = _displayText(decodedValue, 256);
          case 'message':
            message = _displayText(decodedValue, 1024);
        }
      }
    }
    if (rawAddress.isEmpty) {
      throw _DestinationRejection(_missingOnchainFallback());
    }
    return _DestinationInput(
      address: rawAddress,
      wasUri: true,
      amount: amount,
      label: label,
      message: message,
    );
  }

  static bool _mustBeUnique(String key) =>
      key == 'amount' || key == 'label' || key == 'message' || key == 'pop';

  static String? _displayText(String value, int maximumLength) {
    if (value != value.trim() ||
        value.length > maximumLength ||
        _unsafeDisplayCharacters.hasMatch(value)) {
      throw _DestinationRejection(_invalidDestination());
    }
    return value.isEmpty ? null : value;
  }

  static String _validateAddress(
    String address,
    BlockchainEnvironment environment,
  ) {
    if (address.isEmpty ||
        address.length > 128 ||
        address != address.trim() ||
        address.contains(RegExp(r'\s'))) {
      throw _DestinationRejection(_invalidDestination());
    }
    final lowered = address.toLowerCase();
    if (lowered.startsWith('bc1') ||
        lowered.startsWith('tb1') ||
        lowered.startsWith('bcrt1')) {
      return _validateSegwitAddress(address, environment);
    }
    return _validateBase58Address(address, environment);
  }

  static String _validateSegwitAddress(
    String address,
    BlockchainEnvironment environment,
  ) {
    bech32_codec.Decoded? decoded;
    var usesBech32m = false;
    try {
      decoded = bech32_codec.bech32.decode(address);
    } on Exception {
      try {
        decoded = bech32_codec.bech32m.decode(address);
      } on Exception {
        throw _DestinationRejection(_invalidDestination());
      }
      usesBech32m = true;
    }
    final expectedHrp = switch (environment) {
      BlockchainEnvironment.mainnet => 'bc',
      BlockchainEnvironment.signet => 'tb',
      BlockchainEnvironment.regtest => 'bcrt',
    };
    if (decoded.prefix != expectedHrp) {
      throw _DestinationRejection(_networkMismatch());
    }
    if (decoded.words.isEmpty) {
      throw _DestinationRejection(_invalidDestination());
    }
    final witnessVersion = decoded.words.first;
    if (witnessVersion > 16) {
      throw _DestinationRejection(_invalidDestination());
    }
    final Uint8List program;
    try {
      program = bech32_codec.bech32.fromWords(
        Uint8List.fromList(decoded.words.skip(1).toList(growable: false)),
      );
    } on Exception {
      throw _DestinationRejection(_invalidDestination());
    }
    if (program.length < 2 ||
        program.length > 40 ||
        (witnessVersion == 0 && program.length != 20 && program.length != 32) ||
        (witnessVersion == 0 && usesBech32m) ||
        (witnessVersion != 0 && !usesBech32m)) {
      throw _DestinationRejection(_invalidDestination());
    }
    return address.toLowerCase();
  }

  static String _validateBase58Address(
    String address,
    BlockchainEnvironment environment,
  ) {
    final Uint8List payload;
    try {
      payload = base58check.decode(address);
    } on Exception {
      throw _DestinationRejection(_invalidDestination());
    } on ArgumentError {
      throw _DestinationRejection(_invalidDestination());
    }
    if (payload.length != 21) {
      throw _DestinationRejection(_invalidDestination());
    }
    final version = payload.first;
    final acceptedVersions = environment == BlockchainEnvironment.mainnet
        ? const <int>{0, 5}
        : const <int>{111, 196};
    if (!acceptedVersions.contains(version)) {
      if (const <int>{0, 5, 111, 196}.contains(version)) {
        throw _DestinationRejection(_networkMismatch());
      }
      throw _DestinationRejection(_invalidDestination());
    }
    return address;
  }

  static WalletAmount? _parseAmount(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d+)(?:\.(\d{1,8}))?$').firstMatch(value);
    if (match == null) {
      throw _DestinationRejection(_invalidAmount());
    }
    final fraction = match.group(2) ?? '';
    final whole = BigInt.tryParse(match.group(1)!);
    final fractional = fraction.isEmpty
        ? BigInt.zero
        : BigInt.parse(fraction.padRight(8, '0'));
    if (whole == null) {
      throw _DestinationRejection(_invalidAmount());
    }
    final satoshis = whole * BigInt.from(_satoshisPerBitcoin) + fractional;
    if (satoshis > BigInt.from(_maximumBitcoinSatoshis)) {
      throw _DestinationRejection(_invalidAmount());
    }
    if (satoshis == BigInt.zero) return null;
    return WalletAmount.onchain(
      assetId: WalletAsset.bitcoin.id,
      units: satoshis.toInt(),
    );
  }

  static AppFailure _invalidDestination() => const AppFailure(
    code: 'bitcoin_destination_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'Enter a valid Bitcoin address or payment request.',
    retryable: false,
  );

  static AppFailure _networkMismatch() => const AppFailure(
    code: 'bitcoin_destination_network_mismatch',
    kind: AppFailureKind.validation,
    userMessage: 'This Bitcoin address belongs to a different network.',
    retryable: false,
  );

  static AppFailure _invalidAmount() => const AppFailure(
    code: 'bitcoin_destination_amount_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'This Bitcoin payment request contains an invalid amount.',
    retryable: false,
  );

  static AppFailure _unsupportedRequiredInstruction() => const AppFailure(
    code: 'bitcoin_destination_instruction_unsupported',
    kind: AppFailureKind.unsupported,
    userMessage:
        'This Bitcoin payment request requires an unsupported feature.',
    retryable: false,
  );

  static AppFailure _missingOnchainFallback() => const AppFailure(
    code: 'bitcoin_destination_onchain_missing',
    kind: AppFailureKind.validation,
    userMessage: 'This payment request does not include an on-chain address.',
    retryable: false,
  );
}

/// Parser-owned checksum-validated Bitcoin on-chain destination.
///
/// The private constructor prevents feature code from fabricating a value that
/// bypasses [BitcoinDestinationParser]. The original URI is intentionally not
/// retained or included in diagnostics.
@immutable
final class BitcoinDestination {
  BitcoinDestination._({
    required this.address,
    required this.wasUri,
    this.amount,
    this.recipientLabel,
    this.message,
  }) {
    if (address.isEmpty ||
        address != address.trim() ||
        address.length > 128 ||
        address.contains(RegExp(r'\s'))) {
      throw ArgumentError.value(address, 'address');
    }
    final encodedAmount = amount;
    if (encodedAmount != null &&
        (encodedAmount.assetId != WalletAsset.bitcoin.id ||
            encodedAmount.rail != PaymentRail.onchain)) {
      throw ArgumentError.value(encodedAmount, 'amount');
    }
    _requireOptionalDisplayText(recipientLabel, 'recipientLabel', 256);
    _requireOptionalDisplayText(message, 'message', 1024);
  }

  final String address;
  final bool wasUri;
  final WalletAmount? amount;
  final String? recipientLabel;
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is BitcoinDestination &&
      other.address == address &&
      other.wasUri == wasUri &&
      other.amount == amount &&
      other.recipientLabel == recipientLabel &&
      other.message == message;

  @override
  int get hashCode =>
      Object.hash(address, wasUri, amount, recipientLabel, message);

  @override
  String toString() =>
      'BitcoinDestination(uri: $wasUri, amount: ${amount != null})';
}

final class _DestinationInput {
  const _DestinationInput({
    required this.address,
    required this.wasUri,
    this.amount,
    this.label,
    this.message,
  });

  final String address;
  final bool wasUri;
  final String? amount;
  final String? label;
  final String? message;
}

final class _DestinationRejection implements Exception {
  const _DestinationRejection(this.failure);

  final AppFailure failure;
}

void _requireOptionalDisplayText(String? value, String field, int maxLength) {
  if (value == null) return;
  if (value != value.trim() ||
      value.length > maxLength ||
      _unsafeDisplayCharacters.hasMatch(value)) {
    throw ArgumentError.value(value, field);
  }
}

final _unsafeDisplayCharacters = RegExp(
  r'[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u070f\u180e'
  r'\u200b-\u200f\u2028\u2029\u202a-\u202e\u2060-\u206f'
  r'\ufeff\ufff9-\ufffb]',
);
