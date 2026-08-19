import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_artifact_policy.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'aster-release-artifact-',
    );
  });

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('measures a non-empty regular artifact with stable SHA-256', () async {
    final artifact = File('${temporaryDirectory.path}/candidate.aab')
      ..writeAsBytesSync(const [0x41, 0x73, 0x74, 0x65, 0x72]);

    final measurement = await measureReleaseArtifact(
      artifact,
      ReleaseArtifactKind.androidBundle,
    );

    expect(measurement.bytes, 5);
    expect(
      measurement.sha256,
      '83feda83d88cc8975ce4cf859af756b4b5b3f75db31a41970ba4946add70bb47',
    );
  });

  test('rejects missing, empty, and symlink artifacts', () async {
    final missing = File('${temporaryDirectory.path}/missing.aab');
    await expectLater(
      measureReleaseArtifact(missing, ReleaseArtifactKind.androidBundle),
      throwsA(isA<FormatException>()),
    );

    final empty = File('${temporaryDirectory.path}/empty.aab')..createSync();
    await expectLater(
      measureReleaseArtifact(empty, ReleaseArtifactKind.androidBundle),
      throwsA(isA<FormatException>()),
    );

    if (!Platform.isWindows) {
      final target = File('${temporaryDirectory.path}/target.aab')
        ..writeAsStringSync('candidate');
      final link = Link('${temporaryDirectory.path}/linked.aab')
        ..createSync(target.path);
      await expectLater(
        measureReleaseArtifact(
          File(link.path),
          ReleaseArtifactKind.androidBundle,
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('rejects an artifact above its class budget', () async {
    final artifact = File('${temporaryDirectory.path}/candidate.apk');
    final handle = artifact.openSync(mode: FileMode.write);
    handle.truncateSync(ReleaseArtifactKind.androidSplitApk.maximumBytes + 1);
    handle.closeSync();

    await expectLater(
      measureReleaseArtifact(artifact, ReleaseArtifactKind.androidSplitApk),
      throwsA(isA<FormatException>()),
    );
  });
}
