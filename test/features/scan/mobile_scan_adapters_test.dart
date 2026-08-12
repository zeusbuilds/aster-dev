import 'package:aster/features/scan/data/services/mobile_scan_adapters.dart';
import 'package:aster/features/scan/data/services/scan_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scannerChannel = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, null);
  });

  test(
    'Android gallery recovery is consumed before opening a new picker',
    () async {
      final picker = _FakeImagePicker()
        ..lostData = LostDataResponse(
          file: XFile('/temporary/recovered.png'),
          type: RetrieveType.image,
        );
      final gallery = ImagePickerScanGallery(picker, isAndroid: true);

      expect(await gallery.selectImagePath(), '/temporary/recovered.png');
      expect(picker.retrieveCalls, 1);
      expect(picker.pickCalls, 0);
    },
  );

  test('gallery selection requests no unnecessary image metadata', () async {
    final picker = _FakeImagePicker()
      ..pickedImage = XFile('/temporary/selected.png');
    final gallery = ImagePickerScanGallery(picker, isAndroid: false);

    expect(await gallery.selectImagePath(), '/temporary/selected.png');
    expect(picker.pickCalls, 1);
    expect(picker.selectedSource, ImageSource.gallery);
    expect(picker.requestedFullMetadata, isFalse);
  });

  test(
    'gallery permission failures are typed and redact plugin messages',
    () async {
      final picker = _FakeImagePicker()
        ..pickError = PlatformException(
          code: 'photo_access_denied',
          message: 'sensitive platform detail',
        );
      final gallery = ImagePickerScanGallery(picker, isAndroid: false);

      await expectLater(
        gallery.selectImagePath(),
        throwsA(
          isA<ScanDriverException>()
              .having(
                (error) => error.kind,
                'kind',
                ScanDriverFailureKind.permissionDenied,
              )
              .having(
                (error) => error.toString(),
                'diagnostic string',
                isNot(contains('sensitive platform detail')),
              ),
        ),
      );
    },
  );

  test(
    'mobile scanner adapter reflects controller state and commands',
    () async {
      final controller = _FakeMobileScannerController()
        ..value = const MobileScannerState.uninitialized().copyWith(
          isInitialized: true,
          isRunning: true,
          torchState: TorchState.off,
        );
      final driver = MobileScannerCameraDriver(controller);

      expect(driver.state.isInitialized, isTrue);
      expect(driver.state.isRunning, isTrue);
      expect(driver.state.torchAvailable, isTrue);
      expect(driver.state.torchOn, isFalse);
      expect(driver.state.zoomScale, 1);

      await driver.setTorchEnabled(true);
      await driver.setZoomScale(0.5);

      expect(controller.toggleCalls, 1);
      expect(controller.zoomScales, [0.5]);
      expect(driver.state.torchOn, isTrue);
      expect(driver.state.zoomScale, 0.5);
      await driver.close();
      expect(controller.disposeCalls, 1);
    },
  );

  test('uninitialized controller cannot leak its sentinel zoom as real', () {
    final driver = MobileScannerCameraDriver(_FakeMobileScannerController());

    expect(driver.state.isInitialized, isFalse);
    expect(driver.state.zoomScale, 0);
  });

  test('mobile scanner permission errors map without raw details', () async {
    final controller = _FakeMobileScannerController()
      ..startError = const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
        errorDetails: MobileScannerErrorDetails(
          message: 'sensitive native permission detail',
        ),
      );
    final driver = MobileScannerCameraDriver(controller);

    await expectLater(
      driver.start(),
      throwsA(
        isA<ScanDriverException>()
            .having(
              (error) => error.kind,
              'kind',
              ScanDriverFailureKind.permissionDenied,
            )
            .having(
              (error) => error.toString(),
              'diagnostic string',
              isNot(contains('sensitive native permission detail')),
            ),
      ),
    );
    await driver.close();
  });

  test(
    'controller-state startup errors cannot be reported as success',
    () async {
      final controller = _FakeMobileScannerController()
        ..reportedStartError = const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied,
          errorDetails: MobileScannerErrorDetails(
            message: 'sensitive native permission detail',
          ),
        );
      final driver = MobileScannerCameraDriver(controller);

      await expectLater(
        driver.start(),
        throwsA(
          isA<ScanDriverException>()
              .having(
                (error) => error.kind,
                'kind',
                ScanDriverFailureKind.permissionDenied,
              )
              .having(
                (error) => error.toString(),
                'diagnostic string',
                isNot(contains('sensitive native permission detail')),
              ),
        ),
      );
      await driver.close();
    },
  );

  test(
    'controller-state stop failures cannot be reported as success',
    () async {
      final controller = _FakeMobileScannerController()
        ..value = const MobileScannerState.uninitialized().copyWith(
          isInitialized: true,
          isRunning: true,
          torchState: TorchState.off,
        )
        ..leaveRunningOnStop = true;
      final driver = MobileScannerCameraDriver(controller);

      await expectLater(
        driver.stop(),
        throwsA(
          isA<ScanDriverException>()
              .having(
                (error) => error.code,
                'code',
                'scan_camera_stop_incomplete',
              )
              .having(
                (error) => error.kind,
                'kind',
                ScanDriverFailureKind.invalidState,
              ),
        ),
      );
      await driver.close();
    },
  );

  test('unsupported image analysis retains a distinct failure kind', () async {
    final controller = _FakeMobileScannerController()
      ..analyzeError = UnsupportedError('private platform detail');
    final driver = MobileScannerCameraDriver(controller);

    await expectLater(
      driver.analyzeImage('/temporary/code.png'),
      throwsA(
        isA<ScanDriverException>()
            .having((error) => error.code, 'code', 'scan_gallery_unsupported')
            .having(
              (error) => error.kind,
              'kind',
              ScanDriverFailureKind.unsupported,
            ),
      ),
    );
    await driver.close();
  });
}

final class _FakeImagePicker extends ImagePicker {
  LostDataResponse lostData = LostDataResponse.empty();
  XFile? pickedImage;
  Object? pickError;
  ImageSource? selectedSource;
  bool? requestedFullMetadata;
  var retrieveCalls = 0;
  var pickCalls = 0;

  @override
  Future<LostDataResponse> retrieveLostData() async {
    retrieveCalls += 1;
    return lostData;
  }

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    pickCalls += 1;
    selectedSource = source;
    requestedFullMetadata = requestFullMetadata;
    final error = pickError;
    if (error != null) throw error;
    return pickedImage;
  }
}

final class _FakeMobileScannerController extends MobileScannerController {
  Object? startError;
  MobileScannerException? reportedStartError;
  bool leaveRunningOnStop = false;
  Object? analyzeError;
  final zoomScales = <double>[];
  var toggleCalls = 0;
  var disposeCalls = 0;

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {
    final error = startError;
    if (error != null) throw error;
    final reported = reportedStartError;
    if (reported != null) {
      value = value.copyWith(
        error: reported,
        isInitialized: true,
        isRunning: false,
      );
      return;
    }
    value = value.copyWith(
      isInitialized: true,
      isRunning: true,
      torchState: TorchState.off,
    );
  }

  @override
  Future<void> stop() async {
    if (leaveRunningOnStop) return;
    value = value.copyWith(isRunning: false, torchState: TorchState.off);
  }

  @override
  Future<void> toggleTorch() async {
    toggleCalls += 1;
    value = value.copyWith(
      torchState: value.torchState == TorchState.on
          ? TorchState.off
          : TorchState.on,
    );
  }

  @override
  Future<void> setZoomScale(double zoomScale) async {
    zoomScales.add(zoomScale);
    value = value.copyWith(zoomScale: zoomScale);
  }

  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const <BarcodeFormat>[],
  }) async {
    final error = analyzeError;
    if (error != null) throw error;
    return null;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await super.dispose();
  }
}
