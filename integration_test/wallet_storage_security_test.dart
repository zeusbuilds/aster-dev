import 'dart:io';

import 'package:aster/core/storage/storage.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('non-release builds use isolated application storage identity', (
    tester,
  ) async {
    final package = await PackageInfo.fromPlatform();
    final expectedSuffix = kReleaseMode
        ? ''
        : kProfileMode
        ? '.profile'
        : '.debug';

    expect(package.packageName, 'com.example.asterdev$expectedSuffix');
  });

  testWidgets('secure wallet namespace round-trips without destructive reset', (
    tester,
  ) async {
    const key = 'utexo.integration-test.secure-storage';
    const value = 'non-secret-storage-probe';
    final storage = SecureStorageService();
    await storage.delete(key: key);
    addTearDown(() => storage.delete(key: key));

    await storage.write(key: key, value: value);

    expect(await storage.containsKey(key: key), isTrue);
    expect(await storage.read(key: key), value);
    expect(await storage.keys(), contains(key));

    await storage.delete(key: key);
    expect(await storage.containsKey(key: key), isFalse);
  });

  testWidgets('native wallet storage policy protects owned directories', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(
      '${support.path}${Platform.pathSeparator}utexo_storage_policy_test',
    );
    if (await root.exists()) await root.delete(recursive: true);
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    const security = PlatformWalletStorageSecurity();

    await security.prepareRoot(root.path);
    await security.verifyDirectory(root.path);
    expect((await root.stat()).mode & 0x1ff, 0x1c0);

    final child = Directory(
      '${root.path}${Platform.pathSeparator}owned_wallet',
    );
    await security.createDirectory(child.path);
    await security.verifyDirectory(child.path);
    expect((await child.stat()).mode & 0x1ff, 0x1c0);
    await expectLater(
      security.createDirectory(child.path),
      throwsA(isA<FileSystemException>()),
    );

    final metadata = File(
      '${root.path}${Platform.pathSeparator}wallet_registry.a.json',
    );
    await security.replaceTextFile(metadata.path, 'first');
    await security.verifyFile(metadata.path);
    expect(await metadata.readAsString(), 'first');
    expect((await metadata.stat()).mode & 0x1ff, 0x180);
    await security.replaceTextFile(metadata.path, 'second');
    expect(await metadata.readAsString(), 'second');

    final link = Link('${root.path}${Platform.pathSeparator}wallet_link');
    await link.create(child.path);
    await expectLater(
      security.verifyDirectory(link.path),
      throwsA(isA<FileSystemException>()),
    );

    final actualParent = Directory(
      '${root.path}${Platform.pathSeparator}actual_parent',
    );
    await security.createDirectory(actualParent.path);
    final nested = Directory(
      '${actualParent.path}${Platform.pathSeparator}nested_wallet',
    );
    await security.createDirectory(nested.path);
    final parentAlias = Link(
      '${root.path}${Platform.pathSeparator}parent_alias',
    );
    await parentAlias.create(actualParent.path);
    await expectLater(
      security.verifyDirectory(
        '${parentAlias.path}${Platform.pathSeparator}nested_wallet',
      ),
      throwsA(isA<FileSystemException>()),
    );

    await expectLater(
      security.verifyDirectory(
        '${root.path}${Platform.pathSeparator}..'
        '${Platform.pathSeparator}escaped_wallet',
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
