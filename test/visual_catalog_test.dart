import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/visual_catalog.dart';

/// Host visual assertions; PNG export is opt-in and uses test-only fixtures.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerVisualCatalog(
    capture: (tester, name) async {
      if (!const bool.fromEnvironment('ASTER_CAPTURE_VISUALS')) return;
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(visualCatalogBoundary),
        );
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          const output = String.fromEnvironment(
            'ASTER_VISUAL_OUTPUT',
            defaultValue: 'build/visual-restoration/host',
          );
          final file = File('$output/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        } finally {
          image.dispose();
        }
      });
    },
  );
}
