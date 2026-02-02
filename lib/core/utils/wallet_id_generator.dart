import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Utility for generating deterministic wallet identifiers
class WalletIdGenerator {
  WalletIdGenerator._();

  /// Generates a deterministic wallet ID from seed phrase
  ///
  /// Format: First 8 chars + Last 8 chars of SHA-256 hash
  ///
  /// Example: "1F29A3B4" + "C5D6E7F8" = "1F29A3B4 C5D6E7F8"
  static String generateWalletId(String seedPhrase) {
    final bytes = utf8.encode(seedPhrase.trim().toLowerCase());
    final hash = sha256.convert(bytes);
    final hashString = hash.toString();

    // First 8 characters
    final firstPart = hashString.substring(0, 8).toUpperCase();
    // Last 8 characters
    final lastPart = hashString.substring(hashString.length - 8).toUpperCase();

    return '$firstPart $lastPart';
  }

  /// Generates a compact wallet ID (no spaces) for storage
  static String generateCompactWalletId(String seedPhrase) {
    return generateWalletId(seedPhrase).replaceAll(' ', '');
  }

  /// Generates wallet display name from seed phrase
  ///
  /// Currently: First letter of first word, uppercase
  ///
  /// TODO: Allow user customization
  static String generateWalletName(String seedPhrase) {
    final words = seedPhrase.trim().split(' ');
    if (words.isEmpty) return 'Wallet';
    return words.first[0].toUpperCase();
  }
}
