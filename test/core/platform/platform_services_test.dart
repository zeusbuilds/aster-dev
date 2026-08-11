import 'package:aster/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'plain clipboard adapter bounds values and maps platform faults',
    () async {
      var written = '';
      final service = PlatformClipboardService(
        reader: () async => 'payment-request',
        writer: (value) async => written = value,
      );

      expect(
        (await service.readText() as AppSuccess<String?>).value,
        'payment-request',
      );
      expect(await service.writeText('address'), isA<AppSuccess<void>>());
      expect(written, 'address');
      expect(await service.writeText(''), isA<AppFailureResult<void>>());
      expect(await service.writeText('   '), isA<AppFailureResult<void>>());
      expect(
        await service.writeText(
          'a' * (PlatformClipboardService.maximumCharacters + 1),
        ),
        isA<AppFailureResult<void>>(),
      );

      final oversizedRead = PlatformClipboardService(
        reader: () async =>
            'a' * (PlatformClipboardService.maximumCharacters + 1),
        writer: (value) async {},
      );
      expect(await oversizedRead.readText(), isA<AppFailureResult<String?>>());

      final failed = PlatformClipboardService(
        reader: () => throw StateError('private payload'),
        writer: (value) async {},
      );
      final result = await failed.readText() as AppFailureResult<String?>;
      expect(result.failure.code, 'clipboard_read_failed');
      expect(result.failure.userMessage, isNot(contains('private payload')));
    },
  );

  test(
    'share adapter preserves dismissal and fails closed when unavailable',
    () async {
      String? shared;
      final service = PlatformShareService(
        invoker: (text, subject, origin) async {
          shared = text;
          return ShareInvocationOutcome.dismissed;
        },
      );
      final result = await service.shareText(
        'payment-request',
        origin: const ShareOrigin(left: 1, top: 2, width: 3, height: 4),
      );
      expect(
        (result as AppSuccess<ShareDisposition>).value,
        ShareDisposition.dismissed,
      );
      expect(shared, 'payment-request');

      final unavailable = PlatformShareService(
        invoker: (text, subject, origin) async =>
            ShareInvocationOutcome.unavailable,
      );
      final failure = await unavailable.shareText('payment-request');
      expect(
        (failure as AppFailureResult<ShareDisposition>).failure.code,
        'share_unavailable',
      );

      final invalid = await service.shareText(
        'payment-request',
        origin: const ShareOrigin(
          left: double.nan,
          top: 0,
          width: 1,
          height: 1,
        ),
      );
      expect(
        (invalid as AppFailureResult<ShareDisposition>).failure.code,
        'share_value_invalid',
      );
      expect(
        await service.shareText('   '),
        isA<AppFailureResult<ShareDisposition>>(),
      );

      final failed = PlatformShareService(
        invoker: (text, subject, origin) =>
            throw StateError('private payment request'),
      );
      final failedResult =
          await failed.shareText('payment-request')
              as AppFailureResult<ShareDisposition>;
      expect(failedResult.failure.code, 'share_failed');
      expect(
        failedResult.failure.userMessage,
        isNot(contains('private payment request')),
      );
    },
  );
}
