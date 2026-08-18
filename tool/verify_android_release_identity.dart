import 'dart:io';

import 'package:yaml/yaml.dart';

import 'bounded_process.dart';

const _artifactToolTimeout = Duration(minutes: 2);
const _maximumAapt2OutputBytes = 1024 * 1024;
const _maximumInspectorOutputBytes = 64 * 1024;
const _maximumInspectorDiagnosticBytes = 256 * 1024;

/// Application and version metadata that must match a release artifact.
final class AndroidReleaseIdentity {
  const AndroidReleaseIdentity({
    required this.applicationId,
    required this.versionName,
    required this.versionCode,
    this.splitAbi,
  });

  final String applicationId;
  final String versionName;
  final int versionCode;

  /// ABI encoded into a split APK version code; absent for an App Bundle.
  final String? splitAbi;
}

/// Loads authoritative Android identity from committed project configuration.
AndroidReleaseIdentity parseExpectedAndroidReleaseIdentity({
  required String pubspec,
  required String gradleProperties,
}) {
  final document = loadYaml(pubspec);
  if (document is! YamlMap || document['version'] is! String) {
    throw const FormatException('pubspec.yaml must declare one version.');
  }
  final version = document['version']! as String;
  final versionMatch = RegExp(
    r'^([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?)'
    r'\+([1-9][0-9]*)$',
  ).firstMatch(version);
  if (versionMatch == null) {
    throw const FormatException(
      'pubspec.yaml version must include a positive numeric build number.',
    );
  }

  final applicationIds = <String>[];
  final propertyPattern = RegExp(
    r'^utexo\.applicationId='
    r'([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+)$',
  );
  for (final rawLine in gradleProperties.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
      continue;
    }
    if (!line.startsWith('utexo.applicationId=')) continue;
    final match = propertyPattern.firstMatch(line);
    if (match == null) {
      throw const FormatException(
        'utexo.applicationId is malformed in android/gradle.properties.',
      );
    }
    applicationIds.add(match.group(1)!);
  }
  if (applicationIds.length != 1) {
    throw const FormatException(
      'android/gradle.properties must declare one utexo.applicationId.',
    );
  }

  return AndroidReleaseIdentity(
    applicationId: applicationIds.single,
    versionName: versionMatch.group(1)!,
    versionCode: int.parse(versionMatch.group(2)!),
  );
}

/// Parses the package line emitted by the pinned Android `aapt2` binary.
AndroidReleaseIdentity parseAapt2Badging(String output) {
  final packageLines = output
      .split('\n')
      .where((line) => line.startsWith('package: '))
      .toList(growable: false);
  if (packageLines.length != 1) {
    throw const FormatException('aapt2 must emit exactly one package line.');
  }
  final values = <String, String>{};
  for (final match in RegExp(
    r"([A-Za-z][A-Za-z0-9]*)='([^']*)'",
  ).allMatches(packageLines.single)) {
    final key = match.group(1)!;
    if (values.containsKey(key)) {
      throw FormatException('aapt2 emitted duplicate $key metadata.');
    }
    values[key] = match.group(2)!;
  }
  final nativeCodeLines = output
      .split('\n')
      .where((line) => line.startsWith('native-code: '))
      .toList(growable: false);
  if (nativeCodeLines.length != 1) {
    throw const FormatException(
      'aapt2 must emit exactly one native-code line.',
    );
  }
  final packagedAbis = RegExp(r"'([^']+)'")
      .allMatches(nativeCodeLines.single)
      .map((match) => match.group(1)!)
      .toList();
  if (packagedAbis.length != 1 ||
      !_flutterSplitAbiVersions.containsKey(packagedAbis.single)) {
    throw const FormatException(
      'Release APK must contain exactly one supported Flutter ABI.',
    );
  }
  return _identityFromValues(
    applicationId: values['name'],
    versionName: values['versionName'],
    versionCode: values['versionCode'],
    source: 'aapt2',
    splitAbi: packagedAbis.single,
  );
}

/// Parses the constrained output of `AndroidManifestInspector.java`.
AndroidReleaseIdentity parseBundleManifestIdentity(String output) {
  const expectedKeys = {
    'UTEXO_APPLICATION_ID',
    'UTEXO_VERSION_NAME',
    'UTEXO_VERSION_CODE',
  };
  final values = <String, String>{};
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) {
      throw const FormatException('Bundle inspector output is malformed.');
    }
    final key = line.substring(0, separator);
    final value = line.substring(separator + 1);
    if (!expectedKeys.contains(key) || value.isEmpty) {
      throw const FormatException('Bundle inspector output is malformed.');
    }
    if (values.containsKey(key)) {
      throw FormatException('Bundle inspector emitted duplicate $key.');
    }
    values[key] = value;
  }
  if (values.keys.toSet().difference(expectedKeys).isNotEmpty ||
      expectedKeys.difference(values.keys.toSet()).isNotEmpty) {
    throw const FormatException('Bundle inspector output is incomplete.');
  }
  return _identityFromValues(
    applicationId: values['UTEXO_APPLICATION_ID'],
    versionName: values['UTEXO_VERSION_NAME'],
    versionCode: values['UTEXO_VERSION_CODE'],
    source: 'bundle inspector',
  );
}

/// Returns deterministic differences between source and packaged metadata.
List<String> compareAndroidReleaseIdentity({
  required AndroidReleaseIdentity expected,
  required AndroidReleaseIdentity actual,
}) {
  final failures = <String>[];
  final splitPrefix = actual.splitAbi == null
      ? 0
      : _flutterSplitAbiVersions[actual.splitAbi];
  if (actual.splitAbi != null && splitPrefix == null) {
    failures.add('split ABI ${actual.splitAbi} is not supported by Flutter');
  }
  final expectedVersionCode = splitPrefix == null
      ? expected.versionCode
      : splitPrefix * 1000 + expected.versionCode;
  if (actual.applicationId != expected.applicationId) {
    failures.add(
      'application ID ${actual.applicationId} does not match '
      '${expected.applicationId}',
    );
  }
  if (actual.versionName != expected.versionName) {
    failures.add(
      'version name ${actual.versionName} does not match '
      '${expected.versionName}',
    );
  }
  if (actual.versionCode != expectedVersionCode) {
    failures.add(
      'version code ${actual.versionCode} does not match '
      '$expectedVersionCode'
      '${actual.splitAbi == null ? '' : ' for ${actual.splitAbi}'}',
    );
  }
  return List.unmodifiable(failures);
}

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final repository = Directory.current.absolute;
    final expected = parseExpectedAndroidReleaseIdentity(
      pubspec: File('${repository.path}/pubspec.yaml').readAsStringSync(),
      gradleProperties: File('${repository.path}/android/gradle.properties')
          .readAsStringSync(),
    );
    final actual = await _inspectArtifact(options, repository);
    final failures = compareAndroidReleaseIdentity(
      expected: expected,
      actual: actual,
    );
    if (failures.isNotEmpty) {
      for (final failure in failures) {
        stderr.writeln('Android release identity check failed: $failure.');
      }
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Verified Android release identity ${actual.applicationId} '
      '${actual.versionName}+${actual.versionCode}.',
    );
  } on Object catch (error) {
    stderr.writeln('Android release identity check failed: $error');
    exitCode = 1;
  }
}

Future<AndroidReleaseIdentity> _inspectArtifact(
  Map<String, String> options,
  Directory repository,
) async {
  if (options case {'apk': final artifact, 'aapt2': final aapt2}) {
    _requireFile(artifact, 'APK');
    _requireFile(aapt2, 'aapt2');
    final result = await runBoundedProcess(
      aapt2,
      ['dump', 'badging', artifact],
      workingDirectory: repository.path,
      maxStdoutBytes: _maximumAapt2OutputBytes,
      maxStderrBytes: _maximumInspectorDiagnosticBytes,
      timeout: _artifactToolTimeout,
    );
    if (result.exitCode != 0) {
      throw StateError('aapt2 exited with code ${result.exitCode}.');
    }
    return parseAapt2Badging(result.stdout);
  }
  if (options case {
    'bundle': final artifact,
    'aapt2-proto': final aapt2Proto,
    'protobuf': final protobuf,
  }) {
    _requireFile(artifact, 'Android App Bundle');
    _requireFile(aapt2Proto, 'aapt2-proto jar');
    _requireFile(protobuf, 'protobuf jar');
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'utexo_android_manifest_',
    );
    try {
      final manifest = File('${temporaryDirectory.path}/AndroidManifest.pb');
      final extraction = await runBoundedProcess(
        'java',
        [
          'scripts/AndroidArchiveEntryExtractor.java',
          artifact,
          'base/manifest/AndroidManifest.xml',
          manifest.path,
          '16777216',
        ],
        workingDirectory: repository.path,
        maxStdoutBytes: _maximumInspectorOutputBytes,
        maxStderrBytes: _maximumInspectorDiagnosticBytes,
        timeout: _artifactToolTimeout,
      );
      if (extraction.exitCode != 0) {
        throw StateError(
          'bundle manifest extraction exited with code '
          '${extraction.exitCode}.',
        );
      }
      final result = await runBoundedProcess(
        'java',
        [
          '--class-path',
          '$aapt2Proto${Platform.isWindows ? ';' : ':'}$protobuf',
          'scripts/AndroidManifestInspector.java',
          manifest.path,
        ],
        workingDirectory: repository.path,
        maxStdoutBytes: _maximumInspectorOutputBytes,
        maxStderrBytes: _maximumInspectorDiagnosticBytes,
        timeout: _artifactToolTimeout,
      );
      if (result.exitCode != 0) {
        throw StateError(
          'bundle manifest inspector exited with code ${result.exitCode}.',
        );
      }
      return parseBundleManifestIdentity(result.stdout);
    } finally {
      await temporaryDirectory.delete(recursive: true);
    }
  }
  throw const FormatException('Unsupported Android artifact arguments.');
}

Map<String, String> _parseArguments(List<String> arguments) {
  if (arguments.length.isOdd) {
    throw const FormatException('Android artifact arguments must be pairs.');
  }
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final argument = arguments[index];
    if (!argument.startsWith('--') || argument.length == 2) {
      throw const FormatException('Android artifact option is malformed.');
    }
    final key = argument.substring(2);
    if (options.containsKey(key) || arguments[index + 1].isEmpty) {
      throw const FormatException('Android artifact option is invalid.');
    }
    options[key] = arguments[index + 1];
  }
  const apkKeys = {'apk', 'aapt2'};
  const bundleKeys = {'bundle', 'aapt2-proto', 'protobuf'};
  final keys = options.keys.toSet();
  if (!_sameSet(keys, apkKeys) && !_sameSet(keys, bundleKeys)) {
    throw const FormatException(
      'Use --apk with --aapt2, or --bundle with both manifest jars.',
    );
  }
  return Map.unmodifiable(options);
}

AndroidReleaseIdentity _identityFromValues({
  required String? applicationId,
  required String? versionName,
  required String? versionCode,
  required String source,
  String? splitAbi,
}) {
  if (applicationId == null || applicationId.isEmpty) {
    throw FormatException('$source omitted the application ID.');
  }
  if (versionName == null || versionName.isEmpty) {
    throw FormatException('$source omitted the version name.');
  }
  final parsedVersionCode = int.tryParse(versionCode ?? '');
  if (parsedVersionCode == null || parsedVersionCode <= 0) {
    throw FormatException('$source emitted an invalid version code.');
  }
  return AndroidReleaseIdentity(
    applicationId: applicationId,
    versionName: versionName,
    versionCode: parsedVersionCode,
    splitAbi: splitAbi,
  );
}

void _requireFile(String path, String description) {
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FileSystemException(
      '$description is missing or is not a regular file.',
      path,
    );
  }
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

// Mirrors Flutter 3.47.0 FlutterPluginConstants.ABI_VERSION. The toolchain
// gate pins Flutter; artifact tests fail if a later approved SDK changes it.
const _flutterSplitAbiVersions = <String, int>{
  'armeabi-v7a': 1,
  'arm64-v8a': 2,
  'x86_64': 4,
};
