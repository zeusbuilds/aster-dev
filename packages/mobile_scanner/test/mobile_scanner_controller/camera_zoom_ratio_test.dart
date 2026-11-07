import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ZoomPlatform platform;
  final controllers = <MobileScannerController>[];

  setUp(() {
    platform = _ZoomPlatform();
    MobileScannerPlatform.instance = platform;
    MobileScannerController.resetPlatformSessionOwner();
    controllers.clear();
  });

  tearDown(() async {
    for (final controller in controllers.reversed) {
      await controller.dispose();
    }
  });

  Future<MobileScannerController> start() async {
    final controller = MobileScannerController(autoStart: false)..attach();
    controllers.add(controller);
    await controller.start();
    return controller;
  }

  test('running controller returns confirmed platform readback', () async {
    final controller = await start();
    expect((await controller.getZoomState()).maxZoomRatio, 8);
    expect((await controller.setZoomRatio(2)).zoomRatio, 1.95);
    expect(platform.reads, 1);
    expect(platform.requests, [2.0]);
  });

  test('stopped controller cannot read or control a camera', () async {
    final controller = await start();
    await controller.stop();
    expect(controller.getZoomState, throwsStateError);
    expect(() => controller.setZoomRatio(2), throwsStateError);
    expect(platform.reads, 0);
    expect(platform.requests, isEmpty);
  });

  test('superseded controller cannot control another session', () async {
    final previous = await start();
    final current = await start();
    expect(previous.getZoomState, throwsStateError);
    expect(() => previous.setZoomRatio(3), throwsStateError);
    expect((await current.getZoomState()).zoomRatio, 1);
    expect(platform.requests, isEmpty);
  });

  test(
    'disposed controller rejects reads and writes before platform access',
    () async {
      final controller = await start();
      await controller.dispose();
      expect(controller.getZoomState, throwsA(isA<MobileScannerException>()));
      expect(
        () => controller.setZoomRatio(2),
        throwsA(isA<MobileScannerException>()),
      );
      expect(platform.reads, 0);
      expect(platform.requests, isEmpty);
    },
  );

  test('invalid ratio never reaches platform', () async {
    final controller = await start();
    for (final invalid in [double.nan, double.infinity, 0.0, -1.0]) {
      expect(() => controller.setZoomRatio(invalid), throwsArgumentError);
    }
    expect(platform.requests, isEmpty);
  });
}

class _ZoomPlatform extends MobileScannerPlatform {
  int reads = 0;
  final requests = <double>[];

  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(200, 200),
      numberOfCameras: 1,
    );
  }

  @override
  Future<CameraZoomState> getZoomState() async {
    reads++;
    return CameraZoomState(minZoomRatio: 1, maxZoomRatio: 8, zoomRatio: 1);
  }

  @override
  Future<CameraZoomState> setZoomRatio(double ratio) async {
    requests.add(ratio);
    return CameraZoomState(minZoomRatio: 1, maxZoomRatio: 8, zoomRatio: 1.95);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
