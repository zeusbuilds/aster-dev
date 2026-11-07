import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aster/shared/branding/aster_launch_logo.dart';
import 'package:aster/shared/branding/aster_logo_geometry.dart';
import 'package:aster/shared/theme/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Host-only export. Never runs on a device or replaces the production painter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'render Android launch resources through the unchanged opening painter',
    () async {
      const specPath = String.fromEnvironment('ASTER_ANDROID_LAUNCH_SPEC');
      expect(
        specPath,
        isNotEmpty,
        reason: 'Use tool/export_android_launch_logo.py.',
      );
      final specBytes = File(specPath).readAsBytesSync();
      final spec = jsonDecode(utf8.decode(specBytes)) as Map<String, dynamic>;
      expect(spec['schemaVersion'], 1);
      final sources = (spec['sourceSha256'] as Map<String, dynamic>)
          .cast<String, String>();
      for (final source in sources.entries) {
        expect(
          sha256.convert(File(source.key).readAsBytesSync()).toString(),
          source.value,
        );
      }
      final renderer = spec['rendererTool'] as String;
      expect(
        sha256.convert(File(renderer).readAsBytesSync()).toString(),
        spec['rendererToolSha256'],
      );
      final sourceSize = (spec['markSourceUnits'] as List<dynamic>).cast<num>();
      expect(sourceSize, [
        AsterLogoGeometry.size.width,
        AsterLogoGeometry.size.height,
      ]);
      final blue = AppTheme.light().extension<AsterColors>()!.brandArtMain;
      expect(
        blue.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase(),
        spec['blueArgb'],
      );
      expect(spec['sourcePose'], {
        'rotation': 0,
        'expansion': 0,
        'colorProgress': 0,
      });

      final width = (spec['visibleMarkWidthDp'] as num).toDouble();
      final height =
          width * AsterLogoGeometry.size.height / AsterLogoGeometry.size.width;
      final viewport = (spec['viewportDp'] as num).toDouble();
      final outputs = <Map<String, Object?>>[];
      for (final output
          in (spec['outputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final scale = (output['scale'] as num).toDouble();
        final size = (viewport * scale).round();
        expect(output['pixelSize'], [size, size]);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)
          ..scale(scale)
          ..translate(viewport / 2, viewport / 2);
        final path = AsterLogoGeometry.animatedPath(
          logoWidth: width,
          horizontalWidth: width,
          rotationProgress: 0,
          expansionProgress: 0,
        );
        AsterLaunchLogo.paint(
          canvas,
          path: path,
          logoBounds: ui.Rect.fromCenter(
            center: ui.Offset.zero,
            width: width,
            height: height,
          ),
          blueColor: blue,
          finalColor: blue,
          colorProgress: 0,
        );
        expect(canvas.getSaveCount(), 1);
        final picture = recorder.endRecording();
        final image = await picture.toImage(size, size);
        picture.dispose();
        try {
          expect(image.colorSpace, ui.ColorSpace.sRGB);
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
              .buffer
              .asUint8List();
          final destination = File(output['path'] as String);
          destination.parent.createSync(recursive: true);
          destination.writeAsBytesSync(png, flush: true);
          outputs.add({...output, 'pngSha256': sha256.convert(png).toString()});
        } finally {
          image.dispose();
        }
      }
      final receipt = <String, Object?>{
        for (final key in [
          'schemaVersion',
          'sourceSha256',
          'rendererTool',
          'rendererToolSha256',
          'viewportDp',
          'safeDiameterDp',
          'visibleMarkWidthDp',
          'markSourceUnits',
          'blueArgb',
          'sourcePose',
        ])
          key: spec[key],
        'renderSpecSha256': sha256.convert(specBytes).toString(),
        'colorSpace': 'sRGB',
        'outputs': outputs,
        'dartVersion': Platform.version,
        'renderer': 'Actual AsterLaunchLogo.paint at colorProgress zero; unchanged geometry, mask and effects',
      };
      final receiptFile = File(spec['outputReceipt'] as String);
      receiptFile.parent.createSync(recursive: true);
      receiptFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(receipt)}\n',
        flush: true,
      );
    },
  );
}
