import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_ios_release_archive.dart';
import '../../tool/verify_ios_release_export.dart';

void main() {
  test('parses nested plist values without accepting duplicate keys', () {
    final value = parsePlistXml('''
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
        <dict>
          <key>Name</key><string>Aster</string>
          <key>Enabled</key><true/>
          <key>Families</key><array><integer>1</integer></array>
        </dict>
      </plist>
    ''') as Map<String, Object?>;

    expect(value['Name'], 'Aster');
    expect(value['Enabled'], isTrue);
    expect(value['Families'], const [1]);
    expect(
      () => parsePlistXml(
        '<plist><dict><key>A</key><string>1</string>'
        '<key>A</key><string>2</string></dict></plist>',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('compares source and archive identities field by field', () {
    const expected = IosReleaseIdentity(
      bundleIdentifier: 'com.example.asterdev',
      versionName: '1.0.0',
      buildNumber: '1',
    );

    expect(
      compareIosReleaseIdentity(expected: expected, actual: expected),
      isEmpty,
    );
    expect(
      compareIosReleaseIdentity(
        expected: expected,
        actual: const IosReleaseIdentity(
          bundleIdentifier: 'com.example.wrong',
          versionName: '2.0.0',
          buildNumber: '9',
        ),
      ),
      hasLength(3),
    );
  });

  test('requires justified app privacy reasons and tracking false', () {
    final valid = <String, Object?>{
      'NSPrivacyTracking': false,
      'NSPrivacyAccessedAPITypes': <Object?>[
        <String, Object?>{
          'NSPrivacyAccessedAPIType':
              'NSPrivacyAccessedAPICategoryFileTimestamp',
          'NSPrivacyAccessedAPITypeReasons': <Object?>['C617.1'],
        },
      ],
    };

    expect(() => validateIosPrivacyManifest(valid), returnsNormally);
    // An app-owned reason cannot paper over an unreviewed native dependency.
    expect(
      () => validateIosPrivacyManifest({
        ...valid,
        'NSPrivacyAccessedAPITypes': <Object?>[
          ...(valid['NSPrivacyAccessedAPITypes']! as List<Object?>),
          <String, Object?>{
            'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryDiskSpace',
            'NSPrivacyAccessedAPITypeReasons': <Object?>['E174.1'],
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => validateIosPrivacyManifest({...valid, 'NSPrivacyTracking': true}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validateIosPrivacyManifest({
        ...valid,
        'NSPrivacyAccessedAPITypes': <Object?>[],
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validateIosPrivacyManifest({
        ...valid,
        'NSPrivacyCollectedDataTypes': <Object?>[],
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validateIosPrivacyManifest({
        ...valid,
        'NSPrivacyAccessedAPITypes': <Object?>[
          ...(valid['NSPrivacyAccessedAPITypes']! as List<Object?>),
          <String, Object?>{
            'NSPrivacyAccessedAPIType':
                'NSPrivacyAccessedAPICategorySystemBootTime',
            'NSPrivacyAccessedAPITypeReasons': <Object?>['35F9.1'],
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('requires the exact release transport policy', () {
    final valid = <String, Object?>{
      'CFBundleDisplayName': 'Aster',
      'CFBundleName': 'Aster',
      'CFBundleExecutable': 'Runner',
      'MinimumOSVersion': '18.5',
      'UIDeviceFamily': <Object?>[1],
      'CFBundleSupportedPlatforms': <Object?>['iPhoneOS'],
      'NSAppTransportSecurity': <String, Object?>{
        'NSAllowsLocalNetworking': true,
      },
    };

    expect(() => validateIosApplicationPlist(valid), returnsNormally);
    expect(
      () => validateIosApplicationPlist({
        ...valid,
        'NSAppTransportSecurity': <String, Object?>{
          'NSAllowsLocalNetworking': true,
          'NSAllowsArbitraryLoadsInWebContent': true,
        },
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects incomplete iOS identity metadata', () {
    expect(
      () => parseIosReleaseIdentity(const {'CFBundleIdentifier': 'aster'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('installed app measurement rejects symbolic links', () async {
    final directory = await Directory.systemTemp.createTemp('aster-app-');
    addTearDown(() => directory.delete(recursive: true));
    final payload = File('${directory.path}/payload')..writeAsStringSync('ok');
    expect(await measureSafeIosAppDirectory(directory), await payload.length());

    await Link('${directory.path}/alias').create(payload.path);
    await expectLater(
      measureSafeIosAppDirectory(directory),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts one bounded regular app in an IPA payload', () {
    expect(
      validateIosIpaLayout([
        _ipaDirectory('Payload/'),
        _ipaDirectory('Payload/Runner.app/'),
        _ipaFile('Payload/Runner.app/Info.plist', size: 128),
        _ipaFile('Payload/Runner.app/Asset Name.txt'),
        _ipaDirectory('Symbols/'),
      ]),
      'Payload/Runner.app',
    );
  });

  test('rejects unsafe or ambiguous IPA layouts before extraction', () {
    for (final entries in <List<IosIpaEntryMetadata>>[
      [
        _ipaDirectory('Payload/'),
        _ipaDirectory('Payload/Runner.app/'),
        _ipaFile('../outside'),
      ],
      [
        _ipaDirectory('Payload/'),
        _ipaDirectory('Payload/Runner.app/'),
        _ipaFile('Payload/Runner.app/value'),
        _ipaFile('payload/runner.app/VALUE'),
      ],
      [
        _ipaDirectory('Payload/'),
        _ipaDirectory('Payload/Runner.app/'),
        _ipaDirectory('Payload/Other.app/'),
      ],
      [
        _ipaDirectory('Payload/'),
        _ipaDirectory('Payload/Runner.app/'),
        _ipaSymlink('Payload/Runner.app/alias'),
      ],
      [
        _ipaDirectory('Payload/'),
        _ipaDirectory('Payload/Runner.app/'),
        _ipaSpecial('Payload/Runner.app/device'),
      ],
    ]) {
      expect(
        () => validateIosIpaLayout(entries),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('extracts validated IPA bytes and preserves executable mode', () {
    if (Platform.isWindows) return;
    final root = Directory.systemTemp.createTempSync('aster-ipa-extract-');
    addTearDown(() => root.deleteSync(recursive: true));
    final archive = Archive()
      ..add(_archiveDirectory('Payload/'))
      ..add(_archiveDirectory('Payload/Runner.app/'))
      ..add(
        _archiveFile(
          'Payload/Runner.app/Info.plist',
          '<plist><dict/></plist>'.codeUnits,
        ),
      )
      ..add(
        _archiveFile('Payload/Runner.app/Runner', const [
          0x41,
          0x73,
          0x74,
          0x65,
          0x72,
        ], mode: 0x81ed),
      );
    final package = File('${root.path}/candidate.ipa')
      ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    final destination = Directory('${root.path}/expanded')..createSync();

    expect(extractValidatedIosIpa(package, destination), 'Payload/Runner.app');
    expect(
      File('${destination.path}/Payload/Runner.app/Info.plist')
          .readAsStringSync(),
      '<plist><dict/></plist>',
    );
    expect(
      File('${destination.path}/Payload/Runner.app/Runner').statSync().mode &
          0x1ff,
      0x1ed,
    );
  });

  test('rejects an IPA entry whose bytes do not match its checksum', () {
    if (Platform.isWindows) return;
    final root = Directory.systemTemp.createTempSync('aster-ipa-crc-');
    addTearDown(() => root.deleteSync(recursive: true));
    final archive = Archive()
      ..add(_archiveDirectory('Payload/'))
      ..add(_archiveDirectory('Payload/Runner.app/'))
      ..add(
        ArchiveFile.noCompress('Payload/Runner.app/value', 5, 'Aster'.codeUnits)
          ..mode = 0x81a4,
      );
    final encoded = ZipEncoder().encodeBytes(archive);
    final payloadOffset = _indexOf(encoded, 'Aster'.codeUnits);
    expect(payloadOffset, isNonNegative);
    encoded[payloadOffset] = 'B'.codeUnitAt(0);
    final package = File('${root.path}/corrupt.ipa')..writeAsBytesSync(encoded);
    final destination = Directory('${root.path}/expanded')..createSync();

    expect(
      () => extractValidatedIosIpa(package, destination),
      throwsA(isA<FormatException>()),
    );
  });
}

int _indexOf(List<int> bytes, List<int> pattern) {
  for (var offset = 0; offset <= bytes.length - pattern.length; offset += 1) {
    var matches = true;
    for (var index = 0; index < pattern.length; index += 1) {
      if (bytes[offset + index] != pattern[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return offset;
  }
  return -1;
}

ArchiveFile _archiveDirectory(String name) =>
    ArchiveFile.directory(name)..mode = 0x41ed;

ArchiveFile _archiveFile(String name, List<int> bytes, {int mode = 0x81a4}) =>
    ArchiveFile(name, bytes.length, bytes)..mode = mode;

IosIpaEntryMetadata _ipaDirectory(String name) => IosIpaEntryMetadata(
  name: name,
  size: 0,
  mode: 0x41ed,
  isFile: false,
  isDirectory: true,
  isSymbolicLink: false,
);

IosIpaEntryMetadata _ipaFile(String name, {int size = 1}) =>
    IosIpaEntryMetadata(
      name: name,
      size: size,
      mode: 0x81a4,
      isFile: true,
      isDirectory: false,
      isSymbolicLink: false,
    );

IosIpaEntryMetadata _ipaSymlink(String name) => IosIpaEntryMetadata(
  name: name,
  size: 1,
  mode: 0xa1ff,
  isFile: true,
  isDirectory: false,
  isSymbolicLink: true,
);

IosIpaEntryMetadata _ipaSpecial(String name) => IosIpaEntryMetadata(
  name: name,
  size: 0,
  mode: 0x21a4,
  isFile: true,
  isDirectory: false,
  isSymbolicLink: false,
);
