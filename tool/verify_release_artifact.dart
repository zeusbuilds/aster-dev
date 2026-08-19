import 'dart:io';

import 'release_artifact_policy.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseArguments(arguments);
    final measurement = await measureReleaseArtifact(
      File(options.file),
      options.kind,
    );
    stdout.writeln(
      'Verified ${options.kind.name} size ${measurement.bytes} bytes '
      '(SHA-256 ${measurement.sha256}).',
    );
  } on Object catch (error) {
    stderr.writeln('Release artifact check failed: $error');
    exitCode = 1;
  }
}

_Options _parseArguments(List<String> arguments) {
  String? file;
  ReleaseArtifactKind? kind;
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if ((argument == '--file' || argument == '--kind') &&
        index + 1 >= arguments.length) {
      throw FormatException('$argument requires a value.');
    }
    switch (argument) {
      case '--file':
        if (file != null) {
          throw const FormatException('--file may be supplied only once.');
        }
        file = arguments[++index];
      case '--kind':
        if (kind != null) {
          throw const FormatException('--kind may be supplied only once.');
        }
        kind = switch (arguments[++index]) {
          'android-bundle' => ReleaseArtifactKind.androidBundle,
          'android-split-apk' => ReleaseArtifactKind.androidSplitApk,
          'ios-ipa' => ReleaseArtifactKind.iosIpa,
          _ => throw const FormatException('Unknown release artifact kind.'),
        };
      default:
        throw FormatException('Unknown argument: $argument.');
    }
  }
  if (file == null || file.isEmpty || kind == null) {
    throw const FormatException('--file and --kind are required.');
  }
  return _Options(file: file, kind: kind);
}

final class _Options {
  const _Options({required this.file, required this.kind});

  final String file;
  final ReleaseArtifactKind kind;
}
