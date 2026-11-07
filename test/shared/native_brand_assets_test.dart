import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _android = 'http://schemas.android.com/apk/res/android';
const _svg = 'http://www.w3.org/2000/svg';
const _androidResources = 'android/app/src/main/res';

XmlElement _root(String path) =>
    XmlDocument.parse(File(path).readAsStringSync()).rootElement;

String? _androidValue(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _android);

List<List<double>> _outlineVertices(String path) {
  final tokens = RegExp(r'[MLHVZ]|-?(?:\d*\.)?\d+')
      .allMatches(path)
      .map((match) => match.group(0)!)
      .toList();
  var x = 0.0;
  var y = 0.0;
  final points = <List<double>>[];
  var index = 0;
  while (index < tokens.length) {
    switch (tokens[index++]) {
      case 'M' || 'L':
        x = double.parse(tokens[index++]);
        y = double.parse(tokens[index++]);
      case 'H':
        x = double.parse(tokens[index++]);
      case 'V':
        y = double.parse(tokens[index++]);
      case 'Z':
        continue;
      default:
        throw FormatException('Unsupported brand outline command');
    }
    points.add([x, y]);
  }
  if (points.last[0] == points.first[0] && points.last[1] == points.first[1]) {
    points.removeLast();
  }
  return points;
}

void main() {
  late XmlElement canonical;
  late String canonicalPath;
  late double width;
  late double height;

  setUp(() {
    canonical = _root('assets/brand/aster-mark.svg');
    final viewBox = canonical.getAttribute('viewBox')!.split(' ');
    width = double.parse(viewBox[2]);
    height = double.parse(viewBox[3]);
    final paths = canonical.findElements('path', namespaceUri: _svg).toList();
    expect(paths, hasLength(1));
    expect(paths.single.getAttribute('fill'), 'white');
    canonicalPath = paths.single.getAttribute('d')!;
  });

  test(
    'the user-owned native icon references the canonical mark proportions',
    () {
      final composer = jsonDecode(
        File('ios/Runner/AsterIcon.icon/icon.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final group =
          (composer['groups'] as List<dynamic>).single as Map<String, dynamic>;
      final layer =
          (group['layers'] as List<dynamic>).single as Map<String, dynamic>;
      final position = layer['position'] as Map<String, dynamic>;
      final imageName = layer['image-name']! as String;
      expect(imageName, endsWith('.svg'));
      expect(imageName, isNot(contains('/')));
      final icon = _root('ios/Runner/AsterIcon.icon/Assets/$imageName');
      expect(icon.getAttribute('viewBox'), canonical.getAttribute('viewBox'));
      // Figma removed a redundant collinear H151.546 vertex in the user's
      // coloured export. It changes neither the silhouette nor proportions.
      String normalize(String path) => path
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll(RegExp(r'H[-\d.]+(?=H)'), '');
      expect(
        normalize(
          icon
              .findElements('path', namespaceUri: _svg)
              .single
              .getAttribute('d')!,
        ),
        normalize(canonicalPath),
      );
      final intrinsicWidth = double.parse(icon.getAttribute('width')!);
      final intrinsicHeight = double.parse(icon.getAttribute('height')!);
      expect(intrinsicWidth, greaterThan(0));
      expect(intrinsicHeight / intrinsicWidth, closeTo(height / width, 1e-12));
      expect(position['scale']! as num, greaterThan(0));
    },
  );

  test('Android exported launcher PNGs cover each supplied density', () {
    for (final entry in const {
      'ldpi': 36,
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      for (final name in ['ic_launcher', 'ic_launcher_round']) {
        final bytes = File('$_androidResources/mipmap-${entry.key}/$name.png')
            .readAsBytesSync();
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(bytes);
        expect(header.getUint32(16), entry.value);
        expect(header.getUint32(20), entry.value);
      }
    }
    // This higher-priority XML would otherwise hide the new density PNGs on
    // API 24–25, even though their resource names match the manifest.
    expect(
      File('$_androidResources/mipmap-anydpi-v24/ic_launcher.xml').existsSync(),
      isFalse,
    );
  });

  test('Android launcher resolves the exported regular and round icons', () {
    final application = _root('android/app/src/main/AndroidManifest.xml')
        .findElements('application')
        .single;
    expect(_androidValue(application, 'icon'), '@mipmap/ic_launcher');
    expect(
      _androidValue(application, 'roundIcon'),
      '@mipmap/ic_launcher_round',
    );
    for (final name in ['ic_launcher', 'ic_launcher_round']) {
      final adaptive = _root('$_androidResources/mipmap-anydpi-v26/$name.xml');
      expect(adaptive.name.local, 'adaptive-icon');
      expect(
        _androidValue(adaptive.findElements('foreground').single, 'drawable'),
        '@mipmap/ic_launcher_foreground',
      );
      expect(
        _androidValue(adaptive.findElements('background').single, 'drawable'),
        '@color/ic_launcher_background',
      );
    }
    final color = _root('$_androidResources/values/ic_launcher_background.xml')
        .findElements('color')
        .single;
    expect(color.getAttribute('name'), 'ic_launcher_background');
    expect(color.innerText.toLowerCase(), '#ffffff');
    for (final entry in const {
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    }.entries) {
      final header = ByteData.sublistView(
        File(
          '$_androidResources/mipmap-${entry.key}/ic_launcher_foreground.png',
        ).readAsBytesSync(),
      );
      expect(header.getUint32(16), entry.value);
      expect(header.getUint32(20), entry.value);
    }
  });

  test('all native privacy covers use one opaque white and gradient blue appearance', () {
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/com/example/asterdev/'
      'DeviceAuthenticationBridge.kt',
    ).readAsStringSync();
    for (final source in [swift, kotlin]) {
      expect(source, isNot(contains('"setLaunching"')));
      expect(source, isNot(contains('private var launching')));
      expect(source, isNot(contains('setLaunching(')));
      expect(source, contains('539.285'));
      expect(source, contains('28.6915'));
      expect(source, contains('352.343'));
      expect(source, contains('157.807'));
      expect(source, isNot(contains('aster-launch-background')));
      expect(source, isNot(contains('aster-privacy-mark')));
      expect(source, isNot(contains('R.drawable.aster_privacy_background')));
    }
    expect(swift, contains('isOpaque = true'));
    expect(swift, contains('backgroundColor = .white'));
    expect(
      swift,
      contains('preferredStatusBarStyle: UIStatusBarStyle { .darkContent }'),
    );
    expect(swift, isNot(contains('private let backdrop')));
    expect(kotlin, isNot(contains('private var backdrop')));
    expect(kotlin, isNot(contains('coldMark')));
    expect(kotlin, isNot(contains('warmMark')));
    expect(swift, contains('sigma: 15'));
    expect(swift, contains('sigma: 3'));
    expect(swift, contains('private static let logoWidth: CGFloat = 160'));
    expect(kotlin, contains('canvas.drawColor(Color.WHITE)'));
    expect(kotlin, contains('hardAlpha.extractAlpha(alphaPaint, position)'));
    expect(kotlin, contains('(sigma * artworkScale - 0.5f) / 0.57735f'));
    expect(kotlin, contains('PorterDuff.Mode.DST_OUT'));
    expect(swift, contains('"CISourceOutCompositing"'));
    expect(swift, contains('w: 127'));
    expect(kotlin, contains('Color.alpha(pixels[index]) * 127'));
    expect(swift, contains('locations: [0.346154, 1]'));
    expect(kotlin, contains('floatArrayOf(0.346154f, 1f)'));

    final swiftOutline = swift.split('private static func logoPath()').last;
    final swiftPoints = RegExp(r'CGPoint\(x: ([\d.]+), y: ([\d.]+)\)')
        .allMatches(swiftOutline)
        .map(
          (match) => [
            double.parse(match.group(1)!),
            double.parse(match.group(2)!),
          ],
        )
        .toList();
    final kotlinOutline = RegExp(r'val vertices = floatArrayOf\(([\s\S]*?)\)')
        .firstMatch(kotlin)!
        .group(1)!;
    final kotlinNumbers = RegExp(r'([\d.]+)f')
        .allMatches(kotlinOutline)
        .map((match) => double.parse(match.group(1)!))
        .toList();
    final kotlinPoints = [
      for (var index = 0; index < kotlinNumbers.length; index += 2)
        [kotlinNumbers[index], kotlinNumbers[index + 1]],
    ];
    expect(swiftPoints, _outlineVertices(canonicalPath));
    expect(kotlinPoints, _outlineVertices(canonicalPath));
    final nativeLaunch = _root('ios/Runner/Launch Screen.storyboard');
    expect(
      nativeLaunch.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'imageView')
          .map((element) => element.getAttribute('image')),
      isNot(contains('aster-privacy-mark')),
    );
    // Native launch theme resource selection and separation from launcher
    // artwork are covered across APIs/appearances in android_native_launch_test.
  });
}
