import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/resolve_android_artifact_toolchain.dart';

void main() {
  late Directory root;
  late Directory repository;
  late Directory gradleHome;
  late Directory androidSdk;
  late File flutterExtension;

  setUp(() {
    root = Directory.systemTemp.createTempSync('utexo_android_artifacts_');
    repository = Directory('${root.path}/repository')..createSync();
    gradleHome = Directory('${root.path}/gradle')..createSync();
    androidSdk = Directory('${root.path}/android-sdk')..createSync();
    _write(
      repository,
      'android/settings.gradle.kts',
      'id("com.android.application") version "9.1.0" apply false',
    );
    _write(
      repository,
      'android/app/build.gradle.kts',
      'android {\n'
          '  buildToolsVersion = "36.0.0"\n'
          '  ndkVersion = flutter.ndkVersion\n'
          '}',
    );
    flutterExtension = _write(
      root,
      'flutter/FlutterExtension.kt',
      'val ndkVersion: String = "28.2.13676358"',
    );
    _writeAgpMetadata(gradleHome);
    _write(
      gradleHome,
      'caches/modules-2/files-2.1/com.android.tools.build/'
          'aapt2-proto/9.1.0-14792394/hash/'
          'aapt2-proto-9.1.0-14792394.jar',
      '',
    );
    _write(
      gradleHome,
      'caches/modules-2/files-2.1/com.android.tools.build/'
          'bundletool/1.18.3/hash/bundletool-1.18.3.jar',
      '',
    );
    _write(
      gradleHome,
      'caches/modules-2/files-2.1/com.google.protobuf/'
          'protobuf-java/3.25.5/hash/protobuf-java-3.25.5.jar',
      '',
    );
    for (final path in [
      'build-tools/36.0.0/apksigner',
      'build-tools/36.0.0/aapt2',
      'build-tools/36.0.0/zipalign',
    ]) {
      _executable(androidSdk, path);
    }
    _executable(
      androidSdk,
      'ndk/28.2.13676358/toolchains/llvm/prebuilt/test/bin/llvm-readobj',
    );
    _symlink(
      androidSdk,
      'ndk/28.2.13676358/toolchains/llvm/prebuilt/test/bin/llvm-readelf',
      'llvm-readobj',
    );
    _writeVerificationMetadata(repository, _verifiedArtifacts(gradleHome));
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  AndroidArtifactToolchainResolution resolve() {
    return resolveAndroidArtifactToolchain(
      repositoryRoot: repository,
      gradleUserHome: gradleHome,
      androidSdkRoot: androidSdk,
      flutterExtension: flutterExtension,
    );
  }

  test('resolves only the exact owned AGP and Android toolchain', () {
    _write(
      gradleHome,
      'caches/modules-2/files-2.1/com.google.protobuf/'
          'protobuf-java/3.22.3/stale/protobuf-java-3.22.3.jar',
      '',
    );
    _executable(androidSdk, 'build-tools/99.0.0/apksigner');
    _executable(
      androidSdk,
      'ndk/99.0.0/toolchains/llvm/prebuilt/test/bin/llvm-readelf',
    );

    final result = resolve();

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    final toolchain = result.toolchain!;
    expect(toolchain.agpVersion, '9.1.0');
    expect(toolchain.aapt2ProtoVersion, '9.1.0-14792394');
    expect(toolchain.bundletoolVersion, '1.18.3');
    expect(toolchain.protobufVersion, '3.25.5');
    expect(toolchain.apksigner.path, contains('/build-tools/36.0.0/'));
    expect(toolchain.llvmReadelf.path, contains('/ndk/28.2.13676358/'));
  });

  test('rejects divergent repository declarations', () {
    _write(
      repository,
      'android/app/build.gradle.kts',
      'android { ndkVersion = "27.0.0" }',
    );

    final result = resolve();

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('Android build-tools version'),
        contains('must delegate NDK to Flutter'),
      ]),
    );
  });

  test('rejects malformed or ambiguous AGP metadata', () {
    _writeAgpMetadata(gradleHome, suffix: 'second');

    final ambiguous = resolve();

    expect(
      ambiguous.failures,
      contains(contains('module metadata file, found 2')),
    );

    final metadataRoot = Directory(
      '${gradleHome.path}/caches/modules-2/files-2.1/'
      'com.android.tools.build/gradle/9.1.0',
    );
    metadataRoot.deleteSync(recursive: true);
    _write(
      gradleHome,
      'caches/modules-2/files-2.1/com.android.tools.build/'
          'gradle/9.1.0/hash/gradle-9.1.0.module',
      '{malformed',
    );
    _writeVerificationMetadata(repository, _verifiedArtifacts(gradleHome));

    final malformed = resolve();

    expect(
      malformed.failures,
      contains(contains('metadata is malformed or unreadable')),
    );
  });

  test('rejects missing exact tools and cached libraries', () {
    File('${androidSdk.path}/build-tools/36.0.0/zipalign').deleteSync();
    File(
      '${gradleHome.path}/caches/modules-2/files-2.1/'
      'com.google.protobuf/protobuf-java/3.25.5/hash/'
      'protobuf-java-3.25.5.jar',
    ).deleteSync();
    File(
      '${gradleHome.path}/caches/modules-2/files-2.1/'
      'com.android.tools.build/aapt2-proto/9.1.0-14792394/hash/'
      'aapt2-proto-9.1.0-14792394.jar',
    ).deleteSync();

    final result = resolve();

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('Missing executable Android zipalign 36.0.0'),
        contains(
          'cached com.android.tools.build:aapt2-proto:'
          '9.1.0-14792394 jar',
        ),
        contains('cached com.google.protobuf:protobuf-java:3.25.5 jar'),
      ]),
    );
  });

  test('rejects an NDK tool symlink escaping the configured revision', () {
    final outside = _executable(root, 'outside/llvm-readobj');
    final readelf = Link(
      '${androidSdk.path}/ndk/28.2.13676358/toolchains/llvm/prebuilt/'
      'test/bin/llvm-readelf',
    );
    readelf.deleteSync();
    readelf.createSync(outside.path);

    final result = resolve();

    expect(
      result.failures,
      contains(
        contains(
          'Expected one executable Android NDK 28.2.13676358 '
          'llvm-readelf, found 0',
        ),
      ),
    );
  });

  test('rejects cache bytes that differ from committed checksums', () {
    File(
      '${gradleHome.path}/caches/modules-2/files-2.1/'
      'com.android.tools.build/bundletool/1.18.3/hash/'
      'bundletool-1.18.3.jar',
    ).writeAsStringSync('changed after Gradle verification');

    final result = resolve();

    expect(
      result.failures,
      contains(
        contains(
          'Cached artifact com.android.tools.build:bundletool:1.18.3:'
          'bundletool-1.18.3.jar does not match its committed SHA-256',
        ),
      ),
    );
  });

  test('rejects an oversized cache artifact before hashing its contents', () {
    final artifact = File(
      '${gradleHome.path}/caches/modules-2/files-2.1/'
      'com.android.tools.build/bundletool/1.18.3/hash/'
      'bundletool-1.18.3.jar',
    );
    final handle = artifact.openSync(mode: FileMode.write);
    handle.truncateSync(512 * 1024 * 1024 + 1);
    handle.closeSync();

    final result = resolve();

    expect(
      result.failures,
      contains(
        contains(
          'Cached artifact com.android.tools.build:bundletool:1.18.3:'
          'bundletool-1.18.3.jar exceeds the verification size limit',
        ),
      ),
    );
  });

  test('rejects unverified AGP module metadata before parsing it', () {
    final metadata = File(
      '${gradleHome.path}/caches/modules-2/files-2.1/'
      'com.android.tools.build/gradle/9.1.0/hash/gradle-9.1.0.module',
    );
    metadata.writeAsStringSync('${metadata.readAsStringSync()}\n');

    final result = resolve();

    expect(
      result.failures,
      contains(
        contains(
          'Cached artifact com.android.tools.build:gradle:9.1.0:'
          'gradle-9.1.0.module does not match its committed SHA-256',
        ),
      ),
    );
  });

  test('rejects missing and duplicate committed checksums', () {
    final artifacts = _verifiedArtifacts(gradleHome);
    _writeVerificationMetadata(
      repository,
      artifacts.where((artifact) => artifact.module != 'protobuf-java'),
    );

    final missing = resolve();

    expect(
      missing.failures,
      contains(
        contains(
          'Missing committed SHA-256 for com.google.protobuf:'
          'protobuf-java:3.25.5:protobuf-java-3.25.5.jar',
        ),
      ),
    );

    _writeVerificationMetadata(repository, artifacts, duplicateFirst: true);

    final duplicate = resolve();

    expect(
      duplicate.failures,
      contains(contains('Gradle verification duplicates')),
    );
  });
}

File _writeAgpMetadata(Directory gradleHome, {String suffix = 'hash'}) {
  return _write(
    gradleHome,
    'caches/modules-2/files-2.1/com.android.tools.build/'
    'gradle/9.1.0/$suffix/gradle-9.1.0.module',
    jsonEncode({
      'variants': [
        {
          'name': 'runtimeElements',
          'dependencies': [
            {
              'group': 'com.android.tools.build',
              'module': 'aapt2-proto',
              'version': {'requires': '9.1.0-14792394'},
            },
            {
              'group': 'com.android.tools.build',
              'module': 'bundletool',
              'version': {'requires': '1.18.3'},
            },
            {
              'group': 'com.google.protobuf',
              'module': 'protobuf-java',
              'version': {'requires': '3.25.5'},
            },
          ],
        },
      ],
    }),
  );
}

List<_VerifiedArtifact> _verifiedArtifacts(Directory gradleHome) => [
  _VerifiedArtifact(
    group: 'com.android.tools.build',
    module: 'gradle',
    version: '9.1.0',
    file: File(
      '${gradleHome.path}/caches/modules-2/files-2.1/'
      'com.android.tools.build/gradle/9.1.0/hash/gradle-9.1.0.module',
    ),
  ),
  _VerifiedArtifact(
    group: 'com.android.tools.build',
    module: 'aapt2-proto',
    version: '9.1.0-14792394',
    file: File(
      '${gradleHome.path}/caches/modules-2/files-2.1/'
      'com.android.tools.build/aapt2-proto/9.1.0-14792394/hash/'
      'aapt2-proto-9.1.0-14792394.jar',
    ),
  ),
  _VerifiedArtifact(
    group: 'com.android.tools.build',
    module: 'bundletool',
    version: '1.18.3',
    file: File(
      '${gradleHome.path}/caches/modules-2/files-2.1/'
      'com.android.tools.build/bundletool/1.18.3/hash/'
      'bundletool-1.18.3.jar',
    ),
  ),
  _VerifiedArtifact(
    group: 'com.google.protobuf',
    module: 'protobuf-java',
    version: '3.25.5',
    file: File(
      '${gradleHome.path}/caches/modules-2/files-2.1/'
      'com.google.protobuf/protobuf-java/3.25.5/hash/'
      'protobuf-java-3.25.5.jar',
    ),
  ),
];

void _writeVerificationMetadata(
  Directory repository,
  Iterable<_VerifiedArtifact> artifacts, {
  bool duplicateFirst = false,
}) {
  final entries = artifacts.toList();
  final components = entries.map((artifact) {
    final checksum = sha256.convert(artifact.file.readAsBytesSync());
    return '      <component group="${artifact.group}" '
        'name="${artifact.module}" version="${artifact.version}">\n'
        '        <artifact name="${_basename(artifact.file.path)}">\n'
        '          <sha256 value="$checksum"/>\n'
        '        </artifact>\n'
        '      </component>';
  }).toList();
  if (duplicateFirst && components.isNotEmpty) {
    components.add(components.first);
  }
  _write(
    repository,
    'android/gradle/verification-metadata.xml',
    '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<verification-metadata '
        'xmlns="https://schema.gradle.org/dependency-verification">\n'
        '  <configuration>\n'
        '    <verify-metadata>true</verify-metadata>\n'
        '    <verify-signatures>false</verify-signatures>\n'
        '  </configuration>\n'
        '  <components>\n'
        '${components.join('\n')}\n'
        '  </components>\n'
        '</verification-metadata>\n',
  );
}

String _basename(String path) => path.split(Platform.pathSeparator).last;

final class _VerifiedArtifact {
  const _VerifiedArtifact({
    required this.group,
    required this.module,
    required this.version,
    required this.file,
  });

  final String group;
  final String module;
  final String version;
  final File file;
}

File _write(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}

File _executable(Directory root, String relativePath) {
  final file = _write(root, relativePath, '#!/bin/sh\n');
  final result = Process.runSync('chmod', ['755', file.path]);
  if (result.exitCode != 0) {
    throw StateError('Could not make fixture executable: ${result.stderr}');
  }
  return file;
}

Link _symlink(Directory root, String relativePath, String target) {
  final link = Link('${root.path}/$relativePath');
  link.parent.createSync(recursive: true);
  link.createSync(target);
  return link;
}
