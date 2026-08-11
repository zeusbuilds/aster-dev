import 'package:flutter/services.dart';

import '../errors/errors.dart';

typedef PlainClipboardTextReader = Future<String?> Function();
typedef PlainClipboardTextWriter = Future<void> Function(String text);

/// Non-secret system clipboard boundary for payment addresses and requests.
abstract interface class ClipboardService {
  /// Reads bounded plain text without retaining or logging its contents.
  Future<AppResult<String?>> readText();

  /// Writes bounded plain text without retaining or logging its contents.
  Future<AppResult<void>> writeText(String text);
}

/// Flutter clipboard adapter used only behind [ClipboardService].
final class PlatformClipboardService implements ClipboardService {
  PlatformClipboardService({
    PlainClipboardTextReader? reader,
    PlainClipboardTextWriter? writer,
  }) : _reader = reader ?? _readSystemClipboard,
       _writer = writer ?? _writeSystemClipboard;

  static const maximumCharacters = 8192;
  final PlainClipboardTextReader _reader;
  final PlainClipboardTextWriter _writer;

  @override
  Future<AppResult<String?>> readText() async {
    try {
      final value = await _reader();
      if (value != null && value.length > maximumCharacters) {
        return AppResult.failure(_invalidClipboardFailure());
      }
      return AppResult.success(value);
    } catch (error, stackTrace) {
      return AppResult.failure(
        _platformFailure('clipboard_read_failed', error, stackTrace),
      );
    }
  }

  @override
  Future<AppResult<void>> writeText(String text) async {
    if (text.trim().isEmpty || text.length > maximumCharacters) {
      return AppResult.failure(_invalidClipboardFailure());
    }
    try {
      await _writer(text);
      return const AppResult.success(null);
    } catch (error, stackTrace) {
      return AppResult.failure(
        _platformFailure('clipboard_write_failed', error, stackTrace),
      );
    }
  }

  static AppFailure _invalidClipboardFailure() => const AppFailure(
    code: 'clipboard_value_invalid',
    kind: AppFailureKind.validation,
    userMessage: 'The clipboard text is not a supported payment value.',
    retryable: false,
  );

  static AppFailure _platformFailure(
    String code,
    Object error,
    StackTrace stackTrace,
  ) {
    return AppFailure(
      code: code,
      kind: AppFailureKind.unavailable,
      userMessage: 'The system clipboard is unavailable.',
      retryable: true,
      cause: FailureMapper.diagnosticCause(error),
      stackTrace: stackTrace,
    );
  }

  static Future<String?> _readSystemClipboard() async {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  }

  static Future<void> _writeSystemClipboard(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }
}
