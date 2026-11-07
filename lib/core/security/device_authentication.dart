import 'dart:async';

import 'package:flutter/services.dart';

/// Only an authoritative absence of a device credential permits bypass.
/// Biometric availability, cancellation and platform failures are separate.
enum DeviceSecurityStatus { secured, unsecured }

enum DeviceAuthenticationResult { authenticated, cancelled, unsecured }

abstract interface class DeviceAuthentication {
  Future<DeviceSecurityStatus> status();
  Future<DeviceAuthenticationResult> authenticate(String reason);
  Future<void> cancel();
  Future<void> setSensitive(bool sensitive);
  Stream<bool> get captureChanges;
  bool get isCaptured;
}

/// Native confirmation of a genuine background transition. A system auth
/// prompt's temporary inactivity must never emit this event.
abstract interface class DeviceAuthenticationBackgroundEvents {
  Stream<void> get backgroundEvents;
}

/// Ends only the visual ownership of a completed OS prompt. The native result
/// may precede lifecycle delivery; keep both layers in agreement until Dart has
/// observed the host return. This method never authorizes wallet access.
abstract interface class DeviceAuthenticationPresentation {
  Future<void> finishAuthenticationPresentation();
}

/// Uses the operating system's credential prompt; Aster never receives a PIN,
/// passcode, biometric sample or authentication error description.
final class PlatformDeviceAuthentication
    implements
        DeviceAuthentication,
        DeviceAuthenticationBackgroundEvents,
        DeviceAuthenticationPresentation {
  PlatformDeviceAuthentication({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.aster.wallet/device_authentication') {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final _captureChanges = StreamController<bool>.broadcast(sync: true);
  final _backgroundEvents = StreamController<void>.broadcast(sync: true);
  bool _captured = false;

  @override
  bool get isCaptured => _captured;

  @override
  Stream<bool> get captureChanges => _captureChanges.stream;

  @override
  Stream<void> get backgroundEvents => _backgroundEvents.stream;

  @override
  Future<DeviceSecurityStatus> status() async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'getStatus',
    );
    if (response?['secured'] is! bool || response?['captured'] is! bool) {
      throw _invalidResponse();
    }
    _updateCapture(response!['captured']! as bool);
    return response['secured']! as bool
        ? DeviceSecurityStatus.secured
        : DeviceSecurityStatus.unsecured;
  }

  @override
  Future<DeviceAuthenticationResult> authenticate(String reason) async {
    // Reasons are application-owned, concise UI copy, never wallet data.
    if (reason.trim().isEmpty || reason.length > 160) {
      throw ArgumentError.value(reason.length, 'reason', 'Invalid reason');
    }
    final response = await _channel.invokeMethod<String>('authenticate', {
      'reason': reason,
    });
    return switch (response) {
      'authenticated' => DeviceAuthenticationResult.authenticated,
      'cancelled' => DeviceAuthenticationResult.cancelled,
      'unsecured' => DeviceAuthenticationResult.unsecured,
      _ => throw _invalidResponse(),
    };
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  @override
  Future<void> finishAuthenticationPresentation() =>
      _channel.invokeMethod<void>('finishAuthenticationPresentation');

  @override
  Future<void> setSensitive(bool sensitive) =>
      _channel.invokeMethod<void>('setSensitive', {'sensitive': sensitive});

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'backgrounded' && call.arguments == null) {
      _backgroundEvents.add(null);
      return null;
    }
    if (call.method != 'captureChanged' || call.arguments is! bool) {
      throw PlatformException(
        code: 'device_auth_invalid_event',
        message: 'Device security status is unavailable.',
      );
    }
    _updateCapture(call.arguments as bool);
    return null;
  }

  void _updateCapture(bool value) {
    if (_captured == value) return;
    _captured = value;
    _captureChanges.add(value);
  }

  PlatformException _invalidResponse() => PlatformException(
    code: 'device_auth_invalid_response',
    message: 'Device authentication is unavailable.',
  );
}
