import 'dart:io';

import 'package:archive/archive.dart';
import 'package:posix/posix.dart';

import 'release_artifact_policy.dart';
import 'verify_ios_release_archive.dart';

const _maximumIpaEntries = 50000;
const _maximumExpandedIpaBytes = 1024 * 1024 * 1024;

/// Filesystem metadata used to validate an IPA before any entry is extracted.
final class IosIpaEntryMetadata {
  const IosIpaEntryMetadata({
    required this.name,
    required this.size,
    required this.mode,
    required this.isFile,
    required this.isDirectory,
    required this.isSymbolicLink,
  });

  final String name;
  final int size;
  final int mode;
  final bool isFile;
  final bool isDirectory;
  final bool isSymbolicLink;
}

/// Validates archive ownership and returns the single packaged app path.
///
/// This preflight rejects traversal, links, special nodes, case-folding
/// collisions, duplicate entries, excessive expansion, and ambiguous Payload
/// layouts before any entry is allowed to touch the filesystem.
String validateIosIpaLayout(Iterable<IosIpaEntryMetadata> entries) {
  final exactNames = <String>{};
  final foldedNames = <String>{};
  final appPaths = <String>{};
  var entryCount = 0;
  var expandedBytes = BigInt.zero;

  for (final entry in entries) {
    entryCount += 1;
    if (entryCount > _maximumIpaEntries) {
      throw const FormatException('IPA contains too many entries.');
    }
    final canonicalName = _canonicalIpaEntryName(entry);
    if (!exactNames.add(canonicalName) ||
        !foldedNames.add(canonicalName.toLowerCase())) {
      throw const FormatException('IPA contains colliding archive paths.');
    }
    if (entry.isSymbolicLink) {
      throw const FormatException('IPA must not contain symbolic links.');
    }
    if (entry.isFile == entry.isDirectory) {
      throw const FormatException('IPA contains an unsupported archive node.');
    }
    final fileType = entry.mode & 0xf000;
    if (fileType != 0 &&
        ((entry.isFile && fileType != 0x8000) ||
            (entry.isDirectory && fileType != 0x4000))) {
      throw const FormatException('IPA contains a special filesystem node.');
    }
    if (entry.size < 0 || (entry.isDirectory && entry.size != 0)) {
      throw const FormatException('IPA entry size is malformed.');
    }
    expandedBytes += BigInt.from(entry.size);
    if (expandedBytes > BigInt.from(_maximumExpandedIpaBytes)) {
      throw const FormatException('IPA expanded size exceeds its safety cap.');
    }

    final segments = canonicalName.split('/');
    if (segments.first != 'Payload') continue;
    if (segments.length == 1) {
      if (!entry.isDirectory) {
        throw const FormatException('IPA Payload root must be a directory.');
      }
      continue;
    }
    final appName = segments[1];
    if (!appName.endsWith('.app') || appName == '.app') {
      throw const FormatException(
        'Every Payload entry must belong to one application bundle.',
      );
    }
    appPaths.add('Payload/$appName');
  }

  if (entryCount == 0 || appPaths.length != 1) {
    throw const FormatException('IPA must contain exactly one application.');
  }
  return appPaths.single;
}

Future<void> main(List<String> arguments) async {
  Directory? extractionDirectory;
  try {
    if (arguments.length != 2 || arguments.first != '--directory') {
      throw const FormatException('--directory requires one value.');
    }
    final directory = Directory(arguments[1]).absolute;
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('iOS export directory is missing or unsafe.');
    }
    final packages = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.ipa'))
        .toList(growable: false);
    if (packages.length != 1) {
      throw const FormatException(
        'iOS export directory must contain exactly one IPA.',
      );
    }
    final package = packages.single.absolute;
    final measurement = await measureReleaseArtifact(
      package,
      ReleaseArtifactKind.iosIpa,
    );
    extractionDirectory = await Directory.systemTemp.createTemp(
      'aster-ipa-verification-',
    );
    final appRelativePath = extractValidatedIosIpa(
      package,
      extractionDirectory,
    );

    final repository = Directory.current.absolute;
    final appMeasurement = await verifyIosReleaseApplication(
      repository: repository,
      app: Directory('${extractionDirectory.path}/$appRelativePath'),
      expected: expectedIosReleaseIdentity(repository),
      requireSigned: true,
    );
    final finalMeasurement = await measureReleaseArtifact(
      package,
      ReleaseArtifactKind.iosIpa,
    );
    if (finalMeasurement.bytes != measurement.bytes ||
        finalMeasurement.sha256 != measurement.sha256) {
      throw const FormatException('IPA changed while it was being verified.');
    }
    stdout.writeln(
      'Verified signed iOS IPA ${appMeasurement.identity.bundleIdentifier} '
      '${appMeasurement.identity.versionName}+'
      '${appMeasurement.identity.buildNumber}; package size '
      '${measurement.bytes} bytes; installed size '
      '${appMeasurement.installedBytes} bytes; IPA SHA-256 '
      '${measurement.sha256}; executable SHA-256 '
      '${appMeasurement.executableSha256}.',
    );
  } on Object catch (error) {
    stderr.writeln('iOS release export check failed: $error');
    exitCode = 1;
  } finally {
    final owned = extractionDirectory;
    if (owned != null && owned.existsSync()) {
      try {
        await owned.delete(recursive: true);
      } on Object catch (error) {
        stderr.writeln('iOS release export cleanup failed: $error');
        exitCode = 1;
      }
    }
  }
}

/// Preflights and extracts one IPA into an empty caller-owned directory.
///
/// Validation and decompression use the same open archive handle. Every file
/// is bounded to its declared size, and links, special nodes, colliding paths,
/// and traversal are rejected before the first output file is created.
String extractValidatedIosIpa(File package, Directory destination) {
  if (FileSystemEntity.typeSync(destination.path, followLinks: false) !=
          FileSystemEntityType.directory ||
      destination.listSync(followLinks: false).isNotEmpty) {
    throw const FormatException(
      'IPA extraction destination must be an empty owned directory.',
    );
  }
  final opened = _openAndValidateIpa(package);
  try {
    _extractValidatedIpa(opened, destination);
    return opened.appRelativePath;
  } finally {
    opened.close();
  }
}

_OpenedIpa _openAndValidateIpa(File package) {
  final input = InputFileStream(package.path);
  Archive? archive;
  final entries = <IosIpaEntryMetadata>[];
  try {
    archive = ZipDecoder().decodeStream(
      input,
      callback: (entry) {
        entries.add(
          IosIpaEntryMetadata(
            name: entry.name,
            size: entry.size,
            mode: entry.mode,
            isFile: entry.isFile,
            isDirectory: entry.isDirectory,
            isSymbolicLink: entry.isSymbolicLink,
          ),
        );
      },
    );
    return _OpenedIpa(
      input: input,
      archive: archive,
      appRelativePath: validateIosIpaLayout(entries),
    );
  } on Object catch (error) {
    for (final entry in archive?.files ?? const <ArchiveFile>[]) {
      entry.closeSync();
    }
    input.closeSync();
    if (error is ArchiveException) {
      throw FormatException('IPA archive structure is malformed: $error');
    }
    rethrow;
  }
}

void _extractValidatedIpa(_OpenedIpa opened, Directory destination) {
  final directoryModes = <String, int>{};
  for (final entry in opened.archive.files) {
    final relative = entry.name.endsWith('/')
        ? entry.name.substring(0, entry.name.length - 1)
        : entry.name;
    final outputPath = '${destination.path}/$relative';
    if (entry.isDirectory) {
      Directory(outputPath).createSync(recursive: true);
      directoryModes[outputPath] = entry.unixPermissions;
      continue;
    }
    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    final stream = _BoundedOutputFileStream(outputPath, entry.size);
    try {
      entry.writeContent(stream);
    } finally {
      stream.closeSync();
    }
    if (stream.length != entry.size || output.lengthSync() != entry.size) {
      throw const FormatException('IPA entry expanded to an unexpected size.');
    }
    final expectedCrc32 = entry.crc32;
    if (expectedCrc32 == null || stream.crc32 != expectedCrc32) {
      throw const FormatException('IPA entry checksum is invalid.');
    }
    final permissions = entry.unixPermissions;
    if (permissions != 0) chmodWithMode(outputPath, permissions);
  }
  final directories = directoryModes.keys.toList(growable: false)
    ..sort((left, right) => right.length.compareTo(left.length));
  for (final path in directories) {
    final permissions = directoryModes[path]!;
    if (permissions != 0) chmodWithMode(path, permissions);
  }
}

String _canonicalIpaEntryName(IosIpaEntryMetadata entry) {
  final raw = entry.name;
  if (raw.isEmpty ||
      raw.length > 2048 ||
      raw.startsWith('/') ||
      raw.contains('\\') ||
      raw.contains(':') ||
      raw.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e)) {
    throw const FormatException('IPA contains an unsafe archive path.');
  }
  final name = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  if (name.isEmpty ||
      name.endsWith('/') ||
      entry.isDirectory != raw.endsWith('/')) {
    throw const FormatException('IPA archive path type is inconsistent.');
  }
  final segments = name.split('/');
  if (segments.any(
    (segment) =>
        segment.isEmpty ||
        segment != segment.trim() ||
        segment == '.' ||
        segment == '..',
  )) {
    throw const FormatException('IPA contains path traversal.');
  }
  return name;
}

final class _OpenedIpa {
  const _OpenedIpa({
    required this.input,
    required this.archive,
    required this.appRelativePath,
  });

  final InputFileStream input;
  final Archive archive;
  final String appRelativePath;

  void close() {
    for (final entry in archive.files) {
      entry.closeSync();
    }
    input.closeSync();
  }
}

final class _BoundedOutputFileStream extends OutputFileStream {
  _BoundedOutputFileStream(String path, this.maximumBytes)
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));

  final int maximumBytes;
  var _crc32 = 0xffffffff;

  int get crc32 => _crc32 ^ 0xffffffff;

  @override
  void writeByte(int value) {
    _requireCapacity(1);
    _crc32 = getCrc32Byte(_crc32, value);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (count < 0 || count > bytes.length) {
      throw const FormatException('IPA decoder emitted an invalid byte count.');
    }
    _requireCapacity(count);
    for (var index = 0; index < count; index += 1) {
      _crc32 = getCrc32Byte(_crc32, bytes[index]);
    }
    super.writeBytes(bytes, length: count);
  }

  void _requireCapacity(int additionalBytes) {
    if (additionalBytes > maximumBytes - length) {
      throw const FormatException('IPA entry exceeded its declared size.');
    }
  }
}
