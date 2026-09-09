import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

/// Exports native screenshots to the host before Flutter uninstalls its test
/// app. Run only with the fixture-only visual catalog, never a funded wallet.
Future<void> main() async {
  final hashes = <String, String>{};
  await integrationDriver(
    driver: await FlutterDriver.connect(logCommunicationToFile: false),
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
      hashes[name] = sha256.convert(bytes).toString();
      final file = File('build/visual-restoration/ios/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return true;
    },
    responseDataCallback: (data) async {
      final screenshots = data?['screenshots'] as List<Object?>? ?? [];
      // Detect stale-window batches independently of widget-tree assertions.
      // Some legitimate loading scenes match, but these four cannot be equal.
      final sentinels = [
        '02-home/home',
        '02-home/home-hidden',
        '02-home/market-shell',
        '08-settings/settings-shell',
      ].map((name) => hashes[name]).toSet();
      if (screenshots.length != 94 ||
          hashes.length != 94 ||
          sentinels.contains(null) ||
          sentinels.length != 4) {
        throw StateError(
          'Incomplete or stale visual catalog; reject this batch',
        );
      }
      await writeResponseData(
        {
          'screenshotCount': screenshots.length,
          'uniqueImages': hashes.values.toSet().length,
          'evidence': 'iOS-engine Flutter layer; UI fixtures only',
        },
        testOutputFilename: 'visual_catalog_result',
        destinationDirectory: 'build/visual-restoration',
      );
    },
  );
}
