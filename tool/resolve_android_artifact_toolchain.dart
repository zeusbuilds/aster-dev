import 'dart:convert';
import 'dart:io';

/// Exact Android tools and AGP libraries used to inspect release artifacts.
final class AndroidArtifactToolchain {
  const AndroidArtifactToolchain({
    required this.agpVersion,
    required this.buildToolsVersion,
    required this.ndkVersion,
    required this.aapt2ProtoVersion,
    required this.bundletoolVersion,
    required this.protobufVersion,
    required this.aapt2ProtoJar,
    required this.bundletoolJar,
    required this.protobufJar,
    required this.apksigner,
    required this.aapt2,
    required this.zipalign,
    required this.llvmReadelf,
  });

  final String agpVersion;
  final String buildToolsVersion;
  final String ndkVersion;
  final String aapt2ProtoVersion;
  final String bundletoolVersion;
  final String protobufVersion;
  final File aapt2ProtoJar;
  final File bundletoolJar;
  final File protobufJar;
  final File apksigner;
  final File aapt2;
  final File zipalign;
  final File llvmReadelf;
}

/// Result of resolving one release-verification toolchain.
final class AndroidArtifactToolchainResolution {
  const AndroidArtifactToolchainResolution({
    required this.toolchain,
    required this.failures,
  });

  final AndroidArtifactToolchain? toolchain;
  final List<String> failures;

  bool get passed => toolchain != null && failures.isEmpty;
}

/// Resolves artifact tools from exact repository and Gradle declarations.
///
/// Installed-version ordering is deliberately irrelevant. Missing, duplicate,
/// malformed, or divergent metadata fails closed instead of selecting another
/// compatible-looking cache entry.
AndroidArtifactToolchainResolution resolveAndroidArtifactToolchain({
  required Directory repositoryRoot,
  required Directory gradleUserHome,
  required Directory androidSdkRoot,
  required File flutterExtension,
}) {
  final failures = <String>[];
  final root = repositoryRoot.absolute.path;
  final settings = _readRequired(
    File('$root/android/settings.gradle.kts'),
    'android/settings.gradle.kts',
    failures,
  );
  final appBuild = _readRequired(
    File('$root/android/app/build.gradle.kts'),
    'android/app/build.gradle.kts',
    failures,
  );
  final extension = _readRequired(
    flutterExtension,
    'Flutter Gradle extension',
    failures,
  );

  final agpVersion = _singleMatch(
    settings,
    RegExp(r'id\("com\.android\.application"\)\s+version\s+"([^"]+)"'),
    'Android Gradle Plugin version',
    failures,
  );
  final buildToolsVersion = _singleMatch(
    appBuild,
    RegExp(r'\bbuildToolsVersion\s*=\s*"([^"]+)"'),
    'Android build-tools version',
    failures,
  );
  final ndkVersion = _singleMatch(
    extension,
    RegExp(r'val\s+ndkVersion\s*:\s*String\s*=\s*"([^"]+)"'),
    'Flutter NDK version',
    failures,
  );
  if (appBuild != null &&
      !RegExp(r'\bndkVersion\s*=\s*flutter\.ndkVersion\b').hasMatch(appBuild)) {
    failures.add('android/app/build.gradle.kts must delegate NDK to Flutter.');
  }

  String? bundletoolVersion;
  String? aapt2ProtoVersion;
  String? protobufVersion;
  if (agpVersion != null) {
    final metadata = _agpModuleMetadata(gradleUserHome, agpVersion, failures);
    if (metadata != null) {
      aapt2ProtoVersion = _dependencyVersion(
        metadata,
        group: 'com.android.tools.build',
        module: 'aapt2-proto',
        failures: failures,
      );
      bundletoolVersion = _dependencyVersion(
        metadata,
        group: 'com.android.tools.build',
        module: 'bundletool',
        failures: failures,
      );
      protobufVersion = _dependencyVersion(
        metadata,
        group: 'com.google.protobuf',
        module: 'protobuf-java',
        failures: failures,
      );
    }
  }

  File? aapt2ProtoJar;
  if (aapt2ProtoVersion != null) {
    aapt2ProtoJar = _singleCachedJar(
      gradleUserHome,
      group: 'com.android.tools.build',
      module: 'aapt2-proto',
      version: aapt2ProtoVersion,
      failures: failures,
    );
  }
  File? bundletoolJar;
  if (bundletoolVersion != null) {
    bundletoolJar = _singleCachedJar(
      gradleUserHome,
      group: 'com.android.tools.build',
      module: 'bundletool',
      version: bundletoolVersion,
      failures: failures,
    );
  }
  File? protobufJar;
  if (protobufVersion != null) {
    protobufJar = _singleCachedJar(
      gradleUserHome,
      group: 'com.google.protobuf',
      module: 'protobuf-java',
      version: protobufVersion,
      failures: failures,
    );
  }

  File? apksigner;
  File? aapt2;
  File? zipalign;
  if (buildToolsVersion != null) {
    final buildTools = Directory(
      '${androidSdkRoot.absolute.path}/build-tools/$buildToolsVersion',
    );
    apksigner = _requiredExecutable(
      File('${buildTools.path}/apksigner'),
      'Android apksigner $buildToolsVersion',
      failures,
    );
    aapt2 = _requiredExecutable(
      File('${buildTools.path}/aapt2'),
      'Android aapt2 $buildToolsVersion',
      failures,
    );
    zipalign = _requiredExecutable(
      File('${buildTools.path}/zipalign'),
      'Android zipalign $buildToolsVersion',
      failures,
    );
  }

  File? llvmReadelf;
  if (ndkVersion != null) {
    final prebuiltRoot = Directory(
      '${androidSdkRoot.absolute.path}/ndk/$ndkVersion/toolchains/llvm/prebuilt',
    );
    llvmReadelf = _singleExecutableNamed(
      prebuiltRoot,
      'llvm-readelf',
      'Android NDK $ndkVersion llvm-readelf',
      failures,
    );
  }
  failures.sort();
  if (failures.isNotEmpty ||
      agpVersion == null ||
      buildToolsVersion == null ||
      ndkVersion == null ||
      aapt2ProtoVersion == null ||
      bundletoolVersion == null ||
      protobufVersion == null ||
      aapt2ProtoJar == null ||
      bundletoolJar == null ||
      protobufJar == null ||
      apksigner == null ||
      aapt2 == null ||
      zipalign == null ||
      llvmReadelf == null) {
    return AndroidArtifactToolchainResolution(
      toolchain: null,
      failures: List.unmodifiable(failures),
    );
  }

  return AndroidArtifactToolchainResolution(
    toolchain: AndroidArtifactToolchain(
      agpVersion: agpVersion,
      buildToolsVersion: buildToolsVersion,
      ndkVersion: ndkVersion,
      aapt2ProtoVersion: aapt2ProtoVersion,
      bundletoolVersion: bundletoolVersion,
      protobufVersion: protobufVersion,
      aapt2ProtoJar: aapt2ProtoJar,
      bundletoolJar: bundletoolJar,
      protobufJar: protobufJar,
      apksigner: apksigner,
      aapt2: aapt2,
      zipalign: zipalign,
      llvmReadelf: llvmReadelf,
    ),
    failures: const [],
  );
}

void main() {
  final repository = Directory.current;
  final gradleHome = _gradleUserHome();
  final androidSdk = _androidSdkRoot(repository);
  final flutterExtension = _locateFlutterExtension(Platform.resolvedExecutable);
  if (gradleHome == null || androidSdk == null || flutterExtension == null) {
    if (gradleHome == null) stderr.writeln('Gradle user home is unavailable.');
    if (androidSdk == null) stderr.writeln('Android SDK root is unavailable.');
    if (flutterExtension == null) {
      stderr.writeln('Flutter Gradle extension is unavailable.');
    }
    exitCode = 1;
    return;
  }

  final result = resolveAndroidArtifactToolchain(
    repositoryRoot: repository,
    gradleUserHome: gradleHome,
    androidSdkRoot: androidSdk,
    flutterExtension: flutterExtension,
  );
  if (!result.passed) {
    for (final failure in result.failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  final toolchain = result.toolchain!;
  stdout.writeln();
  _emit('UTEXO_AGP_VERSION', toolchain.agpVersion);
  _emit('UTEXO_BUILD_TOOLS_VERSION', toolchain.buildToolsVersion);
  _emit('UTEXO_NDK_VERSION', toolchain.ndkVersion);
  _emit('UTEXO_AAPT2_PROTO_VERSION', toolchain.aapt2ProtoVersion);
  _emit('UTEXO_BUNDLETOOL_VERSION', toolchain.bundletoolVersion);
  _emit('UTEXO_PROTOBUF_VERSION', toolchain.protobufVersion);
  _emit('UTEXO_AAPT2_PROTO_JAR', toolchain.aapt2ProtoJar.path);
  _emit('UTEXO_BUNDLETOOL_JAR', toolchain.bundletoolJar.path);
  _emit('UTEXO_PROTOBUF_JAR', toolchain.protobufJar.path);
  _emit('UTEXO_APKSIGNER', toolchain.apksigner.path);
  _emit('UTEXO_AAPT2', toolchain.aapt2.path);
  _emit('UTEXO_ZIPALIGN', toolchain.zipalign.path);
  _emit('UTEXO_LLVM_READELF', toolchain.llvmReadelf.path);
}

Map<String, Object?>? _agpModuleMetadata(
  Directory gradleHome,
  String agpVersion,
  List<String> failures,
) {
  final directory = Directory(
    '${gradleHome.absolute.path}/caches/modules-2/files-2.1/'
    'com.android.tools.build/gradle/$agpVersion',
  );
  final files = directory.existsSync()
      ? directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where(
              (file) => _basename(file.path) == 'gradle-$agpVersion.module',
            )
            .toList()
      : <File>[];
  if (files.length != 1) {
    failures.add(
      'Expected one AGP $agpVersion module metadata file, found ${files.length}.',
    );
    return null;
  }
  try {
    final decoded = jsonDecode(files.single.readAsStringSync());
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // The deterministic failure below owns malformed cache metadata.
  } on FileSystemException {
    // The deterministic failure below owns unreadable cache metadata.
  }
  failures.add('AGP $agpVersion module metadata is malformed or unreadable.');
  return null;
}

String? _dependencyVersion(
  Map<String, Object?> metadata, {
  required String group,
  required String module,
  required List<String> failures,
}) {
  final versions = <String>{};
  final variants = metadata['variants'];
  if (variants is List<Object?>) {
    for (final variant in variants.whereType<Map<String, Object?>>()) {
      final dependencies = variant['dependencies'];
      if (dependencies is! List<Object?>) continue;
      for (final dependency in dependencies.whereType<Map<String, Object?>>()) {
        if (dependency['group'] != group || dependency['module'] != module) {
          continue;
        }
        final version = dependency['version'];
        if (version case {'requires': final String requiredVersion}) {
          versions.add(requiredVersion);
        }
      }
    }
  }
  if (versions.length != 1) {
    failures.add(
      'Expected one AGP dependency version for $group:$module, found '
      '${versions.length}.',
    );
    return null;
  }
  return versions.single;
}

File? _singleCachedJar(
  Directory gradleHome, {
  required String group,
  required String module,
  required String version,
  required List<String> failures,
}) {
  final directory = Directory(
    '${gradleHome.absolute.path}/caches/modules-2/files-2.1/'
    '$group/$module/$version',
  );
  final expectedName = '$module-$version.jar';
  final files = directory.existsSync()
      ? directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => _basename(file.path) == expectedName)
            .toList()
      : <File>[];
  if (files.length != 1) {
    failures.add(
      'Expected one cached $group:$module:$version jar, found ${files.length}.',
    );
    return null;
  }
  return files.single.absolute;
}

File? _singleExecutableNamed(
  Directory root,
  String name,
  String label,
  List<String> failures,
) {
  final files = root.existsSync()
      ? root
            .listSync(recursive: true, followLinks: false)
            .where((entity) => entity is File || entity is Link)
            .where((entity) => _basename(entity.path) == name)
            .where((entity) => _isExecutableWithin(entity, root))
            .map((entity) => File(entity.path))
            .toList()
      : <File>[];
  if (files.length != 1) {
    failures.add('Expected one executable $label, found ${files.length}.');
    return null;
  }
  return files.single.absolute;
}

File? _requiredExecutable(File file, String label, List<String> failures) {
  if (!_isExecutable(file)) {
    failures.add('Missing executable $label.');
    return null;
  }
  return file.absolute;
}

bool _isExecutable(File file) {
  if (!file.existsSync()) return false;
  final mode = file.statSync().mode;
  return mode & 0x49 != 0;
}

bool _isExecutableWithin(FileSystemEntity entity, Directory root) {
  final file = File(entity.path);
  if (!_isExecutable(file)) return false;
  try {
    final resolvedRoot = root.resolveSymbolicLinksSync();
    final resolvedEntity = entity.resolveSymbolicLinksSync();
    return resolvedEntity.startsWith('$resolvedRoot${Platform.pathSeparator}');
  } on FileSystemException {
    return false;
  }
}

String? _singleMatch(
  String? contents,
  RegExp pattern,
  String label,
  List<String> failures,
) {
  if (contents == null) return null;
  final matches = pattern.allMatches(contents).toList();
  if (matches.length != 1) {
    failures.add('Expected one inspectable $label, found ${matches.length}.');
    return null;
  }
  return matches.single.group(1);
}

String? _readRequired(File file, String label, List<String> failures) {
  if (!file.existsSync()) {
    failures.add('Missing $label.');
    return null;
  }
  try {
    return file.readAsStringSync();
  } on FileSystemException {
    failures.add('Could not read $label.');
    return null;
  }
}

Directory? _gradleUserHome() {
  final configured = Platform.environment['GRADLE_USER_HOME'];
  if (configured != null && configured.trim().isNotEmpty) {
    return Directory(configured);
  }
  final home = Platform.environment['HOME'];
  return home == null || home.trim().isEmpty
      ? null
      : Directory('$home/.gradle');
}

Directory? _androidSdkRoot(Directory repository) {
  final configured =
      Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'];
  if (configured != null && configured.trim().isNotEmpty) {
    return Directory(configured);
  }
  final properties = File(
    '${repository.absolute.path}/android/local.properties',
  );
  if (!properties.existsSync()) return null;
  final matches = RegExp(
    r'^sdk\.dir=(.+)$',
    multiLine: true,
  ).allMatches(properties.readAsStringSync()).toList();
  if (matches.length != 1) return null;
  return Directory(
    matches.single.group(1)!.replaceAll(r'\:', ':').replaceAll(r'\\', r'\'),
  );
}

File? _locateFlutterExtension(String dartExecutable) {
  var candidate = File(dartExecutable).absolute.parent;
  const relative =
      'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt';
  while (candidate.parent.path != candidate.path) {
    final file = File('${candidate.path}/$relative');
    if (file.existsSync()) return file;
    candidate = candidate.parent;
  }
  return null;
}

void _emit(String name, String value) => stdout.writeln('$name=$value');

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
