import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _android = 'http://schemas.android.com/apk/res/android';
const _svg = 'http://www.w3.org/2000/svg';
const _iosAssets = 'ios/Runner/Assets.xcassets';
const _androidResources = 'android/app/src/main/res';

XmlElement _root(String path) =>
    XmlDocument.parse(File(path).readAsStringSync()).rootElement;

String? _androidValue(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _android);

double _number(String value) => double.parse(value.replaceAll('dp', ''));

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
    'native privacy and icon assets retain the canonical mark proportions',
    () {
      final privacy = _root(
        '$_iosAssets/aster-privacy-mark.imageset/aster-privacy-mark.svg',
      );
      expect(
        privacy.getAttribute('viewBox'),
        canonical.getAttribute('viewBox'),
      );
      expect(
        privacy
            .findElements('path', namespaceUri: _svg)
            .single
            .getAttribute('d'),
        canonicalPath,
      );
      final metadata = jsonDecode(
        File('$_iosAssets/aster-privacy-mark.imageset/Contents.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final image =
          (metadata['images'] as List<dynamic>).first as Map<String, dynamic>;
      expect(image['filename'], 'aster-privacy-mark.svg');

      final icon = _root('ios/Runner/AsterIcon.icon/Assets/aster_mark.svg');
      expect(icon.getAttribute('viewBox'), canonical.getAttribute('viewBox'));
      expect(
        icon.findElements('path', namespaceUri: _svg).single.getAttribute('d'),
        canonicalPath,
      );
      final intrinsicWidth = double.parse(icon.getAttribute('width')!);
      final intrinsicHeight = double.parse(icon.getAttribute('height')!);
      expect(intrinsicWidth, 360);
      expect(intrinsicHeight / intrinsicWidth, closeTo(height / width, 1e-12));
      final composer = jsonDecode(
        File('ios/Runner/AsterIcon.icon/icon.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final group =
          (composer['groups'] as List<dynamic>).single as Map<String, dynamic>;
      final layer =
          (group['layers'] as List<dynamic>).single as Map<String, dynamic>;
      final position = layer['position'] as Map<String, dynamic>;
      expect(layer['image-name'], 'aster_mark.svg');
      expect(position['scale'], 2);
    },
  );

  test(
    'Android privacy vector uses canonical unmodified path and aspect ratio',
    () {
      final mark = _root('$_androidResources/drawable/aster_brand_mark.xml');
      expect(_number(_androidValue(mark, 'viewportWidth')!), width);
      expect(_number(_androidValue(mark, 'viewportHeight')!), height);
      expect(
        _number(_androidValue(mark, 'height')!) /
            _number(_androidValue(mark, 'width')!),
        closeTo(height / width, 1e-12),
      );
      final path = mark.findElements('path').single;
      expect(_androidValue(path, 'pathData'), canonicalPath);
      expect(_androidValue(path, 'fillColor'), '#FFFFFFFF');
    },
  );

  test(
    'Android adaptive icon remains centered inside its existing footprint',
    () {
      final foreground = _root(
        '$_androidResources/drawable/aster_launcher_foreground.xml',
      );
      final group = foreground.findElements('group').single;
      final scaleX = _number(_androidValue(group, 'scaleX')!);
      final scaleY = _number(_androidValue(group, 'scaleY')!);
      final dx = _number(_androidValue(group, 'translateX')!);
      final dy = _number(_androidValue(group, 'translateY')!);
      expect(scaleX, scaleY);
      expect(width * scaleX, closeTo(63.45, 1e-9));
      expect(dx + width * scaleX / 2, closeTo(54, 1e-9));
      expect(dy + height * scaleY / 2, closeTo(54, 1e-9));
      expect(
        _androidValue(group.findElements('path').single, 'pathData'),
        canonicalPath,
      );
      final adaptive = _root(
        '$_androidResources/mipmap-anydpi-v26/ic_launcher.xml',
      );
      expect(
        _androidValue(adaptive.findElements('foreground').single, 'drawable'),
        '@drawable/aster_launcher_foreground',
      );
    },
  );

  test(
    'Android privacy and legacy icon preserve aspect ratio in their bounds',
    () {
      for (final path in [
        'drawable/aster_privacy_background.xml',
        'mipmap-anydpi-v24/ic_launcher.xml',
      ]) {
        final root = _root('$_androidResources/$path');
        final mark = root
            .findElements('item')
            .singleWhere(
              (item) =>
                  _androidValue(item, 'drawable') ==
                  '@drawable/aster_brand_mark',
            );
        expect(_androidValue(mark, 'gravity'), 'center');
        expect(
          _number(_androidValue(mark, 'height')!) /
              _number(_androidValue(mark, 'width')!),
          closeTo(height / width, 1e-12),
        );
      }
    },
  );

  test(
    'native privacy covers use dedicated brand assets rather than launch art',
    () {
      expect(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
        contains('UIImage(named: "aster-privacy-mark")'),
      );
      expect(
        File(
          'android/app/src/main/kotlin/com/example/asterdev/'
          'DeviceAuthenticationBridge.kt',
        ).readAsStringSync(),
        contains('R.drawable.aster_privacy_background'),
      );
      final nativeLaunch = _root('ios/Runner/Launch Screen.storyboard');
      expect(
        nativeLaunch.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'imageView')
            .map((element) => element.getAttribute('image')),
        isNot(contains('aster-privacy-mark')),
      );
      for (final folder in ['values-v31', 'values-night-v31']) {
        final styles = _root('$_androidResources/$folder/styles.xml');
        final splash = styles.descendants.whereType<XmlElement>().singleWhere(
          (element) =>
              element.name.local == 'item' &&
              element.getAttribute('name') ==
                  'android:windowSplashScreenAnimatedIcon',
        );
        expect(splash.innerText, isNot('@drawable/aster_launcher_foreground'));
      }
    },
  );
}
