import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aster/shared/branding/aster_launch_logo.dart';
import 'package:aster/shared/branding/aster_logo_geometry.dart';
import 'package:aster/shared/theme/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Invoked only by `python3 tool/export_aster_launch_logo.py --render-shadow`.
/// The production painter and animation are never replaced or modified.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'render native-compatible shadows through the unchanged Flutter painter',
    () async {
      const specPath = String.fromEnvironment('ASTER_LAUNCH_RENDER_SPEC');
      expect(specPath, isNotEmpty, reason: 'Use the Python export command.');
      final specBytes = File(specPath).readAsBytesSync();
      final spec = jsonDecode(utf8.decode(specBytes)) as Map<String, dynamic>;
      expect(spec['schemaVersion'], 1);
      final sourceHashes = (spec['sourceSha256'] as Map<String, dynamic>)
          .cast<String, String>();
      for (final entry in sourceHashes.entries) {
        expect(
          sha256.convert(File(entry.key).readAsBytesSync()).toString(),
          entry.value,
          reason:
              'Dart source changed after the render specification was made.',
        );
      }

      final viewport = (spec['viewportSourceUnits'] as List<dynamic>)
          .cast<num>();
      final center = (spec['markCenterSourceUnits'] as List<dynamic>)
          .cast<num>();
      final markSize = (spec['markSourceUnits'] as List<dynamic>).cast<num>();
      final rasterScale = (spec['rasterScale'] as num).toDouble();
      expect(markSize[0], AsterLogoGeometry.size.width);
      expect(markSize[1], AsterLogoGeometry.size.height);
      final blue = AppTheme.light().extension<AsterColors>()!.brandArtMain;
      expect(
        blue.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase(),
        spec['blueArgb'],
      );

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..scale(rasterScale)
        ..translate(center[0].toDouble(), center[1].toDouble());
      final shadowOnly = _ShadowOnlyCanvas(canvas);
      final path = AsterLogoGeometry.animatedPath(
        logoWidth: AsterLogoGeometry.size.width,
        horizontalWidth: AsterLogoGeometry.size.width,
        rotationProgress: 0,
        expansionProgress: 0,
      );
      AsterLaunchLogo.paint(
        shadowOnly,
        path: path,
        logoBounds: ui.Rect.fromCenter(
          center: ui.Offset.zero,
          width: AsterLogoGeometry.size.width,
          height: AsterLogoGeometry.size.height,
        ),
        blueColor: blue,
        finalColor: blue,
        colorProgress: 0,
      );
      expect(shadowOnly.suppressedForegroundPaths, 1);
      expect(shadowOnly.forwardedShadowPaths, 4);
      expect(canvas.getSaveCount(), shadowOnly.initialSaveCount);

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        (viewport[0] * rasterScale).ceil(),
        (viewport[1] * rasterScale).ceil(),
      );
      picture.dispose();
      try {
        expect(image.colorSpace, ui.ColorSpace.sRGB);
        final raw = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        var nonTransparentPixels = 0;
        var coloredPixels = 0;
        var maximumAlpha = 0;
        for (var i = 0; i < raw.length; i += 4) {
          if (raw[i] != 0 || raw[i + 1] != 0 || raw[i + 2] != 0) {
            coloredPixels += 1;
          }
          final alpha = raw[i + 3];
          if (alpha > 0) nonTransparentPixels += 1;
          if (alpha > maximumAlpha) maximumAlpha = alpha;
        }
        expect(
          coloredPixels,
          0,
          reason: 'The PNG must contain no blue logo fill.',
        );
        expect(nonTransparentPixels, greaterThan(0));
        expect(maximumAlpha, inInclusiveRange(1, 254));
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        final pngFile = File(spec['outputPng'] as String);
        pngFile.parent.createSync(recursive: true);
        pngFile.writeAsBytesSync(png, flush: true);
        final metadata = <String, Object?>{
          'schemaVersion': 1,
          'renderer':
              'Actual AsterLaunchLogo.paint with shadow-only Canvas forwarding',
          'rendererTool': 'tool/render_aster_launch_shadow_test.dart',
          'rendererToolSha256': sha256
              .convert(
                File('tool/render_aster_launch_shadow_test.dart')
                    .readAsBytesSync(),
              )
              .toString(),
          'sourceSha256': sourceHashes,
          'renderSpecSha256': sha256.convert(specBytes).toString(),
          'pngSha256': sha256.convert(png).toString(),
          'viewportSourceUnits': viewport,
          'rasterScale': rasterScale,
          'pixelSize': [image.width, image.height],
          'colorSpace': image.colorSpace.name,
          'nonTransparentPixels': nonTransparentPixels,
          'coloredPixels': coloredPixels,
          'maximumAlpha': maximumAlpha,
          'forwardedShadowPaths': shadowOnly.forwardedShadowPaths,
          'suppressedForegroundPaths': shadowOnly.suppressedForegroundPaths,
          'dartVersion': Platform.version,
        };
        File(spec['outputMetadata'] as String).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(metadata)}\n',
          flush: true,
        );
        // ignore: avoid_print
        print(
          'Rendered ${image.width}x${image.height} black-alpha shadow PNG; '
          '$nonTransparentPixels nontransparent pixels, no colored fill.',
        );
      } finally {
        image.dispose();
      }
    },
  );
}

/// Forwards every Canvas operation used by the production compositor. Only its
/// final drawPath, after all save/layer scopes have closed, is suppressed. New
/// painter operations fail loudly rather than being silently omitted.
final class _ShadowOnlyCanvas implements ui.Canvas {
  _ShadowOnlyCanvas(this.delegate) : initialSaveCount = delegate.getSaveCount();

  final ui.Canvas delegate;
  final int initialSaveCount;
  int forwardedShadowPaths = 0;
  int suppressedForegroundPaths = 0;

  @override
  void save() => delegate.save();

  @override
  void restore() => delegate.restore();

  @override
  int getSaveCount() => delegate.getSaveCount();

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) =>
      delegate.saveLayer(bounds, paint);

  @override
  void clipRect(
    ui.Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => delegate.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);

  @override
  void translate(double dx, double dy) => delegate.translate(dx, dy);

  @override
  void drawPath(ui.Path path, ui.Paint paint) {
    if (delegate.getSaveCount() == initialSaveCount) {
      suppressedForegroundPaths += 1;
      return;
    }
    forwardedShadowPaths += 1;
    delegate.drawPath(path, paint);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Review native-shadow export support for Canvas.${invocation.memberName}',
  );
}
