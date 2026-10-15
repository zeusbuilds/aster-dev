import 'package:aster/core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'secret copying fails closed without invoking the platform clipboard',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
      const service = PlatformSensitiveClipboardService();
      for (final text in ['', 'test-only phrase', 'x' * 10000]) {
        final result = await service.copySensitive(text);
        expect(result, isA<AppFailureResult<void>>());
        final failure = (result as AppFailureResult<void>).failure;
        expect(failure.code, 'sensitive_clipboard_disabled');
        expect(failure.kind, AppFailureKind.unsupported);
        expect(failure.retryable, isFalse);
        expect(failure.cause, isNull);
      }
      await service.clearSensitive();
      await service.dispose();
      expect(calls, isEmpty);
    },
  );
}
