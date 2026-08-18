import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_toolchain.dart';

void main() {
  late Directory repository;
  late File flutterVersionMetadata;
  late File flutterExtension;
  late File flutterGradleUtils;

  setUp(() {
    repository = Directory.systemTemp.createTempSync('utexo_toolchain_');
    flutterVersionMetadata = _write(
      repository,
      'flutter/bin/cache/flutter.version.json',
      '{"flutterVersion":"3.47.0","dartSdkVersion":"3.13.0"}',
    );
    flutterExtension = _write(
      repository,
      'flutter/packages/flutter_tools/gradle/src/main/kotlin/'
          'FlutterExtension.kt',
      'val compileSdkVersion: Int = 36\n'
          'val minSdkVersion: Int = 24\n'
          'val targetSdkVersion: Int = 36\n'
          'val ndkVersion: String = "28.2.13676358"',
    );
    _write(
      repository,
      'flutter/packages/flutter_tools/gradle/src/main/kotlin/'
          'FlutterPluginConstants.kt',
      'ARCH_ARM32 to 1\n'
          'ARCH_ARM64 to 2\n'
          'ARCH_X86_64 to 4',
    );
    _write(
      repository,
      'flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt',
      'output.versionCodeOverride = abiVersionCode * 1000 + baseVersionCode',
    );
    flutterGradleUtils = _write(
      repository,
      'flutter/packages/flutter_tools/lib/src/android/gradle_utils.dart',
      "const templateDefaultGradleVersion = '9.3.1';\n"
          "const templateAndroidGradlePluginVersion = '9.1.0';\n"
          "const templateKotlinGradlePluginVersion = '2.4.0';",
    );
    _write(
      repository,
      'android/app/build.gradle.kts',
      'val utexoApplicationId = '
          'providers.gradleProperty("utexo.applicationId").get()\n'
          'android {\n'
          '  namespace = utexoApplicationId\n'
          '  compileSdk = flutter.compileSdkVersion\n'
          '  buildToolsVersion = "36.0.0"\n'
          '  ndkVersion = flutter.ndkVersion\n'
          '  defaultConfig {\n'
          '    applicationId = utexoApplicationId\n'
          '    minSdk = flutter.minSdkVersion\n'
          '    targetSdk = flutter.targetSdkVersion\n'
          '  }\n'
          '}',
    );
    _write(
      repository,
      'android/gradle.properties',
      'android.useAndroidX=true\n'
          'utexo.applicationId=com.example.utexo\n',
    );
    _write(
      repository,
      'android/settings.gradle.kts',
      'plugins {\n'
          '  id("com.android.application") version "9.1.0" apply false\n'
          '  id("org.jetbrains.kotlin.android") version "2.4.0" apply false\n'
          '}',
    );
    _write(
      repository,
      'android/gradle/wrapper/gradle-wrapper.properties',
      'distributionUrl=https\\://services.gradle.org/distributions/'
          'gradle-9.3.1-all.zip\n'
          'distributionSha256Sum='
          '17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43',
    );
    _write(
      repository,
      'android/gradle/verification-metadata.xml',
      '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<verification-metadata '
          'xmlns="https://schema.gradle.org/dependency-verification">\n'
          '  <configuration>\n'
          '    <verify-metadata>true</verify-metadata>\n'
          '    <verify-signatures>false</verify-signatures>\n'
          '  </configuration>\n'
          '  <components>\n'
          '    <component group="example" name="owned" version="1.0.0">\n'
          '      <artifact name="owned-1.0.0.jar">\n'
          '        <sha256 value="'
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"/>\n'
          '      </artifact>\n'
          '    </component>\n'
          '  </components>\n'
          '</verification-metadata>',
    );
    _write(
      repository,
      'flake.nix',
      'ruby = pkgs.ruby;\n'
          'bundler = pkgs.bundler;\n'
          'includeNDK = true;\n'
          'ndkVersions = [ "28.2.13676358" ];\n'
          'platformToolsVersion = "36.0.0";\n'
          'buildToolsVersions = [ "36.0.0" ];\n'
          'platformVersions = [ "36" ];\n'
          'PATH="build-tools/36.0.0";',
    );
    _write(repository, '.fvmrc', '{"flutter":"3.47.0"}');
    _write(
      repository,
      '.vscode/settings.json',
      '{"dart.flutterSdkPath":".fvm/versions/3.47.0"}',
    );
    _write(
      repository,
      '.github/workflows/dart.yml',
      'flutter-version: "3.47.0"\n'
          'run: flutter pub get --enforce-lockfile\n'
          'run: flutter analyze --no-pub --fatal-warnings --fatal-infos\n'
          'run: flutter test --no-pub',
    );
    _write(
      repository,
      'Makefile',
      'BUNDLE_PATH ?= \$(CURDIR)/.bundle\n'
          'BUNDLER_VERSION := 4.0.10\n'
          'dependencies:\n'
          '\tfvm flutter pub get --enforce-lockfile\n'
          'ios-dependencies:\n'
          '\t@BUNDLE_FROZEN=true BUNDLE_PATH="\$(BUNDLE_PATH)" bundle check || BUNDLE_FROZEN=true BUNDLE_PATH="\$(BUNDLE_PATH)" bundle install\n'
          'ios-native-test: dependencies ios-dependencies\n'
          '\tBUNDLE_FROZEN=true BUNDLE_PATH="\$(BUNDLE_PATH)" bundle exec fvm flutter build ios --simulator --debug --config-only --no-pub\n'
          'ios-storage-test: ios-dependencies\n'
          'run-ios: dependencies ios-dependencies\n'
          '\tBUNDLE_FROZEN=true BUNDLE_PATH="\$(BUNDLE_PATH)" bundle exec fvm flutter run --no-pub -d "\$(IOS_SIMULATOR_ID)"\n'
          'run-android: dependencies\n'
          '\tfvm flutter run --no-pub -d "\$(ANDROID_DEVICE_ID)"\n'
          'prepare-android-release:\n'
          '\tfvm flutter clean\n'
          '\t@\$(MAKE) --no-print-directory dependencies\n'
          '\tfvm dart run tool/prepare_android_release.dart\n'
          'android-release-bundle: prepare-android-release\n'
          '\tfvm flutter build appbundle --release --no-pub\n'
          'android-release-apks: prepare-android-release\n'
          '\tfvm flutter build apk --release --split-per-abi --no-pub',
    );
    _write(
      repository,
      'ios/Runner.xcodeproj/project.pbxproj',
      'PRODUCT_BUNDLE_IDENTIFIER = com.example.utexo;\n'
          'PRODUCT_BUNDLE_IDENTIFIER = com.example.utexo.debug;\n'
          'PRODUCT_BUNDLE_IDENTIFIER = com.example.utexo.profile;\n'
          'PRODUCT_BUNDLE_IDENTIFIER = com.example.utexo.tests;\n'
          'PRODUCT_BUNDLE_IDENTIFIER = com.example.utexo.debug.tests;\n'
          'PRODUCT_BUNDLE_IDENTIFIER = com.example.utexo.profile.tests;',
    );
    _write(
      repository,
      'scripts/run-android-integration-test.sh',
      'readonly release_package="com.example.utexo"\n'
          'readonly test_package="\${release_package}.debug"',
    );
    _write(
      repository,
      'scripts/run-ios-integration-test.sh',
      'readonly release_bundle="com.example.utexo"\n'
          'readonly test_bundle="\${release_bundle}.debug"\n'
          'readonly bundler_version="4.0.10"\n'
          'export BUNDLE_FROZEN=true\n'
          'bundle check >/dev/null 2>&1 ||\n'
          'bundle exec fvm flutter pub get --enforce-lockfile\n'
          'bundle exec fvm flutter build ios --simulator --debug --no-pub\n'
          'bundle exec fvm flutter test --no-pub target\n'
          'readonly built_test_app="\${root}/build/ios/iphonesimulator/Runner.app"\n'
          'plutil -extract CFBundleIdentifier raw -- "\${built_test_app}/Info.plist"\n'
          'xcrun simctl install "\${simulator_id}" "\${built_test_app}"\n'
          'local restored_app="\${root}/build/ios/iphonesimulator/Runner.app"\n'
          'xcrun simctl install "\${simulator_id}" "\${restored_app}"\n'
          'readonly test_path_after="\$(bundle_path "\${test_bundle}")"\n'
          'fail "the isolated debug bundle was not installed"',
    );
    _write(repository, 'ios/Podfile.lock', 'COCOAPODS: 1.16.2');
    _write(
      repository,
      'Gemfile',
      'source "https://rubygems.org"\n\n'
          'gem "cocoapods", "1.16.2"',
    );
    _write(
      repository,
      'Gemfile.lock',
      'GEM\n'
          '  remote: https://rubygems.org/\n'
          '  specs:\n'
          '    cocoapods (1.16.2)\n\n'
          'PLATFORMS\n'
          '  arm64-darwin\n'
          '  ruby\n'
          '  x86_64-darwin\n\n'
          'DEPENDENCIES\n'
          '  cocoapods (= 1.16.2)\n\n'
          'CHECKSUMS\n'
          '  cocoapods (1.16.2) sha256='
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n\n'
          'BUNDLED WITH\n'
          '  4.0.10',
    );
    _write(
      repository,
      'scripts/verify-android-release-apks.sh',
      'fvm dart run tool/verify_android_release_identity.dart \\\n'
          '  --apk "\${apk_path}" \\\n'
          '  --aapt2 "\${UTEXO_AAPT2}"',
    );
    _write(
      repository,
      'scripts/verify-android-release-bundle.sh',
      'fvm dart run tool/verify_android_release_identity.dart \\\n'
          '  --bundle "\${bundle_path}" \\\n'
          '  --aapt2-proto "\${UTEXO_AAPT2_PROTO_JAR}" \\\n'
          '  --protobuf "\${UTEXO_PROTOBUF_JAR}"',
    );
    _write(
      repository,
      'pubspec.yaml',
      'environment:\n'
          '  sdk: ">=3.13.0 <4.0.0"\n'
          '  flutter: ">=3.47.0"',
    );
    _write(
      repository,
      'docs/DEVELOPMENT.md',
      '- Android SDK platform 36, build tools 36.0.0, and platform tools 36.0.0\n'
          '- Android NDK 28.2.13676358, matching Flutter\n'
          '- Gradle 9.3.1, Android Gradle Plugin 9.1.0, and Kotlin 2.4.0\n'
          '- Flutter 3.47.0 and Dart 3.13.0\n'
          '- CocoaPods 1.16.2 through Bundler 4.0.10\n'
          '- Debug `com.example.utexo.debug`\n'
          '- Profile `com.example.utexo.profile`\n'
          '- Release `com.example.utexo`',
    );
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
  });

  test('accepts the complete Flutter-owned toolchain contract', () {
    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(result.passed, isTrue, reason: result.failures.join('\n'));
    expect(result.flutterVersion, '3.47.0');
    expect(result.dartVersion, '3.13.0');
    expect(result.flutterGradleVersion, '9.3.1');
    expect(result.flutterAgpVersion, '9.1.0');
    expect(result.flutterKotlinVersion, '2.4.0');
    expect(result.flutterCompileSdk, 36);
    expect(result.flutterMinSdk, 24);
    expect(result.flutterTargetSdk, 36);
    expect(result.flutterNdkVersion, '28.2.13676358');
    expect(
      result.gradleDistributionSha256,
      '17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43',
    );
    expect(result.androidVerifiedArtifacts, 1);
    expect(result.androidBuildToolsVersion, '36.0.0');
    expect(result.androidPlatformToolsVersion, '36.0.0');
    expect(result.androidApplicationId, 'com.example.utexo');
    expect(result.cocoaPodsVersion, '1.16.2');
    expect(result.bundlerVersion, '4.0.10');
  });

  test('rejects omitted NDK and divergent Nix revisions', () {
    _write(
      repository,
      'flake.nix',
      'includeNDK = false;\nndkVersions = [ "27.0.0" ];',
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must include the Android NDK'),
        contains('exactly Flutter NDK 28.2.13676358'),
        contains('exactly Android build tools 36.0.0'),
        contains('exactly Android SDK platform 36'),
        contains('Nix Android platform-tools version'),
      ]),
    );
  });

  test('rejects Android build-chain drift', () {
    _write(
      repository,
      'android/app/build.gradle.kts',
      'android { ndkVersion = "27.0.0" }',
    );
    _write(
      repository,
      'android/settings.gradle.kts',
      'plugins {\n'
          '  id("com.android.application") version "9.0.1" apply false\n'
          '  id("org.jetbrains.kotlin.android") version "2.3.20" apply false\n'
          '}',
    );
    _write(
      repository,
      'android/gradle/wrapper/gradle-wrapper.properties',
      'distributionUrl=https\\://services.gradle.org/distributions/'
          'gradle-9.1.0-all.zip',
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must delegate compileSdk to Flutter'),
        contains('must delegate minSdk to Flutter'),
        contains('must delegate targetSdk to Flutter'),
        contains('must delegate ndkVersion to Flutter'),
        contains('exactly Android Gradle Plugin 9.1.0'),
        contains('exactly Kotlin Gradle Plugin 2.4.0'),
        contains('wrapper must use Flutter Gradle 9.3.1'),
      ]),
    );
  });

  test('rejects unreviewed Gradle checksums and permissive metadata', () {
    final wrapper = File(
      '${repository.path}/android/gradle/wrapper/gradle-wrapper.properties',
    );
    wrapper.writeAsStringSync(
      wrapper.readAsStringSync().replaceFirst(
        '17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43',
        '0000000000000000000000000000000000000000000000000000000000000000',
      ),
    );
    final metadata = File(
      '${repository.path}/android/gradle/verification-metadata.xml',
    );
    metadata.writeAsStringSync(
      metadata
          .readAsStringSync()
          .replaceFirst(
            '    <verify-signatures>false</verify-signatures>\n',
            '    <verify-signatures>false</verify-signatures>\n'
                '    <trusted-artifacts/>\n',
          )
          .replaceFirst(
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
            'not-a-checksum',
          ),
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('does not match the reviewed official digest'),
        contains('strict metadata SHA-256 checks without broad trust'),
        contains('has an invalid SHA-256 checksum'),
      ]),
    );
  });

  test('rejects multiple accepted hashes for one Gradle artifact', () {
    final metadata = File(
      '${repository.path}/android/gradle/verification-metadata.xml',
    );
    metadata.writeAsStringSync(
      metadata.readAsStringSync().replaceFirst(
        '      </artifact>',
        '        <sha256 value="'
            'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"/>\n'
            '      </artifact>',
      ),
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains(contains('must use exactly one SHA-256 checksum')),
    );
  });

  test('rejects CocoaPods, Bundler, and iOS command drift', () {
    _write(
      repository,
      'Gemfile',
      'source "https://rubygems.org"\n\n'
          'gem "cocoapods", "1.16.1"',
    );
    final gemLock = File('${repository.path}/Gemfile.lock');
    gemLock.writeAsStringSync(
      gemLock.readAsStringSync().replaceFirst(
        RegExp(r'sha256=[0-9a-f]{64}'),
        'sha256=missing',
      ),
    );
    final makefile = File('${repository.path}/Makefile');
    makefile.writeAsStringSync(
      makefile
          .readAsStringSync()
          .replaceFirst('BUNDLER_VERSION := 4.0.10', 'BUNDLER_VERSION := 4.0.9')
          .replaceFirst(
            'bundle exec fvm flutter build ios',
            'fvm flutter build ios',
          )
          .replaceFirst(
            'bundle exec fvm flutter run --no-pub',
            'fvm flutter run --no-pub',
          ),
    );
    final iosIntegration = File(
      '${repository.path}/scripts/run-ios-integration-test.sh',
    );
    iosIntegration.writeAsStringSync(
      iosIntegration.readAsStringSync().replaceFirst(
        'export BUNDLE_FROZEN=true\n',
        '',
      ),
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('Gemfile must pin CocoaPods 1.16.2 exactly'),
        contains('Every locked Ruby gem must carry one SHA-256'),
        contains('Makefile must require Bundler 4.0.10'),
        contains('iOS native bootstrap must execute Flutter inside'),
        contains('Interactive iOS builds must execute Flutter inside'),
        contains('iOS integration must prevent Gemfile.lock mutation'),
      ]),
    );
  });

  test('rejects extra Gemfile inputs and incomplete lock checksums', () {
    final gemfile = File('${repository.path}/Gemfile');
    gemfile.writeAsStringSync('${gemfile.readAsStringSync()}\ngem "rake"\n');
    final gemLock = File('${repository.path}/Gemfile.lock');
    gemLock.writeAsStringSync(
      gemLock.readAsStringSync().replaceFirst(
        RegExp(
          r'^  cocoapods \(1\.16\.2\) sha256=[0-9a-f]{64}\n',
          multiLine: true,
        ),
        '',
      ),
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('Gemfile must contain only the reviewed RubyGems source'),
        contains('Every locked Ruby gem must carry one SHA-256 checksum'),
      ]),
    );
  });

  test('rejects platform identity drift and inferred iOS evidence', () {
    final project = File(
      '${repository.path}/ios/Runner.xcodeproj/project.pbxproj',
    );
    project.writeAsStringSync(
      project.readAsStringSync().replaceFirst(
        'com.example.utexo.profile;',
        'com.example.other.profile;',
      ),
    );
    _write(
      repository,
      'scripts/run-android-integration-test.sh',
      'readonly release_package="com.example.other"\n'
          'readonly test_package="\${release_package}.profile"',
    );
    final iosIntegration = File(
      '${repository.path}/scripts/run-ios-integration-test.sh',
    );
    iosIntegration.writeAsStringSync(
      iosIntegration
          .readAsStringSync()
          .replaceFirst(
            'readonly release_bundle="com.example.utexo"',
            'readonly release_bundle="com.example.other"',
          )
          .replaceFirst(
            'readonly test_bundle="\${release_bundle}.debug"',
            'readonly test_bundle="\${release_bundle}.profile"',
          )
          .replaceFirst(
            'xcrun simctl install "\${simulator_id}" "\${built_test_app}"\n',
            '',
          ),
    );
    final development = File('${repository.path}/docs/DEVELOPMENT.md');
    development.writeAsStringSync(
      development.readAsStringSync().replaceFirst(
        '`com.example.utexo.debug`',
        '`com.example.other.debug`',
      ),
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('iOS build settings must declare exactly one'),
        contains('Android integration wrapper must use release identity'),
        contains('Android integration wrapper must derive its debug identity'),
        contains('iOS integration wrapper must use release identity'),
        contains('iOS integration wrapper must derive its debug identity'),
        contains('iOS integration must install the exact built debug artifact'),
        contains('must document platform identity com.example.utexo.debug'),
      ]),
    );
  });

  test('rejects Flutter split-ABI versioning drift', () {
    _write(
      repository,
      'flutter/packages/flutter_tools/gradle/src/main/kotlin/'
          'FlutterPluginConstants.kt',
      'ARCH_ARM32 to 1\nARCH_ARM64 to 3\nARCH_X86_64 to 4',
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains(
        'Flutter split-ABI version map differs from the artifact verifier.',
      ),
    );
  });

  test('rejects documentation drift', () {
    _write(repository, 'docs/DEVELOPMENT.md', '- Android SDK 36');

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('must document Android NDK 28.2.13676358'),
        contains('must document Flutter\'s Android build chain'),
        contains('must document the Android SDK/build-tools chain'),
        contains('must document the Flutter/Dart versions'),
      ]),
    );
  });

  test('rejects Flutter, Dart, CI, editor, and package version drift', () {
    _write(repository, '.fvmrc', '{"flutter":"3.46.0"}');
    _write(
      repository,
      '.vscode/settings.json',
      '{"dart.flutterSdkPath":".fvm/versions/3.46.0"}',
    );
    _write(
      repository,
      '.github/workflows/dart.yml',
      'flutter-version: "3.46.0"\n'
          'run: flutter pub get\n'
          'run: flutter analyze --fatal-warnings --fatal-infos\n'
          'run: flutter test',
    );
    _write(
      repository,
      'pubspec.yaml',
      'environment:\n'
          '  sdk: ">=3.12.0 <4.0.0"\n'
          '  flutter: ">=3.46.0"',
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('.fvmrc Flutter version must be exactly 3.47.0'),
        contains('VS Code Flutter SDK path must be exactly'),
        contains('GitHub Actions Flutter version must be exactly 3.47.0'),
        contains('must resolve the committed Pub lockfile'),
        contains('analysis must not re-resolve dependencies'),
        contains('tests must not re-resolve dependencies'),
        contains('must require Dart >=3.13.0 <4.0.0'),
        contains('must require Flutter >=3.47.0'),
      ]),
    );
  });

  test('rejects build tools from another compile SDK generation', () {
    _write(
      repository,
      'android/app/build.gradle.kts',
      File('${repository.path}/android/app/build.gradle.kts')
          .readAsStringSync()
          .replaceFirst('36.0.0', '35.0.0'),
    );
    _write(
      repository,
      'flake.nix',
      File('${repository.path}/flake.nix')
          .readAsStringSync()
          .replaceAll('36.0.0', '35.0.0'),
    );
    _write(
      repository,
      'docs/DEVELOPMENT.md',
      File('${repository.path}/docs/DEVELOPMENT.md')
          .readAsStringSync()
          .replaceFirst('36.0.0', '35.0.0'),
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains('Android build tools 35.0.0 must match compile SDK 36.'),
    );
  });

  test('rejects unpinned Make dependency resolution', () {
    _write(repository, 'Makefile', 'dependencies:\n\tfvm flutter pub get');

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains(
        'Makefile dependency setup must enforce the committed Pub lockfile.',
      ),
    );
  });

  test('rejects Android Release targets that bypass guarded preparation', () {
    final makefile = File('${repository.path}/Makefile');
    makefile.writeAsStringSync(
      makefile.readAsStringSync().replaceFirst(
        'android-release-bundle: prepare-android-release',
        'android-release-bundle: dependencies',
      ),
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains(
        'android-release-bundle must depend on guarded Release plugin preparation.',
      ),
    );
  });

  test('rejects reordered Android Release preparation', () {
    final makefile = File('${repository.path}/Makefile');
    makefile.writeAsStringSync(
      makefile.readAsStringSync().replaceFirst(
        '\tfvm flutter clean\n'
            '\t@\$(MAKE) --no-print-directory dependencies\n',
        '\t@\$(MAKE) --no-print-directory dependencies\n'
            '\tfvm flutter clean\n',
      ),
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains(
        'Android Release preparation must clean, resolve the exact lock, and '
        'then run the guarded plugin tool in order.',
      ),
    );
  });

  test('rejects Android artifact identity bypasses', () {
    _write(
      repository,
      'scripts/verify-android-release-bundle.sh',
      './scripts/verify-android-native-libraries.sh',
    );

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains('Bundle verification must enforce committed release identity.'),
    );
  });

  test('rejects malformed Flutter version metadata', () {
    flutterVersionMetadata.writeAsStringSync('{malformed');

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      contains('Flutter version metadata must contain one JSON object.'),
    );
  });

  test('fails closed when Flutter metadata is unavailable', () {
    final result = verifyToolchain(
      repositoryRoot: repository,
      flutterVersionMetadata: null,
      flutterExtension: null,
      flutterGradleUtils: null,
    );

    expect(result.passed, isFalse);
    expect(result.flutterVersion, isNull);
    expect(result.flutterNdkVersion, isNull);
    expect(
      result.failures,
      containsAll([
        'Missing Flutter Gradle extension.',
        'Missing Flutter Gradle plugin.',
        'Missing Flutter Gradle plugin constants.',
        'Missing Flutter Gradle utilities.',
        'Missing Flutter version metadata.',
      ]),
    );
  });
}

ToolchainVerification _verify(
  Directory repository,
  File flutterVersionMetadata,
  File flutterExtension,
  File flutterGradleUtils,
) {
  return verifyToolchain(
    repositoryRoot: repository,
    flutterVersionMetadata: flutterVersionMetadata,
    flutterExtension: flutterExtension,
    flutterGradleUtils: flutterGradleUtils,
  );
}

File _write(Directory root, String path, String contents) {
  final file = File('${root.path}/$path');
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}
