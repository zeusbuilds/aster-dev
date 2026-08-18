import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/prepare_android_release.dart';

void main() {
  const snapshot = AndroidReleaseDependencySnapshot(
    lockfile: 'locked graph',
    packageGraph: 'normalized graph',
  );

  test('accepts an unchanged graph with only production registrations', () {
    final report = verifyAndroidReleasePreparation(
      before: snapshot,
      after: snapshot,
      pluginMetadata: _metadata([
        _plugin('wallet_plugin', '/wallet', development: false),
        _plugin('integration_test', '/integration', development: true),
        _plugin('ffi_only', '/ffi', development: false),
      ]),
      generatedRegistrant: _registrant(['wallet_plugin']),
      readPluginPubspec: (path) => switch (path) {
        '/wallet' => _methodChannelPubspec,
        '/integration' => _methodChannelPubspec,
        '/ffi' => _ffiPubspec,
        _ => throw StateError('unexpected path'),
      },
    );

    expect(report.passed, isTrue);
    expect(report.productionPlugins, 1);
    expect(report.excludedDevelopmentPlugins, 1);
    expect(report.failures, isEmpty);
  });

  test('rejects development leakage and missing production wiring', () {
    final report = verifyAndroidReleasePreparation(
      before: snapshot,
      after: snapshot,
      pluginMetadata: _metadata([
        _plugin('wallet_plugin', '/wallet', development: false),
        _plugin('integration_test', '/integration', development: true),
      ]),
      generatedRegistrant: _registrant(['integration_test']),
      readPluginPubspec: (_) => _methodChannelPubspec,
    );

    expect(report.passed, isFalse);
    expect(
      report.failures,
      contains(
        'Development plugin integration_test leaked into the Release registrant.',
      ),
    );
    expect(
      report.failures,
      contains(
        'Production plugin wallet_plugin is missing from the Release registrant.',
      ),
    );
  });

  test('rejects lockfile and resolved package graph drift', () {
    final report = verifyAndroidReleasePreparation(
      before: snapshot,
      after: const AndroidReleaseDependencySnapshot(
        lockfile: 'different lock',
        packageGraph: 'different graph',
      ),
      pluginMetadata: _metadata(const []),
      generatedRegistrant: _registrant(const []),
      readPluginPubspec: (_) => throw StateError('not reached'),
    );

    expect(
      report.failures,
      contains('Flutter Release preparation changed pubspec.lock.'),
    );
    expect(
      report.failures,
      contains(
        'Flutter Release preparation changed the resolved package graph.',
      ),
    );
  });

  test('fails closed for malformed plugin metadata and pubspecs', () {
    final malformedMetadata = verifyAndroidReleasePreparation(
      before: snapshot,
      after: snapshot,
      pluginMetadata: '{',
      generatedRegistrant: _registrant(const []),
      readPluginPubspec: (_) => _methodChannelPubspec,
    );
    final malformedPubspec = verifyAndroidReleasePreparation(
      before: snapshot,
      after: snapshot,
      pluginMetadata: _metadata([
        _plugin('wallet_plugin', '/wallet', development: false),
      ]),
      generatedRegistrant: _registrant(const []),
      readPluginPubspec: (_) => '[invalid',
    );

    expect(
      malformedMetadata.failures,
      contains('.flutter-plugins-dependencies is not valid JSON.'),
    );
    expect(
      malformedPubspec.failures,
      contains('Could not parse Android plugin metadata for wallet_plugin.'),
    );
  });
}

Map<String, Object?> _plugin(
  String name,
  String path, {
  required bool development,
}) => {'name': name, 'path': path, 'dev_dependency': development};

String _metadata(List<Map<String, Object?>> plugins) => jsonEncode({
  'plugins': {'android': plugins},
});

String _registrant(List<String> plugins) =>
    '''
/** Generated file. Do not edit. */
${plugins.map((name) => 'Error registering plugin $name, PluginClass').join('\n')}
''';

const _methodChannelPubspec = '''
name: plugin
flutter:
  plugin:
    platforms:
      android:
        package: com.example.plugin
        pluginClass: PluginClass
''';

const _ffiPubspec = '''
name: ffi_plugin
flutter:
  plugin:
    platforms:
      android:
        ffiPlugin: true
''';
