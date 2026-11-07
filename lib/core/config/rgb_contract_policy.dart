import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../validation/protocol_text_policy.dart';

/// Shared bounded public-contract validation for runtime and release tooling.
abstract final class RgbContractPolicy {
  static const maximumContractBytes = 1024 * 1024;
  static const maximumEncodedCharacters = ((maximumContractBytes + 2) ~/ 3) * 4;

  static void validate({
    required String contractBase64,
    required String sha256Digest,
    required String nativeName,
    required String nativeTicker,
  }) {
    const failure = FormatException(
      'Approved RGB contract configuration is invalid.',
    );
    if (contractBase64.isEmpty ||
        contractBase64.length > maximumEncodedCharacters ||
        contractBase64.length % 4 != 0 ||
        !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(contractBase64) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Digest) ||
        nativeName.isEmpty ||
        nativeName.length > 256 ||
        nativeName != nativeName.trim() ||
        nativeName.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e) ||
        !ProtocolTextPolicy.isVisibleAscii(
          nativeTicker,
          maximumCharacters: 32,
        )) {
      throw failure;
    }
    final bytes = base64Decode(contractBase64);
    if (bytes.isEmpty ||
        bytes.length > maximumContractBytes ||
        base64Encode(bytes) != contractBase64 ||
        sha256.convert(bytes).toString() != sha256Digest) {
      throw failure;
    }
  }
}
