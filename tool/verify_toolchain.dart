import 'dart:convert';
import 'dart:io';

/// Result of checking the repository's cross-toolchain version contract.
final class ToolchainVerification {
  const ToolchainVerification({
    required this.flutterVersion,
    required this.dartVersion,
    required this.flutterGradleVersion,
    required this.flutterAgpVersion,
    required this.flutterKotlinVersion,
    required this.flutterCompileSdk,
    required this.flutterMinSdk,
    required this.flutterTargetSdk,
    required this.flutterNdkVersion,
    required this.androidBuildToolsVersion,
    required this.androidPlatformToolsVersion,
    required this.failures,
  });

  /// Flutter framework revision represented by the executing SDK.
  final String? flutterVersion;

  /// Dart SDK revision bundled with the executing Flutter SDK.
  final String? dartVersion;

  /// Gradle wrapper revision declared by the Flutter project template.
  final String? flutterGradleVersion;

  /// Android Gradle Plugin revision declared by the Flutter project template.
  final String? flutterAgpVersion;

  /// Kotlin Gradle Plugin revision declared by the Flutter project template.
  final String? flutterKotlinVersion;

  /// Android compile SDK declared by the Flutter Gradle extension.
  final int? flutterCompileSdk;

  /// Android minimum SDK declared by the Flutter Gradle extension.
  final int? flutterMinSdk;

  /// Android target SDK declared by the Flutter Gradle extension.
  final int? flutterTargetSdk;

  /// NDK revision declared by the Flutter SDK, when it could be resolved.
  final String? flutterNdkVersion;

  /// Android build-tools revision pinned by the application and Nix shell.
  final String? androidBuildToolsVersion;

  /// Android platform-tools revision pinned by the reproducible Nix shell.
  final String? androidPlatformToolsVersion;

  /// Deterministically ordered missing or divergent toolchain declarations.
  final List<String> failures;

  /// Whether every owned toolchain surface agrees with Flutter.
  bool get passed => failures.isEmpty;
}

/// Verifies the checked-out repository against the Dart executable's Flutter SDK.
void main() {
  final flutterVersionMetadata = _locateFlutterVersionMetadata(
    Platform.resolvedExecutable,
  );
  final flutterExtension = _locateFlutterExtension(Platform.resolvedExecutable);
  final flutterGradleUtils = _locateFlutterGradleUtils(
    Platform.resolvedExecutable,
  );
  final result = verifyToolchain(
    repositoryRoot: Directory.current,
    flutterVersionMetadata: flutterVersionMetadata,
    flutterExtension: flutterExtension,
    flutterGradleUtils: flutterGradleUtils,
  );

  if (!result.passed) {
    for (final failure in result.failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Toolchain policy verified for Flutter ${result.flutterVersion}, '
    'Dart ${result.dartVersion}, Gradle ${result.flutterGradleVersion}, '
    'AGP ${result.flutterAgpVersion}, Kotlin ${result.flutterKotlinVersion}, '
    'Android SDK ${result.flutterCompileSdk}, build tools '
    '${result.androidBuildToolsVersion}, platform tools '
    '${result.androidPlatformToolsVersion}, and NDK '
    '${result.flutterNdkVersion}.',
  );
}

/// Checks every owned toolchain surface against the executing Flutter SDK.
///
/// Flutter-owned files are injectable so the fail-closed policy can be tested
/// without depending on a globally installed Flutter checkout.
ToolchainVerification verifyToolchain({
  required Directory repositoryRoot,
  required File? flutterVersionMetadata,
  required File? flutterExtension,
  required File? flutterGradleUtils,
}) {
  final failures = <String>[];
  final versionMetadata = _readJsonObject(
    flutterVersionMetadata,
    'Flutter version metadata',
    failures,
  );
  final flutterVersion = _readJsonString(
    versionMetadata,
    'flutterVersion',
    'Flutter framework version',
    failures,
  );
  final dartVersion = _readJsonString(
    versionMetadata,
    'dartSdkVersion',
    'Flutter-bundled Dart version',
    failures,
  );

  final extensionContents = _readRequired(
    flutterExtension,
    'Flutter Gradle extension',
    failures,
  );
  final flutterGradleDirectory = flutterExtension?.parent;
  final flutterPluginConstants = _readRequired(
    flutterGradleDirectory == null
        ? null
        : File('${flutterGradleDirectory.path}/FlutterPluginConstants.kt'),
    'Flutter Gradle plugin constants',
    failures,
  );
  final flutterPlugin = _readRequired(
    flutterGradleDirectory == null
        ? null
        : File('${flutterGradleDirectory.path}/FlutterPlugin.kt'),
    'Flutter Gradle plugin',
    failures,
  );
  _verifyFlutterSplitVersioning(
    constants: flutterPluginConstants,
    plugin: flutterPlugin,
    failures: failures,
  );
  final ndkVersion = extensionContents == null
      ? null
      : RegExp(r'val\s+ndkVersion\s*:\s*String\s*=\s*"([^"]+)"')
            .firstMatch(extensionContents)
            ?.group(1);
  if (extensionContents != null && ndkVersion == null) {
    failures.add(
      'Flutter Gradle extension does not expose an inspectable ndkVersion.',
    );
  }
  final compileSdk = _readKotlinIntProperty(
    extensionContents,
    'compileSdkVersion',
    'Flutter compile SDK',
    failures,
  );
  final minSdk = _readKotlinIntProperty(
    extensionContents,
    'minSdkVersion',
    'Flutter minimum SDK',
    failures,
  );
  final targetSdk = _readKotlinIntProperty(
    extensionContents,
    'targetSdkVersion',
    'Flutter target SDK',
    failures,
  );

  final gradleUtilsContents = _readRequired(
    flutterGradleUtils,
    'Flutter Gradle utilities',
    failures,
  );
  final gradleVersion = _readDartStringConstant(
    gradleUtilsContents,
    'templateDefaultGradleVersion',
    'Flutter Gradle version',
    failures,
  );
  final agpVersion = _readDartStringConstant(
    gradleUtilsContents,
    'templateAndroidGradlePluginVersion',
    'Flutter Android Gradle Plugin version',
    failures,
  );
  final kotlinVersion = _readDartStringConstant(
    gradleUtilsContents,
    'templateKotlinGradlePluginVersion',
    'Flutter Kotlin Gradle Plugin version',
    failures,
  );

  final root = repositoryRoot.absolute.path;
  final android = _readRequired(
    File('$root/android/app/build.gradle.kts'),
    'android/app/build.gradle.kts',
    failures,
  );
  final androidProperties = _readRequired(
    File('$root/android/gradle.properties'),
    'android/gradle.properties',
    failures,
  );
  String? buildToolsVersion;
  if (android != null) {
    _requireSinglePattern(
      android,
      RegExp(
        r'val\s+utexoApplicationId\s*=\s*providers\.gradleProperty\('
        r'"utexo\.applicationId"\)\.get\(\)',
      ),
      'Android application ID must come from the owned Gradle property.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bnamespace\s*=\s*utexoApplicationId\b'),
      'Android namespace must use the owned application ID.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bapplicationId\s*=\s*utexoApplicationId\b'),
      'Android release application ID must use the owned property.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bcompileSdk\s*=\s*flutter\.compileSdkVersion\b'),
      'android/app/build.gradle.kts must delegate compileSdk to Flutter.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bminSdk\s*=\s*flutter\.minSdkVersion\b'),
      'android/app/build.gradle.kts must delegate minSdk to Flutter.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\btargetSdk\s*=\s*flutter\.targetSdkVersion\b'),
      'android/app/build.gradle.kts must delegate targetSdk to Flutter.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bndkVersion\s*=\s*flutter\.ndkVersion\b'),
      'android/app/build.gradle.kts must delegate ndkVersion to Flutter.',
      failures,
    );
    buildToolsVersion = _readSingleCapture(
      android,
      RegExp(r'\bbuildToolsVersion\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"'),
      'Android build-tools version',
      failures,
    );
    if (compileSdk != null &&
        buildToolsVersion != null &&
        buildToolsVersion.split('.').first != compileSdk.toString()) {
      failures.add(
        'Android build tools $buildToolsVersion must match compile SDK '
        '$compileSdk.',
      );
    }
  }

  final settings = _readRequired(
    File('$root/android/settings.gradle.kts'),
    'android/settings.gradle.kts',
    failures,
  );
  if (settings != null) {
    _requirePluginVersion(
      settings,
      plugin: 'com.android.application',
      expected: agpVersion,
      label: 'Android Gradle Plugin',
      failures: failures,
    );
    _requirePluginVersion(
      settings,
      plugin: 'org.jetbrains.kotlin.android',
      expected: kotlinVersion,
      label: 'Kotlin Gradle Plugin',
      failures: failures,
    );
  }

  final wrapper = _readRequired(
    File('$root/android/gradle/wrapper/gradle-wrapper.properties'),
    'android/gradle/wrapper/gradle-wrapper.properties',
    failures,
  );
  if (wrapper != null &&
      gradleVersion != null &&
      !wrapper.contains(
        'distributionUrl=https\\://services.gradle.org/distributions/'
        'gradle-$gradleVersion-all.zip',
      )) {
    failures.add(
      'Android Gradle wrapper must use Flutter Gradle $gradleVersion.',
    );
  }

  final flake = _readRequired(File('$root/flake.nix'), 'flake.nix', failures);
  String? platformToolsVersion;
  if (flake != null) {
    if (!RegExp(r'\bincludeNDK\s*=\s*true\s*;').hasMatch(flake)) {
      failures.add('flake.nix must include the Android NDK.');
    }
    final declaredVersions = RegExp(
      r'\bndkVersions\s*=\s*\[\s*"([^"]+)"\s*\]\s*;',
    ).allMatches(flake).map((match) => match.group(1)!).toList();
    if (ndkVersion != null &&
        (declaredVersions.length != 1 ||
            declaredVersions.single != ndkVersion)) {
      failures.add('flake.nix must declare exactly Flutter NDK $ndkVersion.');
    }
    _requireNixVersionList(
      flake,
      property: 'buildToolsVersions',
      expected: buildToolsVersion,
      label: 'Android build tools',
      failures: failures,
    );
    _requireNixVersionList(
      flake,
      property: 'platformVersions',
      expected: compileSdk?.toString(),
      label: 'Android SDK platform',
      failures: failures,
    );
    platformToolsVersion = _readSingleCapture(
      flake,
      RegExp(r'\bplatformToolsVersion\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"'),
      'Nix Android platform-tools version',
      failures,
    );
    if (buildToolsVersion != null &&
        !flake.contains('build-tools/$buildToolsVersion')) {
      failures.add(
        'flake.nix PATH must expose Android build tools $buildToolsVersion.',
      );
    }
  }

  final fvm = _readJsonObject(File('$root/.fvmrc'), '.fvmrc', failures);
  _requireJsonValue(
    fvm,
    key: 'flutter',
    expected: flutterVersion,
    label: '.fvmrc Flutter version',
    failures: failures,
  );

  final vscode = _readJsonObject(
    File('$root/.vscode/settings.json'),
    '.vscode/settings.json',
    failures,
  );
  _requireJsonValue(
    vscode,
    key: 'dart.flutterSdkPath',
    expected: flutterVersion == null ? null : '.fvm/versions/$flutterVersion',
    label: 'VS Code Flutter SDK path',
    failures: failures,
  );

  final workflow = _readRequired(
    File('$root/.github/workflows/dart.yml'),
    '.github/workflows/dart.yml',
    failures,
  );
  if (workflow != null && flutterVersion != null) {
    _requireSingleCapturedValue(
      workflow,
      RegExp(r'\bflutter-version:\s*"([^"]+)"'),
      flutterVersion,
      'GitHub Actions Flutter version',
      failures,
    );
  }
  if (androidProperties != null) {
    _readSingleCapture(
      androidProperties,
      RegExp(
        r'^utexo\.applicationId='
        r'([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+)\s*$',
        multiLine: true,
      ),
      'Android application ID property',
      failures,
    );
  }
  if (workflow != null) {
    _requireSinglePattern(
      workflow,
      RegExp(
        r'^\s*run:\s*flutter pub get --enforce-lockfile\s*$',
        multiLine: true,
      ),
      'GitHub Actions must resolve the committed Pub lockfile exactly once.',
      failures,
    );
    _requireSinglePattern(
      workflow,
      RegExp(r'^\s*run:\s*flutter analyze --no-pub\b', multiLine: true),
      'GitHub Actions analysis must not re-resolve dependencies.',
      failures,
    );
    _requireSinglePattern(
      workflow,
      RegExp(r'^\s*run:\s*flutter test --no-pub\s*$', multiLine: true),
      'GitHub Actions tests must not re-resolve dependencies.',
      failures,
    );
  }

  final makefile = _readRequired(File('$root/Makefile'), 'Makefile', failures);
  if (makefile != null) {
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^\s*fvm flutter pub get --enforce-lockfile\s*$',
        multiLine: true,
      ),
      'Makefile dependency setup must enforce the committed Pub lockfile.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^prepare-android-release:\s*$\n'
        r'\tfvm flutter clean\s*$\n'
        r'\t@\$\(MAKE\) --no-print-directory dependencies\s*$\n'
        r'\tfvm dart run tool/prepare_android_release\.dart\s*$',
        multiLine: true,
      ),
      'Android Release preparation must clean, resolve the exact lock, and '
      'then run the guarded plugin tool in order.',
      failures,
    );
    for (final target in ['android-release-bundle', 'android-release-apks']) {
      _requireSinglePattern(
        makefile,
        RegExp('^$target:\\s+prepare-android-release\\s*\$', multiLine: true),
        '$target must depend on guarded Release plugin preparation.',
        failures,
      );
    }
  }

  final apkVerifier = _readRequired(
    File('$root/scripts/verify-android-release-apks.sh'),
    'scripts/verify-android-release-apks.sh',
    failures,
  );
  if (apkVerifier != null) {
    _requireSinglePattern(
      apkVerifier,
      RegExp(r'fvm dart run tool/verify_android_release_identity\.dart'),
      'APK verification must enforce committed release identity.',
      failures,
    );
    _requireSinglePattern(
      apkVerifier,
      RegExp(r'--aapt2 "\$\{UTEXO_AAPT2\}"'),
      'APK identity verification must use the resolved aapt2 binary.',
      failures,
    );
  }
  final bundleVerifier = _readRequired(
    File('$root/scripts/verify-android-release-bundle.sh'),
    'scripts/verify-android-release-bundle.sh',
    failures,
  );
  if (bundleVerifier != null) {
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'fvm dart run tool/verify_android_release_identity\.dart'),
      'Bundle verification must enforce committed release identity.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'--aapt2-proto "\$\{UTEXO_AAPT2_PROTO_JAR\}"'),
      'Bundle identity verification must use the resolved aapt2 schema.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'--protobuf "\$\{UTEXO_PROTOBUF_JAR\}"'),
      'Bundle identity verification must use the resolved protobuf runtime.',
      failures,
    );
  }

  final pubspec = _readRequired(
    File('$root/pubspec.yaml'),
    'pubspec.yaml',
    failures,
  );
  if (pubspec != null && dartVersion != null) {
    _requireSinglePattern(
      pubspec,
      RegExp(
        '^  sdk: ">=${RegExp.escape(dartVersion)} <4\\.0\\.0"\\s*\$',
        multiLine: true,
      ),
      'pubspec.yaml must require Dart >=$dartVersion <4.0.0.',
      failures,
    );
  }
  if (pubspec != null && flutterVersion != null) {
    _requireSinglePattern(
      pubspec,
      RegExp(
        '^  flutter: ">=${RegExp.escape(flutterVersion)}"\\s*\$',
        multiLine: true,
      ),
      'pubspec.yaml must require Flutter >=$flutterVersion.',
      failures,
    );
  }

  final development = _readRequired(
    File('$root/docs/DEVELOPMENT.md'),
    'docs/DEVELOPMENT.md',
    failures,
  );
  if (development != null &&
      ndkVersion != null &&
      !development.contains('Android NDK $ndkVersion')) {
    failures.add('docs/DEVELOPMENT.md must document Android NDK $ndkVersion.');
  }
  if (development != null &&
      gradleVersion != null &&
      agpVersion != null &&
      kotlinVersion != null &&
      !development.contains(
        'Gradle $gradleVersion, Android Gradle Plugin $agpVersion, and '
        'Kotlin $kotlinVersion',
      )) {
    failures.add(
      'docs/DEVELOPMENT.md must document Flutter\'s Android build chain.',
    );
  }
  if (development != null &&
      compileSdk != null &&
      buildToolsVersion != null &&
      platformToolsVersion != null &&
      !development.contains(
        'Android SDK platform $compileSdk, build tools $buildToolsVersion, '
        'and platform tools $platformToolsVersion',
      )) {
    failures.add(
      'docs/DEVELOPMENT.md must document the Android SDK/build-tools chain.',
    );
  }
  if (development != null &&
      flutterVersion != null &&
      dartVersion != null &&
      !development.contains('Flutter $flutterVersion and Dart $dartVersion')) {
    failures.add(
      'docs/DEVELOPMENT.md must document the Flutter/Dart versions.',
    );
  }

  failures.sort();
  return ToolchainVerification(
    flutterVersion: flutterVersion,
    dartVersion: dartVersion,
    flutterGradleVersion: gradleVersion,
    flutterAgpVersion: agpVersion,
    flutterKotlinVersion: kotlinVersion,
    flutterCompileSdk: compileSdk,
    flutterMinSdk: minSdk,
    flutterTargetSdk: targetSdk,
    flutterNdkVersion: ndkVersion,
    androidBuildToolsVersion: buildToolsVersion,
    androidPlatformToolsVersion: platformToolsVersion,
    failures: List.unmodifiable(failures),
  );
}

Map<String, Object?>? _readJsonObject(
  File? file,
  String label,
  List<String> failures,
) {
  final contents = _readRequired(file, label, failures);
  if (contents == null) return null;
  try {
    final decoded = jsonDecode(contents);
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // The deterministic failure below owns malformed metadata.
  }
  failures.add('$label must contain one JSON object.');
  return null;
}

String? _readJsonString(
  Map<String, Object?>? object,
  String key,
  String label,
  List<String> failures,
) {
  if (object == null) return null;
  final value = object[key];
  if (value is String && value.isNotEmpty) return value;
  failures.add('$label is not inspectable.');
  return null;
}

int? _readKotlinIntProperty(
  String? contents,
  String name,
  String label,
  List<String> failures,
) {
  if (contents == null) return null;
  final value = _readSingleCapture(
    contents,
    RegExp('val\\s+$name\\s*:\\s*Int\\s*=\\s*(\\d+)'),
    label,
    failures,
  );
  return value == null ? null : int.parse(value);
}

String? _readSingleCapture(
  String contents,
  RegExp pattern,
  String label,
  List<String> failures,
) {
  final matches = pattern.allMatches(contents).toList();
  final value = matches.length == 1 ? matches.single.group(1) : null;
  if (value == null) {
    failures.add('Expected one inspectable $label, found ${matches.length}.');
  }
  return value;
}

void _requireSinglePattern(
  String contents,
  RegExp pattern,
  String message,
  List<String> failures,
) {
  if (pattern.allMatches(contents).length != 1) failures.add(message);
}

void _requireSingleCapturedValue(
  String contents,
  RegExp pattern,
  String expected,
  String label,
  List<String> failures,
) {
  final values = pattern
      .allMatches(contents)
      .map((match) => match.group(1))
      .toList();
  if (values.length != 1 || values.single != expected) {
    failures.add('$label must be exactly $expected.');
  }
}

void _requireNixVersionList(
  String flake, {
  required String property,
  required String? expected,
  required String label,
  required List<String> failures,
}) {
  if (expected == null) return;
  final versions = RegExp(
    '\\b${RegExp.escape(property)}\\s*=\\s*\\[\\s*"([^"]+)"\\s*\\]\\s*;',
  ).allMatches(flake).map((match) => match.group(1)).toList();
  if (versions.length != 1 || versions.single != expected) {
    failures.add('flake.nix must declare exactly $label $expected.');
  }
}

void _requireJsonValue(
  Map<String, Object?>? object, {
  required String key,
  required String? expected,
  required String label,
  required List<String> failures,
}) {
  if (object == null || expected == null) return;
  if (object[key] != expected) {
    failures.add('$label must be exactly $expected.');
  }
}

String? _readDartStringConstant(
  String? contents,
  String name,
  String label,
  List<String> failures,
) {
  if (contents == null) return null;
  final value = RegExp("const\\s+$name\\s*=\\s*'([^']+)'")
      .firstMatch(contents)
      ?.group(1);
  if (value == null) failures.add('$label is not inspectable.');
  return value;
}

void _requirePluginVersion(
  String settings, {
  required String plugin,
  required String? expected,
  required String label,
  required List<String> failures,
}) {
  if (expected == null) return;
  final matches = RegExp(
    'id\\("${RegExp.escape(plugin)}"\\)\\s+version\\s+"([^"]+)"',
  ).allMatches(settings).map((match) => match.group(1)!).toList();
  if (matches.length != 1 || matches.single != expected) {
    failures.add(
      'android/settings.gradle.kts must declare exactly $label $expected.',
    );
  }
}

void _verifyFlutterSplitVersioning({
  required String? constants,
  required String? plugin,
  required List<String> failures,
}) {
  if (constants != null) {
    final actual = <String, int>{};
    for (final match in RegExp(
      r'ARCH_(ARM32|ARM64|X86_64)\s+to\s+([0-9]+)',
    ).allMatches(constants)) {
      final abi = match.group(1)!;
      if (actual.containsKey(abi)) {
        failures.add('Flutter split-ABI version map contains duplicate $abi.');
        continue;
      }
      actual[abi] = int.parse(match.group(2)!);
    }
    const expected = {'ARM32': 1, 'ARM64': 2, 'X86_64': 4};
    if (actual.length != expected.length ||
        expected.entries.any((entry) => actual[entry.key] != entry.value)) {
      failures.add(
        'Flutter split-ABI version map differs from the artifact verifier.',
      );
    }
  }
  if (plugin != null &&
      !RegExp(r'versionCodeOverride\s*=\s*abiVersionCode\s*\*\s*1000\s*\+')
          .hasMatch(plugin)) {
    failures.add(
      'Flutter split-ABI version-code multiplier differs from the artifact '
      'verifier.',
    );
  }
}

File? _locateFlutterExtension(String dartExecutable) {
  return _locateFlutterFile(
    dartExecutable,
    'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt',
  );
}

File? _locateFlutterVersionMetadata(String dartExecutable) {
  return _locateFlutterFile(dartExecutable, 'bin/cache/flutter.version.json');
}

File? _locateFlutterGradleUtils(String dartExecutable) {
  return _locateFlutterFile(
    dartExecutable,
    'packages/flutter_tools/lib/src/android/gradle_utils.dart',
  );
}

File? _locateFlutterFile(String dartExecutable, String relativePath) {
  var candidate = File(dartExecutable).absolute.parent;
  while (candidate.parent.path != candidate.path) {
    final file = File('${candidate.path}/$relativePath');
    if (file.existsSync()) return file;
    candidate = candidate.parent;
  }
  return null;
}

String? _readRequired(File? file, String label, List<String> failures) {
  if (file == null || !file.existsSync()) {
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
