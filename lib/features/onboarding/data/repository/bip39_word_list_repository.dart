import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../../../core/errors/errors.dart';

/// Validated canonical BIP39 English vocabulary used for per-word feedback.
final class Bip39WordList {
  Bip39WordList._(Set<String> words) : _words = Set<String>.unmodifiable(words);

  final Set<String> _words;

  /// Whether [word] is one canonical lowercase BIP39 English word.
  bool contains(String word) => _words.contains(word);

  /// Number of validated entries. BIP39 English requires exactly 2,048.
  int get length => _words.length;
}

/// Loads and integrity-checks the vendored canonical BIP39 English list.
///
/// The list is a UX aid only. Full phrase and checksum validity remains owned
/// by the SDK-backed wallet repository.
final class Bip39WordListRepository {
  Bip39WordListRepository(this._assets);

  static const assetPath = 'assets/data/bip39_english.txt';
  static const expectedSha256 =
      '2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda';
  static const expectedWordCount = 2048;

  final AssetBundle _assets;
  Future<AppResult<Bip39WordList>>? _loadRequest;

  /// Returns one shared validated load for the immutable bundled vocabulary.
  ///
  /// A failure is retained for this repository lifetime because retrying cannot
  /// repair bytes installed with the application. A new app process or build
  /// creates a new repository and performs the integrity check again.
  Future<AppResult<Bip39WordList>> load() => _loadRequest ??= _load();

  Future<AppResult<Bip39WordList>> _load() async {
    try {
      final data = await _assets.load(assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (sha256.convert(bytes).toString() != expectedSha256) {
        throw const FormatException('BIP39 word-list digest mismatch.');
      }
      final source = utf8.decode(bytes, allowMalformed: false);
      final words = const LineSplitter().convert(source);
      _validate(words);
      return AppResult.success(Bip39WordList._(words.toSet()));
    } catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'bip39_word_list_invalid',
          kind: AppFailureKind.configuration,
          userMessage:
              'Recovery phrase validation is unavailable in this build.',
          retryable: false,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  static void _validate(List<String> words) {
    if (words.length != expectedWordCount) {
      throw const FormatException('Invalid BIP39 word-list length.');
    }
    final seen = <String>{};
    String? previous;
    for (final word in words) {
      if (!RegExp(r'^[a-z]+$').hasMatch(word) || !seen.add(word)) {
        throw const FormatException('Invalid BIP39 word-list entry.');
      }
      if (previous != null && previous.compareTo(word) >= 0) {
        throw const FormatException('BIP39 word list is not ordered.');
      }
      previous = word;
    }
  }
}
