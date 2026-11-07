import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _android = 'http://schemas.android.com/apk/res/android';
const _resources = 'android/app/src/main/res';

XmlElement _root(String path) =>
    XmlDocument.parse(File(path).readAsStringSync()).rootElement;

String? _attribute(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _android);

typedef _StyleVariant = ({int api, bool night, XmlElement style});

Iterable<_StyleVariant> _variants() sync* {
  // These native themes use only the API and night qualifiers. Night has
  // higher priority than API, so a stale night-v31 override must not silently
  // hide the API 33 icon preference on a newer device.
  final qualifier = RegExp(r'^values(-night)?(?:-v(\d+))?$');
  for (final directory in Directory(
    _resources,
  ).listSync().whereType<Directory>()) {
    final folder = directory.path.split(Platform.pathSeparator).last;
    final match = qualifier.firstMatch(folder);
    final file = File('${directory.path}/styles.xml');
    if (match == null || !file.existsSync()) continue;
    for (final style in _root(file.path).findElements('style')) {
      yield (
        api: int.parse(match.group(2) ?? '1'),
        night: match.group(1) != null,
        style: style,
      );
    }
  }
}

Map<String, String> _theme(
  String name,
  int api,
  bool night, [
  Set<String> parents = const {},
]) {
  expect(parents, isNot(contains(name)), reason: 'Theme inheritance cycle');
  final matching =
      _variants()
          .where(
            (variant) =>
                variant.style.getAttribute('name') == name &&
                variant.api <= api &&
                (!variant.night || night),
          )
          .toList()
        ..sort(
          (a, b) =>
              a.night != b.night ? (a.night ? 1 : -1) : a.api.compareTo(b.api),
        );
  expect(matching, isNotEmpty, reason: '$name API $api night=$night');
  final style = matching.last.style;
  final parent = style.getAttribute('parent')!;
  final inherited = parent.startsWith('@android:')
      ? <String, String>{}
      : _theme(parent, api, night, {...parents, name});
  if (parent.startsWith('@android:')) {
    expect(parent, '@android:style/Theme.Light.NoTitleBar');
  }
  return {
    ...inherited,
    for (final item in style.findElements('item'))
      item.getAttribute('name')!: item.innerText.trim(),
  };
}

void main() {
  test('native themes retain readable chrome across APIs and appearances', () {
    for (final api in [24, 26, 27, 28, 29, 30, 31, 32, 33, 37]) {
      for (final night in [false, true]) {
        final launch = _theme('LaunchTheme', api, night);
        final normal = _theme('NormalTheme', api, night);
        final reason = 'API $api night=$night';
        expect(
          launch['android:windowBackground'],
          '@drawable/launch_background',
          reason: reason,
        );
        expect(
          launch['android:statusBarColor'],
          '@android:color/white',
          reason: reason,
        );
        expect(
          normal['android:windowBackground'],
          '@color/aster_surface',
          reason: reason,
        );
        expect(
          normal['android:statusBarColor'],
          '@color/aster_surface',
          reason: reason,
        );
        expect(
          launch['android:navigationBarColor'],
          api >= 27 ? '@android:color/white' : '@android:color/black',
          reason: reason,
        );
        expect(
          normal['android:navigationBarColor'],
          api >= 27 ? '@color/aster_surface' : '@android:color/black',
          reason: reason,
        );
        for (final theme in [launch, normal]) {
          expect(theme['android:windowLightStatusBar'], 'true', reason: reason);
          expect(
            theme['android:windowLightNavigationBar'],
            api >= 27 ? 'true' : null,
            reason: reason,
          );
          expect(
            theme['android:enforceNavigationBarContrast'],
            api >= 29 ? 'false' : null,
            reason: reason,
          );
        }
        expect(
          launch['android:windowSplashScreenBackground'],
          api >= 31 ? '@android:color/white' : null,
          reason: reason,
        );
        expect(
          launch['android:windowSplashScreenAnimatedIcon'],
          api >= 31 ? '@drawable/aster_launch_opening' : null,
          reason: reason,
        );
        expect(
          launch['android:windowSplashScreenIconBackgroundColor'],
          api >= 31 ? '@android:color/transparent' : null,
          reason: reason,
        );
        expect(
          launch['android:windowSplashScreenBehavior'],
          api >= 33 ? 'icon_preferred' : null,
          reason: reason,
        );
      }
      for (final name in ['LaunchTheme', 'NormalTheme']) {
        expect(_theme(name, api, true), _theme(name, api, false));
      }
    }
  });

  test('new platform theme attributes are version qualified', () {
    const introduced = {
      'android:windowLightNavigationBar': 27,
      'android:enforceNavigationBarContrast': 29,
      'android:windowSplashScreenBackground': 31,
      'android:windowSplashScreenAnimatedIcon': 31,
      'android:windowSplashScreenIconBackgroundColor': 31,
      'android:windowSplashScreenBehavior': 33,
    };
    for (final variant in _variants()) {
      for (final item in variant.style.findElements('item')) {
        final minimum = introduced[item.getAttribute('name')];
        if (minimum != null) {
          expect(
            variant.api,
            greaterThanOrEqualTo(minimum),
            reason:
                '${variant.style.getAttribute('name')} ${item.getAttribute('name')}',
          );
        }
      }
    }
  });

  test(
    'legacy launch centres unscaled art with density-specific resources',
    () {
      final background = _root('$_resources/drawable/launch_background.xml');
      expect(background.name.local, 'layer-list');
      final layers = background.findElements('item').toList();
      expect(layers, hasLength(2));
      expect(_attribute(layers.first, 'drawable'), '@android:color/white');
      final bitmap = layers.last.findElements('bitmap').single;
      expect(_attribute(bitmap, 'src'), '@drawable/aster_launch_opening');
      expect(_attribute(bitmap, 'gravity'), 'center');
      // Sizing the outer layer to the mark would also scale its transparent
      // artboard and cause a native-to-Flutter size jump.
      for (final layer in layers) {
        expect(_attribute(layer, 'width'), isNull);
        expect(_attribute(layer, 'height'), isNull);
      }
      for (final density in const {
        'mdpi': 288,
        'hdpi': 432,
        'xhdpi': 576,
        'xxhdpi': 864,
        'xxxhdpi': 1152,
      }.entries) {
        final bytes = File(
          '$_resources/drawable-${density.key}/aster_launch_opening.png',
        ).readAsBytesSync();
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(bytes);
        expect(header.getUint32(16), density.value, reason: density.key);
        expect(header.getUint32(20), density.value, reason: density.key);
      }
      // A vector or nodpi override would bypass the painter-rendered density
      // resources that contain the exact union silhouette and outside shadows.
      for (final folder in ['drawable', 'drawable-nodpi', 'drawable-anydpi']) {
        for (final extension in ['xml', 'png']) {
          expect(
            File('$_resources/$folder/aster_launch_opening.$extension')
                .existsSync(),
            isFalse,
          );
        }
      }
    },
  );

  test('launch artwork stays separate from the user-owned launcher icons', () {
    final application = _root('android/app/src/main/AndroidManifest.xml')
        .findElements('application')
        .single;
    expect(_attribute(application, 'icon'), '@mipmap/ic_launcher');
    expect(_attribute(application, 'roundIcon'), '@mipmap/ic_launcher_round');
    final activity = application.findElements('activity').single;
    expect(_attribute(activity, 'name'), 'com.example.asterdev.MainActivity');
    expect(_attribute(activity, 'theme'), '@style/LaunchTheme');
    final normalTheme = activity
        .findElements('meta-data')
        .singleWhere(
          (element) =>
              _attribute(element, 'name') ==
              'io.flutter.embedding.android.NormalTheme',
        );
    expect(_attribute(normalTheme, 'resource'), '@style/NormalTheme');
    expect(
      activity
          .findElements('meta-data')
          .any(
            (element) =>
                _attribute(element, 'name') ==
                'io.flutter.embedding.android.SplashScreenDrawable',
          ),
      isFalse,
      reason: 'The legacy embedding splash would add another splash stage',
    );
    for (final name in ['ic_launcher', 'ic_launcher_round']) {
      final icon = _root('$_resources/mipmap-anydpi-v26/$name.xml');
      expect(
        _attribute(icon.findElements('foreground').single, 'drawable'),
        '@mipmap/ic_launcher_foreground',
      );
      expect(
        _attribute(icon.findElements('background').single, 'drawable'),
        '@color/ic_launcher_background',
      );
    }
  });
}
