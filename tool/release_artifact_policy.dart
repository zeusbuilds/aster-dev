import 'dart:io';

import 'package:crypto/crypto.dart';

/// Release artifact classes with independent regression budgets.
enum ReleaseArtifactKind {
  /// Google Play Android App Bundle.
  androidBundle(maximumBytes: 170 * 1024 * 1024),

  /// One ABI-specific directly distributed Android package.
  androidSplitApk(maximumBytes: 140 * 1024 * 1024),

  /// Signed iOS App Store package.
  iosIpa(maximumBytes: 250 * 1024 * 1024);

  const ReleaseArtifactKind({required this.maximumBytes});

  /// Hard candidate-size ceiling derived from the current reviewed baseline.
  final int maximumBytes;
}

/// Size and content identity of one verified release artifact.
final class ReleaseArtifactMeasurement {
  const ReleaseArtifactMeasurement({required this.bytes, required this.sha256});

  final int bytes;
  final String sha256;
}

/// Measures one regular non-symlink artifact and enforces [kind]'s budget.
Future<ReleaseArtifactMeasurement> measureReleaseArtifact(
  File file,
  ReleaseArtifactKind kind,
) async {
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (type != FileSystemEntityType.file) {
    throw const FormatException(
      'Release artifact must be a regular non-symlink file.',
    );
  }
  final bytes = await file.length();
  if (bytes <= 0) {
    throw const FormatException('Release artifact must not be empty.');
  }
  if (bytes > kind.maximumBytes) {
    throw FormatException(
      '${kind.name} is $bytes bytes, above its ${kind.maximumBytes}-byte budget.',
    );
  }
  final digest = await sha256.bind(file.openRead()).first;
  return ReleaseArtifactMeasurement(bytes: bytes, sha256: '$digest');
}
