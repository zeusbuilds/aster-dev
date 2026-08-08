import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../errors/errors.dart';

typedef ClipboardTextReader = Future<String?> Function();
typedef ClipboardTextWriter = Future<void> Function(String text);

/// Clipboard boundary for short-lived secret material.
abstract interface class SensitiveClipboardService {
  /// Copies [text] and schedules a matching-content clear after [clearAfter].
  Future<AppResult<void>> copySensitive(
    String text, {
    Duration clearAfter = PlatformSensitiveClipboardService.defaultLifetime,
  });

  /// Clears clipboard content only when it still matches this service's lease.
  Future<AppResult<void>> clearSensitive();

  /// Releases timers and attempts a final matching-content clear.
  Future<void> dispose();
}

/// System clipboard adapter that retains only a SHA-256 digest of copied text.
final class PlatformSensitiveClipboardService
    implements SensitiveClipboardService {
  PlatformSensitiveClipboardService({
    ClipboardTextReader? reader,
    ClipboardTextWriter? writer,
  }) : _reader = reader ?? _readSystemClipboard,
       _writer = writer ?? _writeSystemClipboard;

  static const defaultLifetime = Duration(minutes: 1);
  static const maximumSecretCharacters = 512;

  final ClipboardTextReader _reader;
  final ClipboardTextWriter _writer;
  Timer? _clearTimer;
  List<int>? _leasedDigest;
  bool _disposed = false;

  @override
  Future<AppResult<void>> copySensitive(
    String text, {
    Duration clearAfter = defaultLifetime,
  }) async {
    if (_disposed ||
        text.isEmpty ||
        text.length > maximumSecretCharacters ||
        clearAfter <= Duration.zero) {
      return AppResult.failure(
        const AppFailure(
          code: 'clipboard_request_invalid',
          kind: AppFailureKind.validation,
          userMessage: 'The recovery phrase could not be copied safely.',
          retryable: false,
        ),
      );
    }
    try {
      await _writer(text);
      _leasedDigest = _digest(text);
      _clearTimer?.cancel();
      _clearTimer = Timer(clearAfter, () => unawaited(clearSensitive()));
      return const AppResult<void>.success(null);
    } catch (error, stackTrace) {
      _leasedDigest = null;
      _clearTimer?.cancel();
      _clearTimer = null;
      return _failure('clipboard_write_failed', error, stackTrace);
    }
  }

  @override
  Future<AppResult<void>> clearSensitive() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    final expected = _leasedDigest;
    _leasedDigest = null;
    if (expected == null) return const AppResult<void>.success(null);
    try {
      final current = await _reader();
      if (current != null && _constantTimeEquals(_digest(current), expected)) {
        await _writer('');
      }
      return const AppResult<void>.success(null);
    } catch (error, stackTrace) {
      return _failure('clipboard_clear_failed', error, stackTrace);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await clearSensitive();
  }

  static AppResult<void> _failure(
    String code,
    Object error,
    StackTrace stackTrace,
  ) {
    return AppResult.failure(
      AppFailure(
        code: code,
        kind: AppFailureKind.unavailable,
        userMessage: 'The recovery phrase could not be copied safely.',
        retryable: true,
        cause: FailureMapper.diagnosticCause(error),
        stackTrace: stackTrace,
      ),
    );
  }

  static List<int> _digest(String text) =>
      sha256.convert(utf8.encode(text)).bytes;

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static Future<String?> _readSystemClipboard() async {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  }

  static Future<void> _writeSystemClipboard(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }
}
