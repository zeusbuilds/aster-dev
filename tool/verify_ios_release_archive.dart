import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'bounded_process.dart';
import 'verify_android_release_identity.dart';

const maximumIosInstalledBytes = 500 * 1024 * 1024;
const _plistTimeout = Duration(minutes: 1);
const _codesignTimeout = Duration(minutes: 3);
const _maximumPlistBytes = 4 * 1024 * 1024;
const _maximumDiagnosticBytes = 2 * 1024 * 1024;

/// Metadata that an iOS archive must preserve from committed project source.
final class IosReleaseIdentity {
  const IosReleaseIdentity({
    required this.bundleIdentifier,
    required this.versionName,
    required this.buildNumber,
  });

  final String bundleIdentifier;
  final String versionName;
  final String buildNumber;
}

/// Verified identity and footprint of one packaged iOS application bundle.
final class IosReleaseApplicationMeasurement {
  const IosReleaseApplicationMeasurement({
    required this.identity,
    required this.installedBytes,
    required this.executableSha256,
  });

  final IosReleaseIdentity identity;
  final int installedBytes;
  final String executableSha256;
}

/// Extracts release identity from one compiled application plist.
IosReleaseIdentity parseIosReleaseIdentity(Map<String, Object?> plist) {
  final bundleIdentifier = plist['CFBundleIdentifier'];
  final versionName = plist['CFBundleShortVersionString'];
  final buildNumber = plist['CFBundleVersion'];
  if (bundleIdentifier is! String ||
      bundleIdentifier.isEmpty ||
      versionName is! String ||
      versionName.isEmpty ||
      buildNumber is! String ||
      buildNumber.isEmpty) {
    throw const FormatException('iOS release identity is incomplete.');
  }
  return IosReleaseIdentity(
    bundleIdentifier: bundleIdentifier,
    versionName: versionName,
    buildNumber: buildNumber,
  );
}

/// Returns deterministic differences between source and packaged iOS metadata.
List<String> compareIosReleaseIdentity({
  required IosReleaseIdentity expected,
  required IosReleaseIdentity actual,
}) {
  final failures = <String>[];
  if (actual.bundleIdentifier != expected.bundleIdentifier) {
    failures.add(
      'bundle ID ${actual.bundleIdentifier} does not match '
      '${expected.bundleIdentifier}',
    );
  }
  if (actual.versionName != expected.versionName) {
    failures.add(
      'version ${actual.versionName} does not match ${expected.versionName}',
    );
  }
  if (actual.buildNumber != expected.buildNumber) {
    failures.add(
      'build ${actual.buildNumber} does not match ${expected.buildNumber}',
    );
  }
  return List.unmodifiable(failures);
}

/// Parses the property-list value contained by one XML plist document.
Object? parsePlistXml(String source) {
  final document = XmlDocument.parse(source);
  final roots = document.findAllElements('plist').toList(growable: false);
  if (roots.length != 1) {
    throw const FormatException('Expected one plist root.');
  }
  final values = roots.single.childElements.toList(growable: false);
  if (values.length != 1) {
    throw const FormatException('Expected one plist value.');
  }
  return _parsePlistElement(values.single);
}

/// Validates the app-owned declarations; native dependency privacy admission
/// remains a separate required gate, not inferred from this manifest.
void validateIosPrivacyManifest(Map<String, Object?> plist) {
  const allowedRootKeys = <String>{
    'NSPrivacyAccessedAPITypes',
    'NSPrivacyTracking',
  };
  if (plist.keys.toSet().difference(allowedRootKeys).isNotEmpty ||
      !plist.keys.toSet().containsAll(allowedRootKeys)) {
    throw const FormatException(
      'Privacy manifest contains unreviewed declarations.',
    );
  }
  if (plist['NSPrivacyTracking'] != false) {
    throw const FormatException('Privacy manifest must disable tracking.');
  }
  final accessed = plist['NSPrivacyAccessedAPITypes'];
  if (accessed is! List<Object?>) {
    throw const FormatException('Privacy API declarations are missing.');
  }
  final reasons = <String, Set<String>>{};
  for (final value in accessed) {
    if (value is! Map<String, Object?> ||
        value.length != 2 ||
        !value.containsKey('NSPrivacyAccessedAPIType') ||
        !value.containsKey('NSPrivacyAccessedAPITypeReasons')) {
      throw const FormatException('Privacy API declaration is malformed.');
    }
    final category = value['NSPrivacyAccessedAPIType'];
    final rawReasons = value['NSPrivacyAccessedAPITypeReasons'];
    if (category is! String ||
        rawReasons is! List<Object?> ||
        rawReasons.isEmpty ||
        rawReasons.any((reason) => reason is! String) ||
        reasons.containsKey(category)) {
      throw const FormatException('Privacy API declaration is malformed.');
    }
    final categoryReasons = rawReasons.cast<String>().toSet();
    if (categoryReasons.length != rawReasons.length) {
      throw const FormatException('Privacy API reasons must be unique.');
    }
    reasons[category] = categoryReasons;
  }
  const required = <String, Set<String>>{
    'NSPrivacyAccessedAPICategoryFileTimestamp': {'C617.1'},
  };
  if (reasons.length != required.length ||
      required.entries.any(
        (entry) => !_setEquals(reasons[entry.key], entry.value),
      )) {
    throw const FormatException(
      'Privacy manifest does not exactly match approved API reasons.',
    );
  }
}

/// Reads the release identity committed by Aster's shared package metadata.
IosReleaseIdentity expectedIosReleaseIdentity(Directory repository) {
  final root = repository.absolute.path;
  final sourceIdentity = parseExpectedAndroidReleaseIdentity(
    pubspec: File('$root/pubspec.yaml').readAsStringSync(),
    gradleProperties: File('$root/android/gradle.properties')
        .readAsStringSync(),
  );
  return IosReleaseIdentity(
    bundleIdentifier: sourceIdentity.applicationId,
    versionName: sourceIdentity.versionName,
    buildNumber: '${sourceIdentity.versionCode}',
  );
}

/// Verifies one app bundle as it appears in an archive or exported IPA.
///
/// Package identity, app metadata, privacy declarations, tree ownership,
/// installed size, executable identity, and (when requested) the on-disk code
/// signature are checked against committed source rather than trusted from the
/// packaging command's exit status.
Future<IosReleaseApplicationMeasurement> verifyIosReleaseApplication({
  required Directory repository,
  required Directory app,
  required IosReleaseIdentity expected,
  required bool requireSigned,
}) async {
  _requireDirectory(app, 'packaged application');
  final appPlist = _requirePlistMap(
    await _readPlist(File('${app.path}/Info.plist')),
    'application Info.plist',
  );
  final actual = parseIosReleaseIdentity(appPlist);
  final failures = compareIosReleaseIdentity(
    expected: expected,
    actual: actual,
  );
  if (failures.isNotEmpty) {
    throw FormatException(failures.join('; '));
  }
  validateIosApplicationPlist(appPlist);

  final privacy = _requirePlistMap(
    await _readPlist(File('${app.path}/PrivacyInfo.xcprivacy')),
    'privacy manifest',
  );
  validateIosPrivacyManifest(privacy);

  final executable = File('${app.path}/Runner');
  _requireFile(executable, 'application executable');
  final executableDigest = await sha256.bind(executable.openRead()).first;
  final installedBytes = await measureSafeIosAppDirectory(app);
  if (installedBytes > maximumIosInstalledBytes) {
    throw FormatException(
      'Packaged app is $installedBytes bytes, above the '
      '$maximumIosInstalledBytes-byte budget.',
    );
  }

  if (requireSigned) {
    _requireFile(
      File('${app.path}/_CodeSignature/CodeResources'),
      'code signature resources',
    );
    _requireFile(
      File('${app.path}/embedded.mobileprovision'),
      'embedded provisioning profile',
    );
    final result = await runBoundedProcess(
      '/usr/bin/codesign',
      ['--verify', '--deep', '--strict', app.path],
      workingDirectory: repository.absolute.path,
      killProcessTree: true,
      maxStdoutBytes: _maximumDiagnosticBytes,
      maxStderrBytes: _maximumDiagnosticBytes,
      timeout: _codesignTimeout,
    );
    if (result.exitCode != 0) {
      throw StateError('codesign verification exited ${result.exitCode}.');
    }
  }

  return IosReleaseApplicationMeasurement(
    identity: actual,
    installedBytes: installedBytes,
    executableSha256: '$executableDigest',
  );
}

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final root = Directory.current.absolute;
    final archive = Directory(options.archive).absolute;
    _requireDirectory(archive, 'iOS archive');

    final expected = expectedIosReleaseIdentity(root);

    final archivePlist = _requirePlistMap(
      await _readPlist(File('${archive.path}/Info.plist')),
      'archive Info.plist',
    );
    final properties = archivePlist['ApplicationProperties'];
    if (properties is! Map<String, Object?>) {
      throw const FormatException('Archive ApplicationProperties are missing.');
    }
    final applicationPath = properties['ApplicationPath'];
    if (applicationPath != 'Applications/Runner.app') {
      throw const FormatException('Archive application path is unexpected.');
    }
    final app = Directory('${archive.path}/Products/$applicationPath');
    _requireDirectory(app, 'archived application');

    final archiveIdentity = parseIosReleaseIdentity(properties);
    final failures = compareIosReleaseIdentity(
      expected: expected,
      actual: archiveIdentity,
    );
    if (failures.isNotEmpty) {
      throw FormatException(failures.join('; '));
    }
    final measurement = await verifyIosReleaseApplication(
      repository: root,
      app: app,
      expected: expected,
      requireSigned: options.requireSigned,
    );

    stdout.writeln(
      'Verified iOS archive ${measurement.identity.bundleIdentifier} '
      '${measurement.identity.versionName}+'
      '${measurement.identity.buildNumber}; installed size '
      '${measurement.installedBytes} bytes; executable SHA-256 '
      '${measurement.executableSha256}'
      '${options.requireSigned ? '; code signature valid' : ''}.',
    );
  } on Object catch (error) {
    stderr.writeln('iOS release archive check failed: $error');
    exitCode = 1;
  }
}

/// Validates release-owned application metadata and transport policy.
void validateIosApplicationPlist(Map<String, Object?> plist) {
  if (plist['CFBundleDisplayName'] != 'Aster' ||
      plist['CFBundleName'] != 'Aster' ||
      plist['CFBundleExecutable'] != 'Runner' ||
      plist['MinimumOSVersion'] != '18.5') {
    throw const FormatException('Packaged Aster metadata is inconsistent.');
  }
  final families = plist['UIDeviceFamily'];
  if (families is! List<Object?> ||
      families.length != 1 ||
      families.single != 1) {
    throw const FormatException('Release archive must be iPhone-only.');
  }
  final platforms = plist['CFBundleSupportedPlatforms'];
  if (platforms is! List<Object?> ||
      platforms.length != 1 ||
      platforms.single != 'iPhoneOS') {
    throw const FormatException('Release archive platform is inconsistent.');
  }
  final transport = plist['NSAppTransportSecurity'];
  if (transport is! Map<String, Object?> ||
      transport.length != 1 ||
      transport['NSAllowsLocalNetworking'] != true) {
    throw const FormatException(
      'Release archive transport policy is inconsistent.',
    );
  }
}

bool _setEquals<T>(Set<T>? left, Set<T> right) =>
    left != null && left.length == right.length && left.containsAll(right);

Future<String> _readPlist(File file) async {
  _requireFile(file, 'property list');
  final result = await runBoundedProcess(
    '/usr/bin/plutil',
    ['-convert', 'xml1', '-o', '-', file.path],
    maxStdoutBytes: _maximumPlistBytes,
    maxStderrBytes: _maximumDiagnosticBytes,
    timeout: _plistTimeout,
  );
  if (result.exitCode != 0) {
    throw StateError('plutil exited ${result.exitCode}.');
  }
  return result.stdout;
}

Map<String, Object?> _requirePlistMap(String source, String label) {
  final value = parsePlistXml(source);
  if (value is! Map<String, Object?>) {
    throw FormatException('$label must contain a dictionary.');
  }
  return value;
}

Object? _parsePlistElement(XmlElement element) {
  switch (element.name.local) {
    case 'dict':
      final children = element.childElements.toList(growable: false);
      if (children.length.isOdd) {
        throw const FormatException('Plist dictionary is truncated.');
      }
      final values = <String, Object?>{};
      for (var index = 0; index < children.length; index += 2) {
        final keyElement = children[index];
        if (keyElement.name.local != 'key' ||
            keyElement.childElements.isNotEmpty) {
          throw const FormatException('Plist dictionary key is malformed.');
        }
        final key = keyElement.innerText;
        if (key.isEmpty || values.containsKey(key)) {
          throw const FormatException('Plist dictionary key is invalid.');
        }
        values[key] = _parsePlistElement(children[index + 1]);
      }
      return values;
    case 'array':
      return element.childElements
          .map<Object?>(_parsePlistElement)
          .toList(growable: false);
    case 'string':
    case 'date':
    case 'data':
      if (element.childElements.isNotEmpty) {
        throw const FormatException('Plist scalar is malformed.');
      }
      return element.innerText;
    case 'integer':
      final value = int.tryParse(element.innerText);
      if (value == null) {
        throw const FormatException('Plist integer is malformed.');
      }
      return value;
    case 'real':
      final value = double.tryParse(element.innerText);
      if (value == null || !value.isFinite) {
        throw const FormatException('Plist real is malformed.');
      }
      return value;
    case 'true':
      return true;
    case 'false':
      return false;
    default:
      throw FormatException('Unsupported plist value ${element.name.local}.');
  }
}

/// Measures a packaged app while rejecting links and special filesystem nodes.
Future<int> measureSafeIosAppDirectory(Directory directory) async {
  var bytes = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      bytes += await File(entity.path).length();
      if (bytes > maximumIosInstalledBytes) return bytes;
    } else if (type != FileSystemEntityType.directory) {
      throw const FormatException('Archived app contains a special file.');
    }
  }
  return bytes;
}

void _requireFile(File file, String label) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FormatException('$label is missing or unsafe.');
  }
}

void _requireDirectory(Directory directory, String label) {
  if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FormatException('$label is missing or unsafe.');
  }
}

_Options _parseArguments(List<String> arguments) {
  String? archive;
  var requireSigned = false;
  for (var index = 0; index < arguments.length; index += 1) {
    switch (arguments[index]) {
      case '--archive':
        if (archive != null || index + 1 >= arguments.length) {
          throw const FormatException('--archive requires one value.');
        }
        archive = arguments[++index];
      case '--require-signed':
        if (requireSigned) {
          throw const FormatException('--require-signed may appear once.');
        }
        requireSigned = true;
      default:
        throw FormatException('Unknown argument: ${arguments[index]}.');
    }
  }
  if (archive == null || archive.isEmpty) {
    throw const FormatException('--archive is required.');
  }
  return _Options(archive: archive, requireSigned: requireSigned);
}

final class _Options {
  const _Options({required this.archive, required this.requireSigned});

  final String archive;
  final bool requireSigned;
}
