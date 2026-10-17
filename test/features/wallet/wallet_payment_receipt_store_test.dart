import 'dart:io';

import 'package:aster/core/errors/errors.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/wallet_fakes.dart';

const _wallet = '11111111111111111111111111111111';
const _otherWallet = '22222222222222222222222222222222';
final _firstKey = 'a' * 64;
final _secondKey = 'b' * 64;

void main() {
  test(
    'fresh archive creates each secure directory before its child',
    () async {
      final parent = await _temporaryRoot();
      final root = '${parent.path}/receipts';
      final security = _SingleLevelStorageSecurity();
      final store = IoWalletPaymentReceiptStore(root, security);
      await store.writeReceipt(_wallet, _firstKey, '{"receipt":1}');
      expect(security.preparedRoots, [
        root,
        '$root/$_wallet',
        '$root/$_wallet/$_firstKey',
      ]);
      expect(
        await IoWalletPaymentReceiptStore(root, security).readAll(_wallet),
        {_firstKey: '{"receipt":1}'},
      );
    },
  );

  test('receipt archive retains separate keys across restart and wallet boundaries', () async {
    final root = await _temporaryRoot();
    final security = _SingleLevelStorageSecurity();
    final store = IoWalletPaymentReceiptStore(root.path, security);
    expect(await store.readAll(_wallet), isEmpty);
    await store.writeReceipt(_wallet, _firstKey, '{"receipt":1}');
    await store.writeReceipt(_wallet, _secondKey, '{"receipt":2}');
    await store.writeReceipt(_otherWallet, _firstKey, '{"receipt":3}');

    final restarted = IoWalletPaymentReceiptStore(root.path, security);
    final receipts = await restarted.readAll(_wallet);
    expect(receipts, {_firstKey: '{"receipt":1}', _secondKey: '{"receipt":2}'});
    expect(await restarted.readAll(_otherWallet), {_firstKey: '{"receipt":3}'});
    expect(security.replacedFiles, hasLength(3));
    expect(() => receipts[_firstKey] = 'changed', throwsUnsupportedError);
  });

  test(
    'same receipt is idempotent but conflicting bytes cannot replace it',
    () async {
      final root = await _temporaryRoot();
      final security = _SingleLevelStorageSecurity();
      final store = IoWalletPaymentReceiptStore(root.path, security);
      await store.writeReceipt(_wallet, _firstKey, '{"receipt":1}');
      final writes = List<String>.of(security.replacedFiles);
      await IoWalletPaymentReceiptStore(
        root.path,
        security,
      ).writeReceipt(_wallet, _firstKey, '{"receipt":1}');
      expect(security.replacedFiles, writes);
      await expectLater(
        store.writeReceipt(_wallet, _firstKey, '{"receipt":2}'),
        throwsA(isA<StoredDataCorruptionException>()),
      );
      expect(await store.readAll(_wallet), {_firstKey: '{"receipt":1}'});
      expect(security.replacedFiles, writes);
    },
  );

  for (final slot in ['a', 'b']) {
    test(
      'a present corrupt $slot slot blocks archive reads and idempotent writes',
      () async {
        final root = await _temporaryRoot();
        final security = _SingleLevelStorageSecurity();
        final store = IoWalletPaymentReceiptStore(root.path, security);
        await store.writeReceipt(_wallet, _firstKey, '{"receipt":1}');
        final path =
            '${root.path}/$_wallet/$_firstKey/wallet_registry.$slot.json';
        await File(path).writeAsString('{truncated', flush: true);
        final restarted = IoWalletPaymentReceiptStore(root.path, security);
        await expectLater(
          restarted.readAll(_wallet),
          throwsA(isA<StoredDataCorruptionException>()),
        );
        await expectLater(
          restarted.writeReceipt(_wallet, _firstKey, '{"receipt":1}'),
          throwsA(isA<StoredDataCorruptionException>()),
        );
        expect(await File(path).readAsString(), '{truncated');
      },
    );
  }

  test(
    'invalid wallet identities are rejected before touching the archive',
    () async {
      final root = await _temporaryRoot();
      final security = _SingleLevelStorageSecurity();
      final store = IoWalletPaymentReceiptStore(root.path, security);
      for (final walletId in [
        '',
        '../escape',
        'a' * 31,
        'A' * 32,
        '$_wallet/child',
      ]) {
        await expectLater(
          store.readAll(walletId),
          throwsA(isA<StoredDataCorruptionException>()),
        );
        await expectLater(
          store.writeReceipt(walletId, _firstKey, 'receipt'),
          throwsA(isA<StoredDataCorruptionException>()),
        );
      }
      expect(security.preparedRoots, isEmpty);
      expect(await root.list().toList(), isEmpty);
    },
  );

  test(
    'invalid receipt keys cannot create files or escape the wallet',
    () async {
      final root = await _temporaryRoot();
      final security = _SingleLevelStorageSecurity();
      final store = IoWalletPaymentReceiptStore(root.path, security);
      for (final key in [
        '',
        '../escape',
        'a' * 63,
        'A' * 64,
        '$_firstKey/child',
      ]) {
        await expectLater(
          store.writeReceipt(_wallet, key, 'receipt'),
          throwsA(isA<StoredDataCorruptionException>()),
        );
      }
      expect(security.preparedRoots, isEmpty);
      expect(await root.list().toList(), isEmpty);
    },
  );

  test(
    'unexpected archive entries fail closed instead of being skipped',
    () async {
      final root = await _temporaryRoot();
      final store = IoWalletPaymentReceiptStore(
        root.path,
        _SingleLevelStorageSecurity(),
      );
      await store.writeReceipt(_wallet, _firstKey, '{"receipt":1}');
      await File('${root.path}/$_wallet/unexpected.txt')
          .writeAsString('unexpected');
      await expectLater(
        store.readAll(_wallet),
        throwsA(isA<StoredDataCorruptionException>()),
      );
    },
  );

  for (final component in ['root', 'wallet', 'receipt']) {
    test(
      '$component symlink cannot redirect receipt reads or writes',
      () async {
        final parent = await _temporaryRoot();
        final rootPath = '${parent.path}/receipts';
        final outside = await Directory('${parent.path}/outside').create();
        final linkPath = switch (component) {
          'root' => rootPath,
          'wallet' => '$rootPath/$_wallet',
          _ => '$rootPath/$_wallet/$_firstKey',
        };
        await Directory(File(linkPath).parent.path).create(recursive: true);
        await Link(linkPath).create(outside.path);
        final store = IoWalletPaymentReceiptStore(
          rootPath,
          _SingleLevelStorageSecurity(),
        );
        await expectLater(
          store.readAll(_wallet),
          throwsA(isA<StoredDataCorruptionException>()),
        );
        await expectLater(
          store.writeReceipt(_wallet, _firstKey, 'receipt'),
          throwsA(isA<StoredDataCorruptionException>()),
        );
        expect(await outside.list().toList(), isEmpty);
        expect(
          await FileSystemEntity.type(linkPath, followLinks: false),
          FileSystemEntityType.link,
        );
      },
    );
  }

  for (final document in ['', 'x' * (512 * 1024 + 1)]) {
    test(
      'empty or oversized receipt cannot become a committed document (${document.length} bytes)',
      () async {
        final root = await _temporaryRoot();
        final store = IoWalletPaymentReceiptStore(
          root.path,
          _SingleLevelStorageSecurity(),
        );
        await expectLater(
          store.writeReceipt(_wallet, _firstKey, document),
          throwsA(isA<StoredDataCorruptionException>()),
        );
        expect(await store.readAll(_wallet), isEmpty);
      },
    );
  }
}

Future<Directory> _temporaryRoot() async {
  final root = await Directory.systemTemp.createTemp('aster-receipt-archive-');
  addTearDown(() => root.delete(recursive: true));
  return root;
}

/// Models the native policy: prepareRoot creates only one directory level;
/// an existing, verified parent is required. Recursive test mkdir must not
/// conceal missing initialization steps in the production archive.
final class _SingleLevelStorageSecurity implements WalletStorageSecurity {
  final _delegate = MemoryWalletStorageSecurity();

  List<String> get preparedRoots => _delegate.preparedRoots;
  List<String> get replacedFiles => _delegate.replacedFiles;

  @override
  Future<void> prepareRoot(String path) async {
    final parent = Directory(path).parent.path;
    if (await FileSystemEntity.type(parent, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw FileSystemException('Secure parent must already exist.', parent);
    }
    await _delegate.prepareRoot(path);
  }

  @override
  Future<void> createDirectory(String path) => _delegate.createDirectory(path);

  @override
  Future<void> verifyDirectory(String path) => _delegate.verifyDirectory(path);

  @override
  Future<void> verifyFile(String path) => _delegate.verifyFile(path);

  @override
  Future<void> replaceTextFile(String path, String contents) =>
      _delegate.replaceTextFile(path, contents);
}
