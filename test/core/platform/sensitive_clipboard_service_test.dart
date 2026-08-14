import 'dart:async';

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

  test(
    'oversized replacement releases the lease without erasing content',
    () async {
      var clipboard = '';
      final service = PlatformSensitiveClipboardService(
        reader: () async => clipboard,
        writer: (text) async => clipboard = text,
      );
      addTearDown(service.dispose);

      await service.copySensitive('secret phrase');
      clipboard =
          'x' * (PlatformSensitiveClipboardService.maximumSecretCharacters + 1);

      expect(await service.clearSensitive(), isA<AppSuccess<void>>());
      expect(
        clipboard.length,
        PlatformSensitiveClipboardService.maximumSecretCharacters + 1,
      );

      clipboard = 'secret phrase';
      await service.clearSensitive();
      expect(clipboard, 'secret phrase');
    },
  );

  test('serializes an expiring lease ahead of a newer copy', () async {
    var clipboard = '';
    final readGate = Completer<void>();
    final service = PlatformSensitiveClipboardService(
      reader: () async {
        await readGate.future;
        return clipboard;
      },
      writer: (text) async => clipboard = text,
    );
    addTearDown(service.dispose);

    await service.copySensitive('first phrase');
    final clear = service.clearSensitive();
    final secondCopy = service.copySensitive('second phrase');
    readGate.complete();

    expect(await clear, isA<AppSuccess<void>>());
    expect(await secondCopy, isA<AppSuccess<void>>());
    expect(clipboard, 'second phrase');
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

  test('dispose clears the active lease and rejects later copies', () async {
    var clipboard = '';
    final service = PlatformSensitiveClipboardService(
      reader: () async => clipboard,
      writer: (text) async => clipboard = text,
    );
    await service.copySensitive('secret phrase');

    await service.dispose();

    expect(clipboard, isEmpty);
    final afterDispose = await service.copySensitive('another phrase');
    expect(afterDispose, isA<AppFailureResult<void>>());
    expect(
      (afterDispose as AppFailureResult<void>).failure.code,
      'clipboard_request_invalid',
    );
  });

  test(
    'dispose drains an in-flight clipboard operation before returning',
    () async {
      var clipboard = '';
      final writeGate = Completer<void>();
      final service = PlatformSensitiveClipboardService(
        reader: () async => clipboard,
        writer: (text) async {
          await writeGate.future;
          clipboard = text;
        },
      );

      final copy = service.copySensitive('secret phrase');
      final disposal = service.dispose();
      writeGate.complete();
      await copy;
      await disposal;

      expect(clipboard, isEmpty);
    },
  );
}
