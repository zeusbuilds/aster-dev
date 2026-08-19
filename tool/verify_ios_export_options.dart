import 'dart:io';

import 'bounded_process.dart';
import 'release_configuration_manifest.dart';
import 'verify_android_release_identity.dart';
import 'verify_ios_release_archive.dart';

const _maximumExportOptionsBytes = 1024 * 1024;
const _maximumDiagnosticsBytes = 2 * 1024 * 1024;
const _plistTimeout = Duration(minutes: 1);

/// Validates the release-owned Xcode export policy before archive export.
void validateIosExportOptions(
  Map<String, Object?> options, {
  required ReleaseAudience audience,
  required String expectedBundleIdentifier,
}) {
  final unknown = options.keys.toSet().difference(_allowedKeys);
  if (unknown.isNotEmpty) {
    throw FormatException(
      'Export options contain unreviewed keys: '
      '${(unknown.toList()..sort()).join(', ')}.',
    );
  }

  final method = options['method'];
  if (method is! String || !_allMethods.contains(method)) {
    throw const FormatException('Export options method is missing or invalid.');
  }
  if (audience == ReleaseAudience.publicDistribution &&
      !_appStoreMethods.contains(method)) {
    throw const FormatException(
      'Public distribution requires an App Store Connect export method.',
    );
  }

  final teamId = options['teamID'];
  if (teamId is! String || !RegExp(r'^[A-Z0-9]{10}$').hasMatch(teamId)) {
    throw const FormatException(
      'Export options require a valid Apple team ID.',
    );
  }
  if (options['distributionBundleIdentifier'] != expectedBundleIdentifier) {
    throw const FormatException(
      'Export options must bind the committed application identifier.',
    );
  }
  final destination = options['destination'];
  if (destination != null && destination != 'export') {
    throw const FormatException(
      'The owned IPA target requires destination=export.',
    );
  }
  if (options['manageAppVersionAndBuildNumber'] != false) {
    throw const FormatException(
      'Export options must preserve the committed version and build number.',
    );
  }

  final signingStyle = options['signingStyle'] ?? 'automatic';
  if (signingStyle != 'automatic' && signingStyle != 'manual') {
    throw const FormatException('Export signingStyle is invalid.');
  }
  if (signingStyle == 'manual') {
    final profiles = options['provisioningProfiles'];
    if (profiles is! Map<String, Object?> ||
        profiles.length != 1 ||
        profiles[expectedBundleIdentifier] is! String ||
        (profiles[expectedBundleIdentifier]! as String).isEmpty) {
      throw const FormatException(
        'Manual signing requires the application provisioning profile.',
      );
    }
  } else if (options.containsKey('provisioningProfiles')) {
    throw const FormatException(
      'Automatic signing must not carry manual provisioning profiles.',
    );
  }

  _validatePropertyListValues(options, depth: 0);
}

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final file = File(options.file).absolute;
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException(
        'Export options must be a regular non-symlink file.',
      );
    }
    if (await file.length() > _maximumExportOptionsBytes) {
      throw const FormatException('Export options are too large.');
    }
    final converted = await runBoundedProcess(
      '/usr/bin/plutil',
      ['-convert', 'xml1', '-o', '-', file.path],
      maxStdoutBytes: _maximumExportOptionsBytes,
      maxStderrBytes: _maximumDiagnosticsBytes,
      timeout: _plistTimeout,
    );
    if (converted.exitCode != 0) {
      throw StateError('plutil exited ${converted.exitCode}.');
    }
    final value = parsePlistXml(converted.stdout);
    if (value is! Map<String, Object?>) {
      throw const FormatException('Export options must contain a dictionary.');
    }

    final root = Directory.current.absolute;
    final identity = parseExpectedAndroidReleaseIdentity(
      pubspec: File('${root.path}/pubspec.yaml').readAsStringSync(),
      gradleProperties: File('${root.path}/android/gradle.properties')
          .readAsStringSync(),
    );
    validateIosExportOptions(
      value,
      audience: options.audience,
      expectedBundleIdentifier: identity.applicationId,
    );
    stdout.writeln(
      'Verified ${options.audience.name} iOS export policy for '
      '${identity.applicationId}.',
    );
  } on Object catch (error) {
    stderr.writeln('iOS export-options check failed: $error');
    exitCode = 1;
  }
}

void _validatePropertyListValues(Object? value, {required int depth}) {
  if (depth > 8) {
    throw const FormatException('Export options are nested too deeply.');
  }
  switch (value) {
    case final Map<Object?, Object?> values:
      for (final entry in values.entries) {
        if (entry.key is! String || (entry.key! as String).length > 256) {
          throw const FormatException('Export option key is malformed.');
        }
        _validatePropertyListValues(entry.value, depth: depth + 1);
      }
    case final List<Object?> values:
      if (values.length > 256) {
        throw const FormatException('Export option list is too large.');
      }
      for (final entry in values) {
        _validatePropertyListValues(entry, depth: depth + 1);
      }
    case final String text:
      if (text.isEmpty || text.length > 2048 || text.contains('\u0000')) {
        throw const FormatException('Export option string is malformed.');
      }
    case bool() || int() || double():
      return;
    default:
      throw const FormatException('Export option value type is unsupported.');
  }
}

_Options _parseArguments(List<String> arguments) {
  String? file;
  ReleaseAudience? audience;
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if ((argument == '--file' || argument == '--audience') &&
        index + 1 >= arguments.length) {
      throw FormatException('$argument requires a value.');
    }
    switch (argument) {
      case '--file':
        if (file != null) {
          throw const FormatException('--file may be supplied only once.');
        }
        file = arguments[++index];
      case '--audience':
        if (audience != null) {
          throw const FormatException('--audience may be supplied only once.');
        }
        audience = parseReleaseAudience(arguments[++index]);
      default:
        throw FormatException('Unknown argument: $argument.');
    }
  }
  if (file == null || file.isEmpty || audience == null) {
    throw const FormatException('--file and --audience are required.');
  }
  return _Options(file: file, audience: audience);
}

final class _Options {
  const _Options({required this.file, required this.audience});

  final String file;
  final ReleaseAudience audience;
}

const _appStoreMethods = <String>{'app-store', 'app-store-connect'};
const _allMethods = <String>{
  ..._appStoreMethods,
  'ad-hoc',
  'development',
  'enterprise',
  'release-testing',
};
const _allowedKeys = <String>{
  'compileBitcode',
  'destination',
  'distributionBundleIdentifier',
  'embedOnDemandResourcesAssetPacksInBundle',
  'generateAppStoreInformation',
  'iCloudContainerEnvironment',
  'installerSigningCertificate',
  'manageAppVersionAndBuildNumber',
  'manifest',
  'method',
  'onDemandResourcesAssetPacksBaseURL',
  'provisioningProfiles',
  'signingCertificate',
  'signingStyle',
  'stripSwiftSymbols',
  'teamID',
  'thinning',
  'uploadBitcode',
  'uploadSymbols',
};
