import 'dart:async';

import 'package:aster/core/security/device_authentication.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.aster/device_authentication');
  late PlatformDeviceAuthentication device;
  late List<MethodCall> calls;
  Object? response;
  PlatformException? platformError;

  setUp(() {
    calls = [];
    response = null;
    platformError = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (platformError case final error?) throw error;
      return response;
    });
    device = PlatformDeviceAuthentication(channel: channel);
  });
  tearDown(() {
    channel.setMethodCallHandler(null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('secured status is independent of biometric availability', () async {
    response = {'secured': true, 'captured': false};
    expect(await device.status(), DeviceSecurityStatus.secured);
    expect(calls.single.method, 'getStatus');
    expect(calls.single.arguments, isNull);
    expect(device.isCaptured, isFalse);
  });

  test(
    'only an explicit false device-credential status permits bypass',
    () async {
      response = {'secured': false, 'captured': false};
      expect(await device.status(), DeviceSecurityStatus.unsecured);
      for (final malformed in <Object?>[
        null,
        {},
        {'captured': false},
        {'secured': null, 'captured': false},
        {'secured': 0, 'captured': false},
        {'secured': 'false', 'captured': false},
        {'secured': false},
        {'secured': false, 'captured': null},
        {'secured': false, 'captured': 'false'},
      ]) {
        response = malformed;
        await expectLater(device.status(), throwsA(isA<PlatformException>()));
      }
    },
  );

  test(
    'recognizes precisely the three native authentication outcomes',
    () async {
      for (final entry in {
        'authenticated': DeviceAuthenticationResult.authenticated,
        'cancelled': DeviceAuthenticationResult.cancelled,
        'unsecured': DeviceAuthenticationResult.unsecured,
      }.entries) {
        response = entry.key;
        expect(await device.authenticate('Unlock Aster'), entry.value);
        expect(calls.last.method, 'authenticate');
        expect(calls.last.arguments, {'reason': 'Unlock Aster'});
      }
    },
  );

  test('null and unrecognized outcomes never authenticate or bypass', () async {
    for (final malformed in <Object?>[null, '', 'success', 'true', true, 1]) {
      response = malformed;
      await expectLater(device.authenticate('Unlock Aster'), throwsA(anything));
    }
  });

  test(
    'native failures retain their typed error and never become success',
    () async {
      platformError = PlatformException(code: 'device_auth_locked_out');
      await expectLater(
        device.status(),
        throwsA(
          isA<PlatformException>().having(
            (value) => value.code,
            'code',
            'device_auth_locked_out',
          ),
        ),
      );
      await expectLater(
        device.authenticate('Reveal your recovery phrase'),
        throwsA(
          isA<PlatformException>().having(
            (value) => value.code,
            'code',
            'device_auth_locked_out',
          ),
        ),
      );
    },
  );

  test('rejects absent or oversized reasons before calling the OS', () async {
    for (final reason in ['', '  ', 'x' * 161]) {
      await expectLater(device.authenticate(reason), throwsArgumentError);
    }
    expect(calls, isEmpty);
  });

  test(
    'capture status reports only changes including initial status discovery',
    () async {
      final captures = <bool>[];
      final subscription = device.captureChanges.listen(captures.add);
      addTearDown(subscription.cancel);
      response = {'secured': true, 'captured': true};
      await device.status();
      await device.status();
      expect(device.isCaptured, isTrue);
      expect(captures, [true]);
      response = {'secured': true, 'captured': false};
      await device.status();
      expect(device.isCaptured, isFalse);
      expect(captures, [true, false]);
    },
  );

  test(
    'native capture callbacks update capture status without wallet data',
    () async {
      final captures = <bool>[];
      final subscription = device.captureChanges.listen(captures.add);
      addTearDown(subscription.cancel);
      final result = await _fromNative(
        binding,
        channel,
        const MethodCall('captureChanged', true),
      );
      expect(result, isNull);
      expect(device.isCaptured, isTrue);
      await _fromNative(
        binding,
        channel,
        const MethodCall('captureChanged', true),
      );
      await _fromNative(
        binding,
        channel,
        const MethodCall('captureChanged', false),
      );
      expect(captures, [true, false]);
      expect(device.isCaptured, isFalse);
      expect(calls, isEmpty);
    },
  );

  test('invalid native callbacks do not change capture state', () async {
    for (final call in [
      const MethodCall('captureChanged', null),
      const MethodCall('captureChanged', 'true'),
      const MethodCall('unexpected', true),
    ]) {
      await expectLater(
        _fromNative(binding, channel, call),
        throwsA(
          isA<PlatformException>().having(
            (value) => value.code,
            'code',
            'device_auth_invalid_event',
          ),
        ),
      );
      expect(device.isCaptured, isFalse);
    }
  });

  test(
    'genuine native background callback is distinct from auth inactivity',
    () async {
      var events = 0;
      final subscription = device.backgroundEvents.listen((_) => events += 1);
      addTearDown(subscription.cancel);
      await _fromNative(binding, channel, const MethodCall('backgrounded'));
      expect(events, 1);
      expect(device.isCaptured, isFalse);
      await expectLater(
        _fromNative(binding, channel, const MethodCall('backgrounded', true)),
        throwsA(
          isA<PlatformException>().having(
            (value) => value.code,
            'code',
            'device_auth_invalid_event',
          ),
        ),
      );
      expect(events, 1);
    },
  );

  test(
    'cancel, presentation cleanup and capture use narrow platform commands',
    () async {
      await device.cancel();
      await device.finishAuthenticationPresentation();
      await device.setSensitive(true);
      await device.setSensitive(false);
      expect(calls.map((call) => call.method), [
        'cancel',
        'finishAuthenticationPresentation',
        'setSensitive',
        'setSensitive',
      ]);
      expect(calls[0].arguments, isNull);
      expect(calls[1].arguments, isNull);
      expect(calls[2].arguments, {'sensitive': true});
      expect(calls[3].arguments, {'sensitive': false});
    },
  );
}

Future<Object?> _fromNative(
  TestWidgetsFlutterBinding binding,
  MethodChannel channel,
  MethodCall call,
) async {
  final reply = Completer<Object?>();
  // Test a native-to-Dart callback through the actual registered channel handler.
  // ignore: deprecated_member_use
  await binding.defaultBinaryMessenger.handlePlatformMessage(
    channel.name,
    channel.codec.encodeMethodCall(call),
    (response) {
      try {
        reply.complete(
          response == null ? null : channel.codec.decodeEnvelope(response),
        );
      } catch (error, stackTrace) {
        reply.completeError(error, stackTrace);
      }
    },
  );
  return reply.future;
}
