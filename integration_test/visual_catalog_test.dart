import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/visual_catalog.dart';

/// iOS-engine captures of production widgets with isolated UI fixtures.
/// Never runs the native wallet or accesses an installed wallet's storage.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final screenshots = <Map<String, Object>>[];
  binding.reportData = {'screenshots': screenshots};
  registerVisualCatalog(
    capture: (tester, name) async {
      // Capture the mounted Flutter layer explicitly: iOS's multi-window
      // capture can return a retained launch view from another engine. This
      // includes the actual on-device Flutter raster, not OS/platform views.
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(visualCatalogBoundary),
      );
      final image = await boundary.toImage(
        pixelRatio: tester.view.devicePixelRatio,
      );
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        screenshots.add({
          'screenshotName': name,
          'bytes': bytes.buffer.asUint8List(),
        });
      } finally {
        image.dispose();
      }
    },
  );
}
