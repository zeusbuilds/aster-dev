import 'package:aster/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clears copied secret only while its lease still matches', () async {
    var clipboard = '';
    final service = PlatformSensitiveClipboardService(
      reader: () async => clipboard,
      writer: (text) async => clipboard = text,
    );
    addTearDown(service.dispose);

    expect(
      await service.copySensitive('secret phrase'),
      isA<AppSuccess<void>>(),
    );
    expect(clipboard, 'secret phrase');

    expect(await service.clearSensitive(), isA<AppSuccess<void>>());
    expect(clipboard, isEmpty);
  });

  test('does not erase clipboard content written after the secret', () async {
    var clipboard = '';
    final service = PlatformSensitiveClipboardService(
      reader: () async => clipboard,
      writer: (text) async => clipboard = text,
    );
    addTearDown(service.dispose);

    await service.copySensitive('secret phrase');
    clipboard = 'user replacement';
    await service.clearSensitive();

    expect(clipboard, 'user replacement');
  });

  test('expires a matching secret after the bounded lifetime', () async {
    var clipboard = '';
    final service = PlatformSensitiveClipboardService(
      reader: () async => clipboard,
      writer: (text) async => clipboard = text,
    );
    addTearDown(service.dispose);

    await service.copySensitive(
      'secret phrase',
      clearAfter: const Duration(milliseconds: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(clipboard, isEmpty);
  });

  test('returns a redacted failure when the platform write fails', () async {
    final service = PlatformSensitiveClipboardService(
      reader: () async => null,
      writer: (text) async => throw StateError('contains $text'),
    );
    addTearDown(service.dispose);

    final result = await service.copySensitive('secret phrase');

    expect(result, isA<AppFailureResult<void>>());
    final failure = (result as AppFailureResult<void>).failure;
    expect(failure.code, 'clipboard_write_failed');
    expect(failure.userMessage, isNot(contains('secret')));
    expect(failure.cause, isA<FailureDiagnostic>());
  });
}
