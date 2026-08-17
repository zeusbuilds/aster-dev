import 'dart:io';

/// Result of checking the repository's cross-toolchain version contract.
final class ToolchainVerification {
  const ToolchainVerification({
    required this.flutterGradleVersion,
    required this.flutterAgpVersion,
    required this.flutterKotlinVersion,
    required this.flutterNdkVersion,
    required this.failures,
  });

  /// Gradle wrapper revision declared by the Flutter project template.
  final String? flutterGradleVersion;

  /// Android Gradle Plugin revision declared by the Flutter project template.
  final String? flutterAgpVersion;

  /// Kotlin Gradle Plugin revision declared by the Flutter project template.
  final String? flutterKotlinVersion;

  /// NDK revision declared by the Flutter SDK, when it could be resolved.
  final String? flutterNdkVersion;

  /// Deterministically ordered missing or divergent toolchain declarations.
  final List<String> failures;

  /// Whether every owned toolchain surface agrees with Flutter.
  bool get passed => failures.isEmpty;
}

/// Verifies the checked-out repository against the Dart executable's Flutter SDK.
void main() {
  final flutterExtension = _locateFlutterExtension(Platform.resolvedExecutable);
  final flutterGradleUtils = _locateFlutterGradleUtils(
    Platform.resolvedExecutable,
  );
  final result = verifyToolchain(
    repositoryRoot: Directory.current,
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
    'Toolchain policy verified for Gradle ${result.flutterGradleVersion}, '
    'AGP ${result.flutterAgpVersion}, Kotlin ${result.flutterKotlinVersion}, '
    'and NDK ${result.flutterNdkVersion}.',
  );
}

/// Checks Android, Nix, and documentation against Flutter's NDK declaration.
///
/// [flutterExtension] is injectable so the fail-closed policy can be tested
/// without depending on a globally installed Flutter checkout. The same is
/// true of [flutterGradleUtils], which owns Flutter's Android template pins.
ToolchainVerification verifyToolchain({
  required Directory repositoryRoot,
  required File? flutterExtension,
  required File? flutterGradleUtils,
}) {
  final failures = <String>[];
  final extensionContents = _readRequired(
    flutterExtension,
    'Flutter Gradle extension',
    failures,
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
  if (android != null &&
      !RegExp(r'\bndkVersion\s*=\s*flutter\.ndkVersion\b').hasMatch(android)) {
    failures.add(
      'android/app/build.gradle.kts must delegate ndkVersion to Flutter.',
    );
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

  failures.sort();
  return ToolchainVerification(
    flutterGradleVersion: gradleVersion,
    flutterAgpVersion: agpVersion,
    flutterKotlinVersion: kotlinVersion,
    flutterNdkVersion: ndkVersion,
    failures: List.unmodifiable(failures),
  );
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

File? _locateFlutterExtension(String dartExecutable) {
  return _locateFlutterFile(
    dartExecutable,
    'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt',
  );
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
