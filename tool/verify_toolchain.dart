import 'dart:io';

/// Result of checking the repository's cross-toolchain version contract.
final class ToolchainVerification {
  const ToolchainVerification({
    required this.flutterNdkVersion,
    required this.failures,
  });

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
  final result = verifyToolchain(
    repositoryRoot: Directory.current,
    flutterExtension: flutterExtension,
  );

  if (!result.passed) {
    for (final failure in result.failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Toolchain policy verified for Flutter NDK '
    '${result.flutterNdkVersion}.',
  );
}

/// Checks Android, Nix, and documentation against Flutter's NDK declaration.
///
/// [flutterExtension] is injectable so the fail-closed policy can be tested
/// without depending on a globally installed Flutter checkout.
ToolchainVerification verifyToolchain({
  required Directory repositoryRoot,
  required File? flutterExtension,
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

  failures.sort();
  return ToolchainVerification(
    flutterNdkVersion: ndkVersion,
    failures: List.unmodifiable(failures),
  );
}

File? _locateFlutterExtension(String dartExecutable) {
  var candidate = File(dartExecutable).absolute.parent;
  while (candidate.parent.path != candidate.path) {
    final extension = File(
      '${candidate.path}/packages/flutter_tools/gradle/src/main/kotlin/'
      'FlutterExtension.kt',
    );
    if (extension.existsSync()) return extension;
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
