import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';
import 'rgb_contract_policy.dart';

/// Issuer-approved public genesis bytes and their exact native metadata.
///
/// This contains no wallet keys or balances. A checksum authenticates the
/// reviewed bytes, not the issuer; approval and deployment remain release
/// responsibilities. Native import must independently validate the contract.
@immutable
final class RgbContractConfiguration {
  const RgbContractConfiguration({
    required this.contractBase64,
    required this.sha256Digest,
    required this.nativeName,
    required this.nativeTicker,
  });

  static const maximumContractBytes = RgbContractPolicy.maximumContractBytes;
  static const maximumEncodedCharacters =
      RgbContractPolicy.maximumEncodedCharacters;

  final String contractBase64;
  final String sha256Digest;
  final String nativeName;
  final String nativeTicker;

  /// Validates bounded canonical Base64 and exact digest before native access.
  void validate() {
    try {
      RgbContractPolicy.validate(
        contractBase64: contractBase64,
        sha256Digest: sha256Digest,
        nativeName: nativeName,
        nativeTicker: nativeTicker,
      );
    } on FormatException {
      throw const AppConfigurationException();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RgbContractConfiguration &&
      other.contractBase64 == contractBase64 &&
      other.sha256Digest == sha256Digest &&
      other.nativeName == nativeName &&
      other.nativeTicker == nativeTicker;

  @override
  int get hashCode =>
      Object.hash(contractBase64, sha256Digest, nativeName, nativeTicker);
}
