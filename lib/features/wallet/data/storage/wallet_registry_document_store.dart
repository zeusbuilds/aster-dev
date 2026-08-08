import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../../core/errors/errors.dart';
import 'wallet_storage_security.dart';

/// Durable document boundary for the non-secret wallet registry.
abstract interface class WalletRegistryDocumentStore {
  Future<String?> read();
  Future<void> write(String document);
}

/// Crash-tolerant two-slot journal for critical wallet metadata.
///
/// Each write is flushed to a temporary file and atomically renamed over the
/// older slot. The other slot remains a valid rollback copy. Checksums detect
/// truncation and accidental corruption before registry JSON is decoded.
final class IoWalletRegistryDocumentStore
    implements WalletRegistryDocumentStore {
  const IoWalletRegistryDocumentStore(this.rootPath, this._security);

  static const _schemaVersion = 1;
  static const _maximumDocumentBytes = 512 * 1024;
  static const _maximumEnvelopeBytes = _maximumDocumentBytes + 4096;

  final String rootPath;
  final WalletStorageSecurity _security;

  @override
  Future<String?> read() async {
    final root = Directory(rootPath);
    if (!await root.exists()) return null;
    await _security.verifyDirectory(rootPath);
    final slots = await _readSlots();
    if (slots.isEmpty) return null;
    slots.sort((left, right) => right.generation.compareTo(left.generation));
    if (slots.length > 1 &&
        slots[0].generation == slots[1].generation &&
        slots[0].checksum != slots[1].checksum) {
      throw const StoredDataCorruptionException();
    }
    return slots.first.document;
  }

  @override
  Future<void> write(String document) async {
    final documentBytes = utf8.encode(document);
    if (documentBytes.isEmpty || documentBytes.length > _maximumDocumentBytes) {
      throw const StoredDataCorruptionException();
    }
    final root = Directory(rootPath);
    if (await root.exists()) {
      await _security.verifyDirectory(rootPath);
    } else {
      await _security.prepareRoot(rootPath);
    }
    final slots = await _readSlots();
    final currentGeneration = slots.fold<int>(
      -1,
      (current, slot) => slot.generation > current ? slot.generation : current,
    );
    if (currentGeneration >= _maximumSignedInteger) {
      throw const StoredDataCorruptionException();
    }
    final nextGeneration = currentGeneration + 1;
    final checksum = _checksum(nextGeneration, document);
    final envelope = jsonEncode({
      'schema': _schemaVersion,
      'generation': nextGeneration,
      'checksum': checksum,
      'document': document,
    });
    final target = _slot(nextGeneration.isEven ? 'a' : 'b');
    final failures = <Object>[];
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        await _security.replaceTextFile(target.path, envelope);
        final verified = await _readSlot(target);
        if (verified == null ||
            verified.generation != nextGeneration ||
            verified.checksum != checksum) {
          throw const StoredDataCorruptionException();
        }
        return;
      } catch (error, stackTrace) {
        failures.add(
          StorageOperationException(
            'walletRegistryCommit',
            cause: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
    throw DurableStorageCommitException(failures);
  }

  Future<List<_RegistrySlot>> _readSlots() async {
    final valid = <_RegistrySlot>[];
    var present = 0;
    for (final file in [_slot('a'), _slot('b')]) {
      if (!await file.exists()) continue;
      present += 1;
      await _security.verifyFile(file.path);
      final slot = await _readSlot(file);
      if (slot != null) valid.add(slot);
    }
    if (present > 0 && valid.isEmpty) {
      throw const StoredDataCorruptionException();
    }
    return valid;
  }

  Future<_RegistrySlot?> _readSlot(File file) async {
    try {
      final length = await file.length();
      if (length < 1 || length > _maximumEnvelopeBytes) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?> ||
          decoded['schema'] != _schemaVersion) {
        return null;
      }
      final generation = decoded['generation'];
      final checksum = decoded['checksum'];
      final document = decoded['document'];
      if (generation is! int ||
          generation < 0 ||
          checksum is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum) ||
          document is! String ||
          utf8.encode(document).length > _maximumDocumentBytes ||
          _checksum(generation, document) != checksum) {
        return null;
      }
      return _RegistrySlot(
        generation: generation,
        checksum: checksum,
        document: document,
      );
    } on FormatException {
      return null;
    }
  }

  File _slot(String suffix) => File(
    '${Directory(rootPath).path}${Platform.pathSeparator}'
    'wallet_registry.$suffix.json',
  );

  static String _checksum(int generation, String document) => sha256
      .convert(utf8.encode('$_schemaVersion\n$generation\n$document'))
      .toString();
}

final class _RegistrySlot {
  const _RegistrySlot({
    required this.generation,
    required this.checksum,
    required this.document,
  });

  final int generation;
  final String checksum;
  final String document;
}

const _maximumSignedInteger = 0x7fffffffffffffff;
