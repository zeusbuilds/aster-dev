import 'package:xml/xml.dart';

const _gradleVerificationNamespace =
    'https://schema.gradle.org/dependency-verification';

/// Strict, immutable Gradle artifact-checksum catalog.
final class GradleVerificationMetadata {
  const GradleVerificationMetadata._(this._checksums);

  final Map<String, String> _checksums;

  /// Number of uniquely identified artifacts in the catalog.
  int get artifactCount => _checksums.length;

  /// Returns the one reviewed SHA-256 for an exact artifact coordinate.
  String? checksumFor({
    required String group,
    required String module,
    required String version,
    required String artifactName,
  }) => _checksums[_artifactKey(group, module, version, artifactName)];
}

/// Result of parsing one Gradle verification-metadata document.
final class GradleVerificationMetadataParseResult {
  const GradleVerificationMetadataParseResult({
    required this.metadata,
    required this.failures,
  });

  /// Parsed catalog, or `null` when the document root cannot be trusted.
  final GradleVerificationMetadata? metadata;

  /// Deterministically ordered structural or checksum-policy failures.
  final List<String> failures;

  /// Whether [metadata] is complete and policy-valid.
  bool get passed => metadata != null && failures.isEmpty;
}

/// Parses Gradle dependency verification metadata without filesystem access.
GradleVerificationMetadataParseResult parseGradleVerificationMetadata(
  String contents,
) {
  final failures = <String>[];
  try {
    final document = XmlDocument.parse(contents);
    final root = document.rootElement;
    if (root.name.local != 'verification-metadata' ||
        root.name.namespaceUri != _gradleVerificationNamespace) {
      return const GradleVerificationMetadataParseResult(
        metadata: null,
        failures: ['Gradle verification metadata has an invalid root.'],
      );
    }

    final rootChildren = root.childElements.toList();
    final configurations = rootChildren
        .where(
          (element) =>
              element.name.local == 'configuration' &&
              element.name.namespaceUri == _gradleVerificationNamespace,
        )
        .toList();
    final componentContainers = rootChildren
        .where(
          (element) =>
              element.name.local == 'components' &&
              element.name.namespaceUri == _gradleVerificationNamespace,
        )
        .toList();
    if (rootChildren.length != 2 ||
        configurations.length != 1 ||
        componentContainers.length != 1) {
      return const GradleVerificationMetadataParseResult(
        metadata: null,
        failures: [
          'Gradle verification metadata must contain one configuration and one components container.',
        ],
      );
    }

    _validateConfiguration(configurations.single, failures);
    final checksums = _readComponents(componentContainers.single, failures);
    if (checksums.isEmpty) {
      failures.add('Gradle verification metadata contains no artifacts.');
    }
    final uniqueFailures = failures.toSet().toList()..sort();
    return GradleVerificationMetadataParseResult(
      metadata: GradleVerificationMetadata._(
        Map<String, String>.unmodifiable(checksums),
      ),
      failures: List<String>.unmodifiable(uniqueFailures),
    );
  } on XmlParserException {
    return const GradleVerificationMetadataParseResult(
      metadata: null,
      failures: ['Gradle verification metadata is malformed XML.'],
    );
  }
}

void _validateConfiguration(XmlElement configuration, List<String> failures) {
  final options = <String, String>{};
  for (final option in configuration.childElements) {
    if (option.name.namespaceUri != _gradleVerificationNamespace) {
      failures.add('Gradle verification contains a foreign option.');
      continue;
    }
    final name = option.name.local;
    if (options.containsKey(name)) {
      failures.add('Gradle verification option $name is duplicated.');
      continue;
    }
    options[name] = option.innerText.trim();
  }
  if (options.length != 2 ||
      options['verify-metadata'] != 'true' ||
      options['verify-signatures'] != 'false') {
    failures.add(
      'Gradle dependency verification must use strict metadata SHA-256 '
      'checks without broad trust exceptions.',
    );
  }
}

Map<String, String> _readComponents(
  XmlElement container,
  List<String> failures,
) {
  final checksums = <String, String>{};
  final componentKeys = <String>{};
  for (final component in container.childElements) {
    if (component.name.local != 'component' ||
        component.name.namespaceUri != _gradleVerificationNamespace) {
      failures.add('Gradle components contain an unexpected element.');
      continue;
    }
    final group = component.getAttribute('group');
    final module = component.getAttribute('name');
    final version = component.getAttribute('version');
    if ([
      group,
      module,
      version,
    ].any((value) => value == null || value.isEmpty)) {
      failures.add('Gradle verification contains an unidentifiable component.');
      continue;
    }
    final componentKey = '$group:$module:$version';
    if (!componentKeys.add(componentKey)) {
      failures.add('Gradle verification duplicates $componentKey.');
    }

    final artifactNames = <String>{};
    final artifacts = component.childElements.toList();
    if (artifacts.isEmpty) {
      failures.add('Gradle verification component $componentKey is empty.');
    }
    for (final artifact in artifacts) {
      if (artifact.name.local != 'artifact' ||
          artifact.name.namespaceUri != _gradleVerificationNamespace) {
        failures.add('$componentKey contains an unexpected element.');
        continue;
      }
      final artifactName = artifact.getAttribute('name');
      if (artifactName == null || artifactName.isEmpty) {
        failures.add('$componentKey contains an unnamed artifact.');
        continue;
      }
      if (!artifactNames.add(artifactName)) {
        failures.add('$componentKey duplicates artifact $artifactName.');
      }
      final artifactChecksums = artifact.childElements.toList();
      if (artifactChecksums.length != 1 ||
          artifactChecksums.single.name.local != 'sha256' ||
          artifactChecksums.single.name.namespaceUri !=
              _gradleVerificationNamespace) {
        failures.add(
          '$componentKey:$artifactName must use exactly one SHA-256 checksum.',
        );
        continue;
      }
      final checksum = artifactChecksums.single.getAttribute('value');
      if (checksum == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
        failures.add(
          '$componentKey:$artifactName has an invalid SHA-256 checksum.',
        );
        continue;
      }
      final key = _artifactKey(group!, module!, version!, artifactName);
      if (checksums.containsKey(key)) {
        failures.add('Gradle verification duplicates $key.');
        continue;
      }
      checksums[key] = checksum;
    }
  }
  return checksums;
}

String _artifactKey(
  String group,
  String module,
  String version,
  String artifactName,
) => '$group:$module:$version:$artifactName';
