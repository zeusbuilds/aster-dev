import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'release_configuration_manifest.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final path = options.file;
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException(
        'Release configuration must be a regular non-symlink file.',
      );
    }
    final bytes = await readBoundedReleaseConfiguration(File(path));
    final source = utf8.decode(bytes, allowMalformed: false);
    final manifest = ReleaseConfigurationManifest.parse(
      source,
      audience: options.audience,
    );
    stdout.writeln(
      'Verified ${manifest.audience.name} release configuration with '
      '${manifest.values.length} non-secret keys '
      '(SHA-256 ${sha256.convert(bytes)}).',
    );
  } on Object catch (error) {
    stderr.writeln('Release configuration check failed: $error');
    exitCode = 1;
  }
}

/// Reads at most the manifest contract's byte limit plus one sentinel byte.
///
/// A size check after `readAsBytes` does not bound memory use. Streaming only
/// the accepted prefix makes the command fail predictably even when the input
/// is unexpectedly large.
Future<Uint8List> readBoundedReleaseConfiguration(File file) async {
  final output = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in file.openRead(
    0,
    maximumReleaseConfigurationBytes + 1,
  )) {
    length += chunk.length;
    if (length > maximumReleaseConfigurationBytes) {
      throw const FormatException('Release configuration is too large.');
    }
    output.add(chunk);
  }
  return output.takeBytes();
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
