import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Exports native screenshots to the host before Flutter uninstalls its test
/// app. Run only with the fixture-only visual catalog, never a funded wallet.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    if (!RegExp(r'^[a-z0-9-]+/[a-z0-9-]+$').hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'Invalid catalog screenshot name',
      );
    }
    const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < pngSignature.length) return false;
    for (var index = 0; index < pngSignature.length; index++) {
      if (bytes[index] != pngSignature[index]) return false;
    }
    final file = File('build/visual-restoration/ios/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return true;
  },
  responseDataCallback: (data) async {
    final screenshots = data?['screenshots'] as List<Object?>? ?? [];
    await writeResponseData(
      {'screenshotCount': screenshots.length, 'evidence': 'UI fixtures only'},
      testOutputFilename: 'visual_catalog_result',
      destinationDirectory: 'build/visual-restoration',
    );
  },
);
