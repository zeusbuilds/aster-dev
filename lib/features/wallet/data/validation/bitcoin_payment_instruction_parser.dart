import 'package:bs58check/bs58check.dart' as base58check;
import 'package:dart_bech32/dart_bech32.dart' as bech32_codec;
import 'package:flutter/foundation.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/errors.dart';
import '../../../../core/validation/validation.dart';
import '../../domain/models/models.dart';
import '../../domain/validation/validation.dart';

/// Validates and canonicalizes a plain Bitcoin address for one environment.
///
/// Returns `null` when [value] is malformed, has an invalid checksum, or belongs
/// to another network. Payment URIs are deliberately outside this narrow
/// contract and must be passed to
/// [BitcoinPaymentInstructionDecoder.decodeOnchain].
abstract interface class BitcoinAddressValidator {
  String? normalizeAddress(String value, BlockchainEnvironment environment);
}

/// Resolves a selected Bitcoin payment rail from direct or BIP321 input.
abstract interface class BitcoinPaymentInstructionDecoder
    implements BitcoinAddressValidator {
  AppResult<BitcoinDestination> decodeOnchain(
    String value,
    BlockchainEnvironment environment,
  );

  AppResult<BitcoinLightningInstruction> extractLightning(String value);
}

/// Checksum-validating BIP173, BIP350, and BIP321 instruction parser.
///
/// The caller selects the rail before parsing, so this parser never switches
/// rails based on URI contents. Repeated on-chain instructions are evaluated in
/// sender order, while repeated Lightning invoices fail as ambiguous because
/// the app has no invoice-choice UI. Every unsupported `req-*` instruction
/// fails closed.
final class BitcoinPaymentInstructionParser
    implements BitcoinPaymentInstructionDecoder {
  const BitcoinPaymentInstructionParser();

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
  AppResult<BitcoinDestination> decodeOnchain(
    String value,
    BlockchainEnvironment environment,
  ) {
    if (!_isValidInstructionInput(value)) {
      return AppResult.failure(_invalidDestination());
    }

    try {
      final uri = _parsePaymentUri(value);
      final address = uri == null
          ? _validateAddress(value, environment)
          : _resolveOnchainAddress(uri, environment);
      final amount = _parseAmount(uri?.singleValue('amount'));
      return AppResult.success(
        BitcoinDestination._(
          address: address,
          wasUri: uri != null,
          amount: amount,
          recipientLabel: _displayText(uri?.singleValue('label'), 256),
          message: _displayText(uri?.singleValue('message'), 1024),
        ),
      );
    } on _DestinationRejection catch (rejection) {
      return AppResult.failure(rejection.failure);
    }
  }

  @override
  AppResult<BitcoinLightningInstruction> extractLightning(String value) {
    if (!_isValidInstructionInput(value)) {
      return AppResult.failure(_invalidLightningInstruction());
    }

    try {
      final uri = _parsePaymentUri(value);
      if (uri == null) {
        return AppResult.success(
          BitcoinLightningInstruction._(invoice: value, wasUri: false),
        );
      }
      final invoices = uri.valuesFor('lightning');
      if (invoices.isEmpty) {
        throw _DestinationRejection(_missingLightningInstruction());
      }
      if (invoices.length != 1) {
        throw _DestinationRejection(_ambiguousLightningInstruction());
      }
      final invoice = invoices.single;
      if (!_isValidInstructionInput(invoice)) {
        throw _DestinationRejection(_invalidLightningInstruction());
      }
      return AppResult.success(
        BitcoinLightningInstruction._(
          invoice: invoice,
          wasUri: true,
          recipientLabel: _displayText(uri.singleValue('label'), 256),
          message: _displayText(uri.singleValue('message'), 1024),
        ),
      );
    } on _DestinationRejection catch (rejection) {
      return AppResult.failure(rejection.failure);
    }
  }

  static _PaymentUri? _parsePaymentUri(String value) {
    if (!value.toLowerCase().startsWith('bitcoin:')) return null;

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

    final values = <String, List<String>>{};
    final uniqueKeys = <String>{};
    if (queryStart != -1 && queryStart + 1 == value.length) {
      throw _DestinationRejection(_invalidDestination());
    }
    if (queryStart != -1) {
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
          // BIP321 follows RFC 3986, where `+` is data rather than HTML form
          // whitespace. Splitting separators before decoding also preserves an
          // encoded `=` while rejecting an unescaped second separator below.
          key = Uri.decodeComponent(rawKey).toLowerCase();
          decodedValue = Uri.decodeComponent(rawValue);
        } on FormatException {
          throw _DestinationRejection(_invalidDestination());
        }
        if (!WalletProtocolText.isIdentifier(key, maximumCharacters: 128)) {
          throw _DestinationRejection(_invalidDestination());
        }
        if (key.startsWith('req-')) {
          throw _DestinationRejection(_unsupportedRequiredInstruction());
        }
        if ((equals == -1 && _requiresValueSeparator(key)) ||
            rawValue.contains('=')) {
          throw _DestinationRejection(_invalidDestination());
        }
        if (_mustBeUnique(key) && !uniqueKeys.add(key)) {
          throw _DestinationRejection(_invalidDestination());
        }
        values.putIfAbsent(key, () => <String>[]).add(decodedValue);
      }
    }
    if (rawAddress.isEmpty && values.isEmpty) {
      throw _DestinationRejection(_invalidDestination());
    }
    final paymentUri = _PaymentUri(fallbackAddress: rawAddress, values: values);
    if (rawAddress.isEmpty && !paymentUri.hasPaymentInstruction) {
      throw _DestinationRejection(_invalidDestination());
    }
    _parseAmount(paymentUri.singleValue('amount'));
    _displayText(paymentUri.singleValue('label'), 256);
    _displayText(paymentUri.singleValue('message'), 1024);
    return paymentUri;
  }

  static bool _mustBeUnique(String key) =>
      key == 'amount' || key == 'label' || key == 'message' || key == 'pop';

  static bool _requiresValueSeparator(String key) =>
      _standardInstructionKeys.contains(key) ||
      _networkInstructionKeys.contains(key);

  static String? _displayText(String? value, int maximumLength) {
    if (value == null || value.isEmpty) return null;
    if (!DisplayTextPolicy.isSafe(value, maximumCharacters: maximumLength)) {
      throw _DestinationRejection(_invalidDestination());
    }
    return value;
  }

  static bool _isValidInstructionInput(String value) =>
      WalletProtocolText.isEncodedValue(
        value,
        maximumCharacters: _maximumInputLength,
      );

  static String _resolveOnchainAddress(
    _PaymentUri uri,
    BlockchainEnvironment environment,
  ) {
    if (uri.fallbackAddress.isNotEmpty) {
      return _validateAddress(uri.fallbackAddress, environment);
    }
    final expectedKey = switch (environment) {
      BlockchainEnvironment.mainnet => 'bc',
      BlockchainEnvironment.signet => 'tb',
      BlockchainEnvironment.regtest => 'bcrt',
    };
    final candidates = uri.valuesFor(expectedKey);
    if (candidates.isEmpty) {
      if (_networkInstructionKeys.any(uri.hasKey)) {
        throw _DestinationRejection(_networkMismatch());
      }
      throw _DestinationRejection(_missingOnchainFallback());
    }
    final normalized = <String>[];
    for (final candidate in candidates) {
      if (!candidate.toLowerCase().startsWith('${expectedKey}1')) {
        throw _DestinationRejection(_invalidDestination());
      }
      normalized.add(_validateAddress(candidate, environment));
    }
    return normalized.first;
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

  static AppFailure _invalidLightningInstruction() => const AppFailure(
    code: 'bitcoin_lightning_instruction_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'Enter a valid Lightning invoice or Bitcoin payment request.',
    retryable: false,
  );

  static AppFailure _missingLightningInstruction() => const AppFailure(
    code: 'bitcoin_lightning_instruction_missing',
    kind: AppFailureKind.validation,
    userMessage: 'This payment request does not include a Lightning invoice.',
    retryable: false,
  );

  static AppFailure _ambiguousLightningInstruction() => const AppFailure(
    code: 'bitcoin_lightning_instruction_ambiguous',
    kind: AppFailureKind.unsupported,
    userMessage: 'This payment request contains multiple Lightning choices, which are not yet supported.',
    retryable: false,
  );
}

/// Parser-owned checksum-validated Bitcoin on-chain destination.
///
/// The private constructor prevents feature code from fabricating a value that
/// bypasses [BitcoinPaymentInstructionParser]. The original URI is
/// intentionally not retained or included in diagnostics.
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

/// Parser-owned BOLT11 instruction selected from direct or BIP321 input.
@immutable
final class BitcoinLightningInstruction {
  BitcoinLightningInstruction._({
    required this.invoice,
    required this.wasUri,
    this.recipientLabel,
    this.message,
  }) {
    if (!BitcoinPaymentInstructionParser._isValidInstructionInput(invoice)) {
      throw ArgumentError.value(invoice, 'invoice');
    }
    _requireOptionalDisplayText(recipientLabel, 'recipientLabel', 256);
    _requireOptionalDisplayText(message, 'message', 1024);
  }

  final String invoice;
  final bool wasUri;
  final String? recipientLabel;
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is BitcoinLightningInstruction &&
      other.invoice == invoice &&
      other.wasUri == wasUri &&
      other.recipientLabel == recipientLabel &&
      other.message == message;

  @override
  int get hashCode => Object.hash(invoice, wasUri, recipientLabel, message);

  @override
  String toString() => 'BitcoinLightningInstruction(uri: $wasUri)';
}

final class _PaymentUri {
  _PaymentUri({
    required this.fallbackAddress,
    required Map<String, List<String>> values,
  }) : _values = Map<String, List<String>>.unmodifiable(
         values.map(
           (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
         ),
       );

  final String fallbackAddress;
  final Map<String, List<String>> _values;

  bool get hasPaymentInstruction =>
      _values.keys.any((key) => !_generalInstructionKeys.contains(key));

  bool hasKey(String key) => _values.containsKey(key);

  List<String> valuesFor(String key) => _values[key] ?? const <String>[];

  String? singleValue(String key) {
    final values = valuesFor(key);
    return values.isEmpty ? null : values.single;
  }
}

final class _DestinationRejection implements Exception {
  const _DestinationRejection(this.failure);

  final AppFailure failure;
}

void _requireOptionalDisplayText(String? value, String field, int maxLength) {
  if (value == null) return;
  if (!DisplayTextPolicy.isSafe(value, maximumCharacters: maxLength)) {
    throw ArgumentError.value(value, field);
  }
}

const _generalInstructionKeys = <String>{'amount', 'label', 'message', 'pop'};
const _standardInstructionKeys = <String>{
  ..._generalInstructionKeys,
  'lightning',
  'lno',
  'pay',
  'sp',
};
const _networkInstructionKeys = <String>{'bc', 'tb', 'bcrt'};
