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
      final failedResult = await failed.shareText(
        'payment-request',
      ) as AppFailureResult<ShareDisposition>;
      expect(failedResult.failure.code, 'share_failed');
      expect(
        failedResult.failure.userMessage,
        isNot(contains('private payment request')),
      );
    },
  );

  test(
    'external URI adapter accepts only bounded public HTTPS links',
    () async {
      Uri? opened;
      final service = PlatformExternalUriService(
        invoker: (uri) async {
          opened = uri;
          return true;
        },
      );
      final uri = Uri.parse('https://mempool.space/tx/${'a' * 64}');

      expect(await service.open(uri), isA<AppSuccess<void>>());
      expect(opened, uri);
      expect(
        await service.open(Uri.parse('http://mempool.space/tx/value')),
        isA<AppFailureResult<void>>(),
      );
      expect(
        await service.open(Uri.parse('https://token@mempool.space/tx/value')),
        isA<AppFailureResult<void>>(),
      );

      final unavailable = PlatformExternalUriService(
        invoker: (uri) async => false,
      );
      final unavailableResult = await unavailable.open(uri);
      expect(
        (unavailableResult as AppFailureResult<void>).failure.code,
        'external_uri_unavailable',
      );

      final failed = PlatformExternalUriService(
        invoker: (uri) => throw StateError('private browser detail'),
      );
      final failedResult = await failed.open(uri) as AppFailureResult<void>;
      expect(failedResult.failure.code, 'external_uri_open_failed');
      expect(
        failedResult.failure.userMessage,
        isNot(contains('private browser detail')),
      );
    },
  );

  test('app metadata adapter returns only bounded display fields', () async {
    final service = PlatformAppMetadataService(
      loader: () async =>
          const AppBuildMetadata(version: '1.0.0', buildNumber: '42'),
    );

    final result = await service.load() as AppSuccess<AppBuildMetadata>;
    expect(result.value.version, '1.0.0');
    expect(result.value.buildNumber, '42');
    expect(
      const AppBuildMetadata(
        version: '1.0.0-beta.1',
        buildNumber: '42_debug',
      ).isValid,
      isTrue,
    );

    for (final metadata in [
      const AppBuildMetadata(version: '', buildNumber: '1'),
      const AppBuildMetadata(version: ' 1.0.0', buildNumber: '1'),
      const AppBuildMetadata(version: '1.0 beta', buildNumber: '1'),
      const AppBuildMetadata(version: '1.0.0\u202e', buildNumber: '1'),
      const AppBuildMetadata(version: '1.0.0', buildNumber: '1\nsecret'),
      AppBuildMetadata(
        version: '1' * (AppBuildMetadata.maximumFieldCharacters + 1),
        buildNumber: '1',
      ),
    ]) {
      final invalid = PlatformAppMetadataService(loader: () async => metadata);
      final failure =
          await invalid.load() as AppFailureResult<AppBuildMetadata>;
      expect(failure.failure.code, 'app_metadata_invalid');
      expect(failure.failure.retryable, isFalse);
    }
  });

  test('app metadata adapter redacts platform failures', () async {
    final service = PlatformAppMetadataService(
      loader: () => throw StateError('private package detail'),
    );

    final result = await service.load() as AppFailureResult<AppBuildMetadata>;
    expect(result.failure.code, 'app_metadata_load_failed');
    expect(result.failure.retryable, isTrue);
    expect(result.failure.userMessage, isNot(contains('private package')));
  });
}
