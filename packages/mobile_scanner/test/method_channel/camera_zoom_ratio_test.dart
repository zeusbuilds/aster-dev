import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/method_channel/mobile_scanner_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MethodChannelMobileScanner platform;
  final calls = <MethodCall>[];
  Object? response;

  setUp(() {
    calls.clear();
    response = {'minZoomRatio': 1.0, 'maxZoomRatio': 8.0, 'zoomRatio': 1.0};
    platform = MethodChannelMobileScanner();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, (call) async {
          calls.add(call);
          return response;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, null);
  });

  test('reads native supported bounds and current ratio', () async {
    response = {'minZoomRatio': 0.5, 'maxZoomRatio': 2.4, 'zoomRatio': 1.5};
    final state = await platform.getZoomState();
    expect(calls.single.method, 'getZoomState');
    expect(state.minZoomRatio, 0.5);
    expect(state.maxZoomRatio, 2.4);
    expect(state.zoomRatio, 1.5);
  });

  test(
    'sends actual ratio and trusts readback rather than requested value',
    () async {
      response = {'minZoomRatio': 1.0, 'maxZoomRatio': 8.0, 'zoomRatio': 1.95};
      final state = await platform.setZoomRatio(2);
      expect(calls.single.method, 'setZoomRatio');
      expect(calls.single.arguments, 2.0);
      expect(state.zoomRatio, 1.95);
    },
  );

  test(
    'malformed native replies are unavailable rather than fabricated',
    () async {
      for (final malformed in <Object?>[
        null,
        <String, double>{},
        {'minZoomRatio': 1, 'maxZoomRatio': 4},
        {'minZoomRatio': 0, 'maxZoomRatio': 4, 'zoomRatio': 1},
        {'minZoomRatio': 1, 'maxZoomRatio': 0.5, 'zoomRatio': 1},
        {'minZoomRatio': 1, 'maxZoomRatio': 4, 'zoomRatio': 5},
        {'minZoomRatio': double.nan, 'maxZoomRatio': 4, 'zoomRatio': 1},
        {'minZoomRatio': 1, 'maxZoomRatio': double.infinity, 'zoomRatio': 1},
        {'minZoomRatio': 1, 'maxZoomRatio': 4, 'zoomRatio': '1'},
      ]) {
        response = malformed;
        await expectLater(platform.getZoomState(), throwsFormatException);
        await expectLater(platform.setZoomRatio(2), throwsFormatException);
      }
    },
  );

  test('fixed-zoom camera reports its one supported ratio', () async {
    response = {'minZoomRatio': 1, 'maxZoomRatio': 1, 'zoomRatio': 1};
    final state = await platform.getZoomState();
    expect(state.minZoomRatio, state.maxZoomRatio);
    expect(state.zoomRatio, 1);
  });

  test('invalid numeric requests do not reach native camera', () async {
    for (final invalid in [double.nan, double.infinity, -1.0, 0.0]) {
      await expectLater(platform.setZoomRatio(invalid), throwsArgumentError);
    }
    expect(calls, isEmpty);
  });

  test('unsupported platform has no synthetic zoom fallback', () async {
    final unsupported = _UnsupportedZoomPlatform();
    expect(unsupported.getZoomState, throwsUnsupportedError);
    expect(() => unsupported.setZoomRatio(2), throwsUnsupportedError);
  });
}

class _UnsupportedZoomPlatform extends MobileScannerPlatform {}
