import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

const _reviewedGradleDistributionSha256 = <String, String>{
  '9.3.1': '17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43',
};

/// Result of checking the repository's cross-toolchain version contract.
final class ToolchainVerification {
  const ToolchainVerification({
    required this.flutterVersion,
    required this.dartVersion,
    required this.flutterGradleVersion,
    required this.flutterAgpVersion,
    required this.flutterKotlinVersion,
    required this.flutterCompileSdk,
    required this.flutterMinSdk,
    required this.flutterTargetSdk,
    required this.flutterNdkVersion,
    required this.gradleDistributionSha256,
    required this.androidVerifiedArtifacts,
    required this.androidBuildToolsVersion,
    required this.androidPlatformToolsVersion,
    required this.androidApplicationId,
    required this.cocoaPodsVersion,
    required this.bundlerVersion,
    required this.failures,
  });

  /// Flutter framework revision represented by the executing SDK.
  final String? flutterVersion;

  /// Dart SDK revision bundled with the executing Flutter SDK.
  final String? dartVersion;

  /// Gradle wrapper revision declared by the Flutter project template.
  final String? flutterGradleVersion;

  /// Android Gradle Plugin revision declared by the Flutter project template.
  final String? flutterAgpVersion;

  /// Kotlin Gradle Plugin revision declared by the Flutter project template.
  final String? flutterKotlinVersion;

  /// Android compile SDK declared by the Flutter Gradle extension.
  final int? flutterCompileSdk;

  /// Android minimum SDK declared by the Flutter Gradle extension.
  final int? flutterMinSdk;

  /// Android target SDK declared by the Flutter Gradle extension.
  final int? flutterTargetSdk;

  /// NDK revision declared by the Flutter SDK, when it could be resolved.
  final String? flutterNdkVersion;

  /// Reviewed digest for the exact Gradle wrapper distribution.
  final String? gradleDistributionSha256;

  /// Number of Maven artifacts covered by strict SHA-256 verification.
  final int androidVerifiedArtifacts;

  /// Android build-tools revision pinned by the application and Nix shell.
  final String? androidBuildToolsVersion;

  /// Android platform-tools revision pinned by the reproducible Nix shell.
  final String? androidPlatformToolsVersion;

  /// Provisional application identity shared by both mobile hosts.
  final String? androidApplicationId;

  /// CocoaPods version locked for every owned iOS build path.
  final String? cocoaPodsVersion;

  /// Bundler version that generated the committed Ruby dependency lock.
  final String? bundlerVersion;

  /// Deterministically ordered missing or divergent toolchain declarations.
  final List<String> failures;

  /// Whether every owned toolchain surface agrees with Flutter.
  bool get passed => failures.isEmpty;
}

/// Verifies the checked-out repository against the Dart executable's Flutter SDK.
void main() {
  final flutterVersionMetadata = _locateFlutterVersionMetadata(
    Platform.resolvedExecutable,
  );
  final flutterExtension = _locateFlutterExtension(Platform.resolvedExecutable);
  final flutterGradleUtils = _locateFlutterGradleUtils(
    Platform.resolvedExecutable,
  );
  final result = verifyToolchain(
    repositoryRoot: Directory.current,
    flutterVersionMetadata: flutterVersionMetadata,
    flutterExtension: flutterExtension,
    flutterGradleUtils: flutterGradleUtils,
  );

  if (!result.passed) {
    for (final failure in result.failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Toolchain policy verified for Flutter ${result.flutterVersion}, '
    'Dart ${result.dartVersion}, Gradle ${result.flutterGradleVersion}, '
    '${result.androidVerifiedArtifacts} verified Android artifacts, '
    'AGP ${result.flutterAgpVersion}, Kotlin ${result.flutterKotlinVersion}, '
    'Android SDK ${result.flutterCompileSdk}, build tools '
    '${result.androidBuildToolsVersion}, platform tools '
    '${result.androidPlatformToolsVersion}, NDK '
    '${result.flutterNdkVersion}, CocoaPods ${result.cocoaPodsVersion}, and '
    'Bundler ${result.bundlerVersion}.',
  );
}

/// Checks every owned toolchain surface against the executing Flutter SDK.
///
/// Flutter-owned files are injectable so the fail-closed policy can be tested
/// without depending on a globally installed Flutter checkout.
ToolchainVerification verifyToolchain({
  required Directory repositoryRoot,
  required File? flutterVersionMetadata,
  required File? flutterExtension,
  required File? flutterGradleUtils,
}) {
  final failures = <String>[];
  final versionMetadata = _readJsonObject(
    flutterVersionMetadata,
    'Flutter version metadata',
    failures,
  );
  final flutterVersion = _readJsonString(
    versionMetadata,
    'flutterVersion',
    'Flutter framework version',
    failures,
  );
  final dartVersion = _readJsonString(
    versionMetadata,
    'dartSdkVersion',
    'Flutter-bundled Dart version',
    failures,
  );

  final extensionContents = _readRequired(
    flutterExtension,
    'Flutter Gradle extension',
    failures,
  );
  final flutterGradleDirectory = flutterExtension?.parent;
  final flutterPluginConstants = _readRequired(
    flutterGradleDirectory == null
        ? null
        : File('${flutterGradleDirectory.path}/FlutterPluginConstants.kt'),
    'Flutter Gradle plugin constants',
    failures,
  );
  final flutterPlugin = _readRequired(
    flutterGradleDirectory == null
        ? null
        : File('${flutterGradleDirectory.path}/FlutterPlugin.kt'),
    'Flutter Gradle plugin',
    failures,
  );
  _verifyFlutterSplitVersioning(
    constants: flutterPluginConstants,
    plugin: flutterPlugin,
    failures: failures,
  );
  final ndkVersion = extensionContents == null
      ? null
      : RegExp(r'val\s+ndkVersion\s*:\s*String\s*=\s*"([^"]+)"')
            .firstMatch(extensionContents)
            ?.group(1);
  if (extensionContents != null && ndkVersion == null) {
    failures.add(
      'Flutter Gradle extension does not expose an inspectable ndkVersion.',
    );
  }
  final compileSdk = _readKotlinIntProperty(
    extensionContents,
    'compileSdkVersion',
    'Flutter compile SDK',
    failures,
  );
  final minSdk = _readKotlinIntProperty(
    extensionContents,
    'minSdkVersion',
    'Flutter minimum SDK',
    failures,
  );
  final targetSdk = _readKotlinIntProperty(
    extensionContents,
    'targetSdkVersion',
    'Flutter target SDK',
    failures,
  );

  final gradleUtilsContents = _readRequired(
    flutterGradleUtils,
    'Flutter Gradle utilities',
    failures,
  );
  final gradleVersion = _readDartStringConstant(
    gradleUtilsContents,
    'templateDefaultGradleVersion',
    'Flutter Gradle version',
    failures,
  );
  final agpVersion = _readDartStringConstant(
    gradleUtilsContents,
    'templateAndroidGradlePluginVersion',
    'Flutter Android Gradle Plugin version',
    failures,
  );
  final kotlinVersion = _readDartStringConstant(
    gradleUtilsContents,
    'templateKotlinGradlePluginVersion',
    'Flutter Kotlin Gradle Plugin version',
    failures,
  );

  final root = repositoryRoot.absolute.path;
  final android = _readRequired(
    File('$root/android/app/build.gradle.kts'),
    'android/app/build.gradle.kts',
    failures,
  );
  final androidProperties = _readRequired(
    File('$root/android/gradle.properties'),
    'android/gradle.properties',
    failures,
  );
  final androidApplicationId = androidProperties == null
      ? null
      : _readSingleCapture(
          androidProperties,
          RegExp(
            r'^utexo\.applicationId='
            r'([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+)\s*$',
            multiLine: true,
          ),
          'Android application ID property',
          failures,
        );
  String? buildToolsVersion;
  if (android != null) {
    _requireSinglePattern(
      android,
      RegExp(
        r'val\s+utexoApplicationId\s*=\s*providers\.gradleProperty\('
        r'"utexo\.applicationId"\)\.get\(\)',
      ),
      'Android application ID must come from the owned Gradle property.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bnamespace\s*=\s*utexoApplicationId\b'),
      'Android namespace must use the owned application ID.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bapplicationId\s*=\s*utexoApplicationId\b'),
      'Android release application ID must use the owned property.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bcompileSdk\s*=\s*flutter\.compileSdkVersion\b'),
      'android/app/build.gradle.kts must delegate compileSdk to Flutter.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bminSdk\s*=\s*flutter\.minSdkVersion\b'),
      'android/app/build.gradle.kts must delegate minSdk to Flutter.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\btargetSdk\s*=\s*flutter\.targetSdkVersion\b'),
      'android/app/build.gradle.kts must delegate targetSdk to Flutter.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bndkVersion\s*=\s*flutter\.ndkVersion\b'),
      'android/app/build.gradle.kts must delegate ndkVersion to Flutter.',
      failures,
    );
    buildToolsVersion = _readSingleCapture(
      android,
      RegExp(r'\bbuildToolsVersion\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"'),
      'Android build-tools version',
      failures,
    );
    if (compileSdk != null &&
        buildToolsVersion != null &&
        buildToolsVersion.split('.').first != compileSdk.toString()) {
      failures.add(
        'Android build tools $buildToolsVersion must match compile SDK '
        '$compileSdk.',
      );
    }
  }

  final settings = _readRequired(
    File('$root/android/settings.gradle.kts'),
    'android/settings.gradle.kts',
    failures,
  );
  if (settings != null) {
    _requirePluginVersion(
      settings,
      plugin: 'com.android.application',
      expected: agpVersion,
      label: 'Android Gradle Plugin',
      failures: failures,
    );
    _requirePluginVersion(
      settings,
      plugin: 'org.jetbrains.kotlin.android',
      expected: kotlinVersion,
      label: 'Kotlin Gradle Plugin',
      failures: failures,
    );
  }

  final wrapper = _readRequired(
    File('$root/android/gradle/wrapper/gradle-wrapper.properties'),
    'android/gradle/wrapper/gradle-wrapper.properties',
    failures,
  );
  String? gradleDistributionSha256;
  if (wrapper != null && gradleVersion != null) {
    _requireSinglePattern(
      wrapper,
      RegExp(
        '^distributionUrl=https\\\\://services\\.gradle\\.org/'
        'distributions/gradle-${RegExp.escape(gradleVersion)}-all\\.zip\\s*\$',
        multiLine: true,
      ),
      'Android Gradle wrapper must use Flutter Gradle $gradleVersion.',
      failures,
    );
    gradleDistributionSha256 = _readSingleCapture(
      wrapper,
      RegExp(r'^distributionSha256Sum=([0-9a-f]{64})\s*$', multiLine: true),
      'Gradle distribution SHA-256',
      failures,
    );
    final reviewedSha256 = _reviewedGradleDistributionSha256[gradleVersion];
    if (reviewedSha256 == null) {
      failures.add(
        'Flutter Gradle $gradleVersion has no reviewed distribution digest.',
      );
    } else if (gradleDistributionSha256 != null &&
        gradleDistributionSha256 != reviewedSha256) {
      failures.add(
        'Gradle $gradleVersion distribution SHA-256 does not match the '
        'reviewed official digest.',
      );
    }
  }

  final androidVerifiedArtifacts = _verifyGradleDependencyMetadata(
    File('$root/android/gradle/verification-metadata.xml'),
    failures,
  );

  final flake = _readRequired(File('$root/flake.nix'), 'flake.nix', failures);
  String? platformToolsVersion;
  if (flake != null) {
    _requireSinglePattern(
      flake,
      RegExp(r'\bruby\s*=\s*pkgs\.ruby\s*;'),
      'flake.nix must provide the pinned Ruby package on macOS.',
      failures,
    );
    _requireSinglePattern(
      flake,
      RegExp(r'\bbundler\s*=\s*pkgs\.bundler\s*;'),
      'flake.nix must provide Bundler on macOS.',
      failures,
    );
    if (RegExp(r'\bcocoapods\s*=\s*pkgs\.cocoapods\s*;').hasMatch(flake)) {
      failures.add(
        'flake.nix must obtain CocoaPods through the committed Bundler lock.',
      );
    }
    if (!RegExp(r'\bincludeNDK\s*=\s*true\s*;').hasMatch(flake)) {
      failures.add('flake.nix must include the Android NDK.');
    }
    final declaredVersions = RegExp(
      r'\bndkVersions\s*=\s*\[\s*"([^"]+)"\s*\]\s*;',
    ).allMatches(flake).map((match) => match.group(1)!).toList();
    if (ndkVersion != null &&
        (declaredVersions.length != 1 ||
            declaredVersions.single != ndkVersion)) {
      failures.add('flake.nix must declare exactly Flutter NDK $ndkVersion.');
    }
    _requireNixVersionList(
      flake,
      property: 'buildToolsVersions',
      expected: buildToolsVersion,
      label: 'Android build tools',
      failures: failures,
    );
    _requireNixVersionList(
      flake,
      property: 'platformVersions',
      expected: compileSdk?.toString(),
      label: 'Android SDK platform',
      failures: failures,
    );
    platformToolsVersion = _readSingleCapture(
      flake,
      RegExp(r'\bplatformToolsVersion\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"'),
      'Nix Android platform-tools version',
      failures,
    );
    if (buildToolsVersion != null &&
        !flake.contains('build-tools/$buildToolsVersion')) {
      failures.add(
        'flake.nix PATH must expose Android build tools $buildToolsVersion.',
      );
    }
  }

  final fvm = _readJsonObject(File('$root/.fvmrc'), '.fvmrc', failures);
  _requireJsonValue(
    fvm,
    key: 'flutter',
    expected: flutterVersion,
    label: '.fvmrc Flutter version',
    failures: failures,
  );

  final vscode = _readJsonObject(
    File('$root/.vscode/settings.json'),
    '.vscode/settings.json',
    failures,
  );
  _requireJsonValue(
    vscode,
    key: 'dart.flutterSdkPath',
    expected: flutterVersion == null ? null : '.fvm/versions/$flutterVersion',
    label: 'VS Code Flutter SDK path',
    failures: failures,
  );

  final workflow = _readRequired(
    File('$root/.github/workflows/dart.yml'),
    '.github/workflows/dart.yml',
    failures,
  );
  if (workflow != null && flutterVersion != null) {
    _requireSingleCapturedValue(
      workflow,
      RegExp(r'\bflutter-version:\s*"([^"]+)"'),
      flutterVersion,
      'GitHub Actions Flutter version',
      failures,
    );
  }
  if (workflow != null) {
    _requireSinglePattern(
      workflow,
      RegExp(
        r'^\s*run:\s*flutter pub get --enforce-lockfile\s*$',
        multiLine: true,
      ),
      'GitHub Actions must resolve the committed Pub lockfile exactly once.',
      failures,
    );
    _requireSinglePattern(
      workflow,
      RegExp(r'^\s*run:\s*flutter analyze --no-pub\b', multiLine: true),
      'GitHub Actions analysis must not re-resolve dependencies.',
      failures,
    );
    _requireSinglePattern(
      workflow,
      RegExp(r'^\s*run:\s*flutter test --no-pub\s*$', multiLine: true),
      'GitHub Actions tests must not re-resolve dependencies.',
      failures,
    );
  }

  final iosProject = _readRequired(
    File('$root/ios/Runner.xcodeproj/project.pbxproj'),
    'ios/Runner.xcodeproj/project.pbxproj',
    failures,
  );
  final androidIntegration = _readRequired(
    File('$root/scripts/run-android-integration-test.sh'),
    'scripts/run-android-integration-test.sh',
    failures,
  );
  final iosIntegration = _readRequired(
    File('$root/scripts/run-ios-integration-test.sh'),
    'scripts/run-ios-integration-test.sh',
    failures,
  );
  if (androidApplicationId != null) {
    if (iosProject != null) {
      for (final bundleId in <String>[
        androidApplicationId,
        '$androidApplicationId.debug',
        '$androidApplicationId.profile',
        '$androidApplicationId.tests',
        '$androidApplicationId.debug.tests',
        '$androidApplicationId.profile.tests',
      ]) {
        _requireSinglePattern(
          iosProject,
          RegExp(
            '\\bPRODUCT_BUNDLE_IDENTIFIER\\s*=\\s*'
            '${RegExp.escape(bundleId)}\\s*;',
          ),
          'iOS build settings must declare exactly one $bundleId identity.',
          failures,
        );
      }
    }
    _requireIntegrationIdentity(
      androidIntegration,
      label: 'Android integration wrapper',
      variable: 'release_package',
      expected: androidApplicationId,
      failures: failures,
    );
    _requireIntegrationIdentity(
      iosIntegration,
      label: 'iOS integration wrapper',
      variable: 'release_bundle',
      expected: androidApplicationId,
      failures: failures,
    );
    _requireDerivedDebugIdentity(
      androidIntegration,
      label: 'Android integration wrapper',
      variable: 'test_package',
      releaseVariable: 'release_package',
      failures: failures,
    );
    _requireDerivedDebugIdentity(
      iosIntegration,
      label: 'iOS integration wrapper',
      variable: 'test_bundle',
      releaseVariable: 'release_bundle',
      failures: failures,
    );
  }
  if (iosIntegration != null) {
    _requireSinglePattern(
      iosIntegration,
      RegExp(
        r'^readonly built_test_app="\$\{root\}/build/ios/'
        r'iphonesimulator/Runner\.app"\s*$',
        multiLine: true,
      ),
      'iOS integration must inspect the exact built test application.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(r'plutil -extract CFBundleIdentifier raw'),
      'iOS integration must inspect the built test bundle identifier.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(
        r'xcrun simctl install "\$\{simulator_id\}" "\$\{built_test_app\}"',
      ),
      'iOS integration must install the exact built debug artifact.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(
        r'^\s*local restored_app="\$\{root\}/build/ios/'
        r'iphonesimulator/Runner\.app"\s*$',
        multiLine: true,
      ),
      'iOS integration must own the ordinary app restoration artifact.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(r'xcrun simctl install "\$\{simulator_id\}" "\$\{restored_app\}"'),
      'iOS integration must restore the ordinary installed debug app.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(
        r'^readonly test_path_after="\$\(bundle_path "\$\{test_bundle\}"\)"\s*$',
        multiLine: true,
      ),
      'iOS integration must inspect the installed debug bundle.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(r'fail "the isolated debug bundle was not installed"'),
      'iOS integration must fail when its debug bundle is absent.',
      failures,
    );
  }

  final podLock = _readRequired(
    File('$root/ios/Podfile.lock'),
    'ios/Podfile.lock',
    failures,
  );
  final cocoaPodsVersion = podLock == null
      ? null
      : _readSingleCapture(
          podLock,
          RegExp(r'^COCOAPODS: ([0-9]+\.[0-9]+\.[0-9]+)\s*$', multiLine: true),
          'CocoaPods lock version',
          failures,
        );
  final gemfile = _readRequired(File('$root/Gemfile'), 'Gemfile', failures);
  final gemfileLock = _readRequired(
    File('$root/Gemfile.lock'),
    'Gemfile.lock',
    failures,
  );
  String? bundlerVersion;
  if (cocoaPodsVersion != null && gemfile != null) {
    _verifyGemfile(
      gemfile,
      cocoaPodsVersion: cocoaPodsVersion,
      failures: failures,
    );
  }
  if (gemfileLock != null) {
    bundlerVersion = _verifyBundlerLock(
      gemfileLock,
      cocoaPodsVersion: cocoaPodsVersion,
      failures: failures,
    );
  }

  final makefile = _readRequired(File('$root/Makefile'), 'Makefile', failures);
  if (makefile != null) {
    if (bundlerVersion != null) {
      _requireSinglePattern(
        makefile,
        RegExp(
          '^BUNDLER_VERSION := ${RegExp.escape(bundlerVersion)}\\s*\$',
          multiLine: true,
        ),
        'Makefile must require Bundler $bundlerVersion.',
        failures,
      );
    }
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^\s*fvm flutter pub get --enforce-lockfile\s*$',
        multiLine: true,
      ),
      'Makefile dependency setup must enforce the committed Pub lockfile.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(r'^ios-dependencies:\s*$', multiLine: true),
      'Makefile must own one locked iOS dependency bootstrap target.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(r'\bbundle check\b[^\n]*\|\|[^\n]*\bbundle install\b'),
      'iOS dependency bootstrap must check before installing Gemfile.lock.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^ios-native-test:\s+dependencies ios-dependencies\s*$',
        multiLine: true,
      ),
      'iOS native tests must bootstrap Pub and locked Ruby dependencies.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(r'^ios-storage-test:\s+ios-dependencies\s*$', multiLine: true),
      'iOS integration tests must bootstrap locked Ruby dependencies.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(r'^run-ios:\s+dependencies ios-dependencies\s*$', multiLine: true),
      'Interactive iOS builds must bootstrap locked Pub and Ruby dependencies.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^\s*BUNDLE_FROZEN=true BUNDLE_PATH="\$\(BUNDLE_PATH\)" '
        r'bundle exec fvm flutter run --no-pub -d '
        r'"\$\(IOS_SIMULATOR_ID\)"\s*$',
        multiLine: true,
      ),
      'Interactive iOS builds must execute Flutter inside the Ruby bundle.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(r'^run-android:\s+dependencies\s*$', multiLine: true),
      'Interactive Android builds must enforce the committed Pub lock.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^\s*fvm flutter run --no-pub -d '
        r'"\$\(ANDROID_DEVICE_ID\)"\s*$',
        multiLine: true,
      ),
      'Interactive Android builds must require an explicit device.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^\s*BUNDLE_FROZEN=true BUNDLE_PATH="\$\(BUNDLE_PATH\)" '
        r'bundle exec fvm flutter '
        r'build ios --simulator --debug --config-only --no-pub\s*$',
        multiLine: true,
      ),
      'iOS native bootstrap must execute Flutter inside the Ruby bundle.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^prepare-android-release:\s*$\n'
        r'\tfvm flutter clean\s*$\n'
        r'\t@\$\(MAKE\) --no-print-directory dependencies\s*$\n'
        r'\tfvm dart run tool/prepare_android_release\.dart\s*$',
        multiLine: true,
      ),
      'Android Release preparation must clean, resolve the exact lock, and '
      'then run the guarded plugin tool in order.',
      failures,
    );
    for (final target in ['android-release-bundle', 'android-release-apks']) {
      _requireSinglePattern(
        makefile,
        RegExp('^$target:\\s+prepare-android-release\\s*\$', multiLine: true),
        '$target must depend on guarded Release plugin preparation.',
        failures,
      );
    }
  }
  if (iosIntegration != null) {
    if (bundlerVersion != null) {
      _requireSinglePattern(
        iosIntegration,
        RegExp(
          '^readonly bundler_version="${RegExp.escape(bundlerVersion)}"\\s*\$',
          multiLine: true,
        ),
        'iOS integration must require Bundler $bundlerVersion.',
        failures,
      );
    }
    _requireSinglePattern(
      iosIntegration,
      RegExp(r'^export BUNDLE_FROZEN=true\s*$', multiLine: true),
      'iOS integration must prevent Gemfile.lock mutation.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(r'^bundle check >/dev/null 2>&1 \|\|\s*$', multiLine: true),
      'iOS integration must fail closed when locked gems are unavailable.',
      failures,
    );
    for (final command in <String>[
      'pub get --enforce-lockfile',
      'build ios --simulator --debug --no-pub',
      'test --no-pub',
    ]) {
      _requireSinglePattern(
        iosIntegration,
        RegExp('bundle exec fvm flutter ${RegExp.escape(command)}'),
        'iOS integration must run `$command` inside the Ruby bundle.',
        failures,
      );
    }
  }

  final apkVerifier = _readRequired(
    File('$root/scripts/verify-android-release-apks.sh'),
    'scripts/verify-android-release-apks.sh',
    failures,
  );
  if (apkVerifier != null) {
    _requireSinglePattern(
      apkVerifier,
      RegExp(r'fvm dart run tool/verify_android_release_identity\.dart'),
      'APK verification must enforce committed release identity.',
      failures,
    );
    _requireSinglePattern(
      apkVerifier,
      RegExp(r'--aapt2 "\$\{UTEXO_AAPT2\}"'),
      'APK identity verification must use the resolved aapt2 binary.',
      failures,
    );
  }
  final bundleVerifier = _readRequired(
    File('$root/scripts/verify-android-release-bundle.sh'),
    'scripts/verify-android-release-bundle.sh',
    failures,
  );
  if (bundleVerifier != null) {
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'fvm dart run tool/verify_android_release_identity\.dart'),
      'Bundle verification must enforce committed release identity.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'--aapt2-proto "\$\{UTEXO_AAPT2_PROTO_JAR\}"'),
      'Bundle identity verification must use the resolved aapt2 schema.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'--protobuf "\$\{UTEXO_PROTOBUF_JAR\}"'),
      'Bundle identity verification must use the resolved protobuf runtime.',
      failures,
    );
  }

  final pubspec = _readRequired(
    File('$root/pubspec.yaml'),
    'pubspec.yaml',
    failures,
  );
  if (pubspec != null && dartVersion != null) {
    _requireSinglePattern(
      pubspec,
      RegExp(
        '^  sdk: ">=${RegExp.escape(dartVersion)} <4\\.0\\.0"\\s*\$',
        multiLine: true,
      ),
      'pubspec.yaml must require Dart >=$dartVersion <4.0.0.',
      failures,
    );
  }
  if (pubspec != null && flutterVersion != null) {
    _requireSinglePattern(
      pubspec,
      RegExp(
        '^  flutter: ">=${RegExp.escape(flutterVersion)}"\\s*\$',
        multiLine: true,
      ),
      'pubspec.yaml must require Flutter >=$flutterVersion.',
      failures,
    );
  }

  final development = _readRequired(
    File('$root/docs/DEVELOPMENT.md'),
    'docs/DEVELOPMENT.md',
    failures,
  );
  if (development != null &&
      ndkVersion != null &&
      !development.contains('Android NDK $ndkVersion')) {
    failures.add('docs/DEVELOPMENT.md must document Android NDK $ndkVersion.');
  }
  if (development != null &&
      gradleVersion != null &&
      agpVersion != null &&
      kotlinVersion != null &&
      !development.contains(
        'Gradle $gradleVersion, Android Gradle Plugin $agpVersion, and '
        'Kotlin $kotlinVersion',
      )) {
    failures.add(
      'docs/DEVELOPMENT.md must document Flutter\'s Android build chain.',
    );
  }
  if (development != null &&
      compileSdk != null &&
      buildToolsVersion != null &&
      platformToolsVersion != null &&
      !development.contains(
        'Android SDK platform $compileSdk, build tools $buildToolsVersion, '
        'and platform tools $platformToolsVersion',
      )) {
    failures.add(
      'docs/DEVELOPMENT.md must document the Android SDK/build-tools chain.',
    );
  }
  if (development != null &&
      flutterVersion != null &&
      dartVersion != null &&
      !development.contains('Flutter $flutterVersion and Dart $dartVersion')) {
    failures.add(
      'docs/DEVELOPMENT.md must document the Flutter/Dart versions.',
    );
  }
  if (development != null &&
      cocoaPodsVersion != null &&
      bundlerVersion != null &&
      !development.contains(
        'CocoaPods $cocoaPodsVersion through Bundler $bundlerVersion',
      )) {
    failures.add(
      'docs/DEVELOPMENT.md must document the CocoaPods/Bundler versions.',
    );
  }
  if (development != null && androidApplicationId != null) {
    for (final identity in <String>[
      '$androidApplicationId.debug',
      '$androidApplicationId.profile',
      androidApplicationId,
    ]) {
      if (!development.contains('`$identity`')) {
        failures.add(
          'docs/DEVELOPMENT.md must document platform identity $identity.',
        );
      }
    }
  }

  failures.sort();
  return ToolchainVerification(
    flutterVersion: flutterVersion,
    dartVersion: dartVersion,
    flutterGradleVersion: gradleVersion,
    flutterAgpVersion: agpVersion,
    flutterKotlinVersion: kotlinVersion,
    flutterCompileSdk: compileSdk,
    flutterMinSdk: minSdk,
    flutterTargetSdk: targetSdk,
    flutterNdkVersion: ndkVersion,
    gradleDistributionSha256: gradleDistributionSha256,
    androidVerifiedArtifacts: androidVerifiedArtifacts,
    androidBuildToolsVersion: buildToolsVersion,
    androidPlatformToolsVersion: platformToolsVersion,
    androidApplicationId: androidApplicationId,
    cocoaPodsVersion: cocoaPodsVersion,
    bundlerVersion: bundlerVersion,
    failures: List.unmodifiable(failures),
  );
}

Map<String, Object?>? _readJsonObject(
  File? file,
  String label,
  List<String> failures,
) {
  final contents = _readRequired(file, label, failures);
  if (contents == null) return null;
  try {
    final decoded = jsonDecode(contents);
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // The deterministic failure below owns malformed metadata.
  }
  failures.add('$label must contain one JSON object.');
  return null;
}

int _verifyGradleDependencyMetadata(File file, List<String> failures) {
  final contents = _readRequired(
    file,
    'android/gradle/verification-metadata.xml',
    failures,
  );
  if (contents == null) return 0;

  try {
    final document = XmlDocument.parse(contents);
    final root = document.rootElement;
    const namespace = 'https://schema.gradle.org/dependency-verification';
    if (root.name.local != 'verification-metadata' ||
        root.name.namespaceUri != namespace) {
      failures.add('Gradle verification metadata has an invalid root.');
      return 0;
    }

    final rootChildren = root.childElements.toList();
    final configurations = rootChildren
        .where(
          (element) =>
              element.name.local == 'configuration' &&
              element.name.namespaceUri == namespace,
        )
        .toList();
    final componentContainers = rootChildren
        .where(
          (element) =>
              element.name.local == 'components' &&
              element.name.namespaceUri == namespace,
        )
        .toList();
    if (rootChildren.length != 2 ||
        configurations.length != 1 ||
        componentContainers.length != 1) {
      failures.add(
        'Gradle verification metadata must contain one configuration and '
        'one components container.',
      );
      return 0;
    }

    final configuration = configurations.single;
    final options = <String, String>{};
    for (final option in configuration.childElements) {
      if (option.name.namespaceUri != namespace) {
        failures.add('Gradle verification contains a foreign option.');
        continue;
      }
      final name = option.name.local;
      if (options.containsKey(name)) {
        failures.add('Gradle verification option $name is duplicated.');
        continue;
      }
      options[name] = option.innerText.trim();
    }
    if (options.length != 2 ||
        options['verify-metadata'] != 'true' ||
        options['verify-signatures'] != 'false') {
      failures.add(
        'Gradle dependency verification must use strict metadata SHA-256 '
        'checks without broad trust exceptions.',
      );
    }

    final componentKeys = <String>{};
    var artifactCount = 0;
    for (final component in componentContainers.single.childElements) {
      if (component.name.local != 'component' ||
          component.name.namespaceUri != namespace) {
        failures.add('Gradle components contain an unexpected element.');
        continue;
      }
      final group = component.getAttribute('group');
      final name = component.getAttribute('name');
      final version = component.getAttribute('version');
      if ([
        group,
        name,
        version,
      ].any((value) => value == null || value.isEmpty)) {
        failures.add(
          'Gradle verification contains an unidentifiable component.',
        );
        continue;
      }
      final componentKey = '$group:$name:$version';
      if (!componentKeys.add(componentKey)) {
        failures.add('Gradle verification duplicates $componentKey.');
      }

      final artifactNames = <String>{};
      final artifacts = component.childElements.toList();
      if (artifacts.isEmpty) {
        failures.add('Gradle verification component $componentKey is empty.');
      }
      for (final artifact in artifacts) {
        if (artifact.name.local != 'artifact' ||
            artifact.name.namespaceUri != namespace) {
          failures.add('$componentKey contains an unexpected element.');
          continue;
        }
        final artifactName = artifact.getAttribute('name');
        if (artifactName == null || artifactName.isEmpty) {
          failures.add('$componentKey contains an unnamed artifact.');
          continue;
        }
        if (!artifactNames.add(artifactName)) {
          failures.add('$componentKey duplicates artifact $artifactName.');
        }
        final checksums = artifact.childElements.toList();
        if (checksums.length != 1 ||
            checksums.single.name.local != 'sha256' ||
            checksums.single.name.namespaceUri != namespace) {
          failures.add(
            '$componentKey:$artifactName must use exactly one SHA-256 checksum.',
          );
          continue;
        }
        final value = checksums.single.getAttribute('value');
        if (value == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
          failures.add(
            '$componentKey:$artifactName has an invalid SHA-256 checksum.',
          );
        }
        artifactCount += 1;
      }
    }
    if (artifactCount == 0) {
      failures.add('Gradle verification metadata contains no artifacts.');
    }
    return artifactCount;
  } on XmlParserException {
    failures.add('Gradle verification metadata is malformed XML.');
    return 0;
  }
}

void _verifyGemfile(
  String gemfile, {
  required String cocoaPodsVersion,
  required List<String> failures,
}) {
  _requireSinglePattern(
    gemfile,
    RegExp(r'^source "https://rubygems\.org"\s*$', multiLine: true),
    'Gemfile HTTPS RubyGems source',
    failures,
  );
  _requireSinglePattern(
    gemfile,
    RegExp(
      '^gem "cocoapods", "${RegExp.escape(cocoaPodsVersion)}"\\s*\$',
      multiLine: true,
    ),
    'Gemfile must pin CocoaPods $cocoaPodsVersion exactly',
    failures,
  );
  final activeLines = gemfile
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
  final expectedLines = <String>[
    'source "https://rubygems.org"',
    'gem "cocoapods", "$cocoaPodsVersion"',
  ];
  if (activeLines.length != expectedLines.length ||
      activeLines.indexed.any((entry) => entry.$2 != expectedLines[entry.$1])) {
    failures.add(
      'Gemfile must contain only the reviewed RubyGems source and exact '
      'CocoaPods dependency.',
    );
  }
}

String? _verifyBundlerLock(
  String lock, {
  required String? cocoaPodsVersion,
  required List<String> failures,
}) {
  final sectionHeaders = RegExp(
    r'^[A-Z][A-Z ]*$',
    multiLine: true,
  ).allMatches(lock).map((match) => match.group(0)!).toList();
  const expectedSections = <String>[
    'GEM',
    'PLATFORMS',
    'DEPENDENCIES',
    'CHECKSUMS',
    'BUNDLED WITH',
  ];
  if (sectionHeaders.length != expectedSections.length ||
      sectionHeaders.indexed.any(
        (entry) => entry.$2 != expectedSections[entry.$1],
      )) {
    failures.add('Gemfile.lock contains an unexpected dependency source.');
  }

  _requireSinglePattern(
    lock,
    RegExp(r'^  remote: https://rubygems\.org/\s*$', multiLine: true),
    'Gemfile.lock must use only the HTTPS RubyGems source.',
    failures,
  );
  if (RegExp(r'^  remote: .+$', multiLine: true).allMatches(lock).length != 1) {
    failures.add('Gemfile.lock must declare exactly one gem source.');
  }
  if (cocoaPodsVersion != null) {
    _requireSinglePattern(
      lock,
      RegExp(
        '^    cocoapods \\(${RegExp.escape(cocoaPodsVersion)}\\)\\s*\$',
        multiLine: true,
      ),
      'Gemfile.lock must resolve CocoaPods $cocoaPodsVersion exactly.',
      failures,
    );
    _requireSinglePattern(
      lock,
      RegExp(
        '^  cocoapods \\(= ${RegExp.escape(cocoaPodsVersion)}\\)\\s*\$',
        multiLine: true,
      ),
      'Gemfile.lock must retain the exact CocoaPods dependency constraint.',
      failures,
    );
    _requireSinglePattern(
      lock,
      RegExp(
        '^  cocoapods \\(${RegExp.escape(cocoaPodsVersion)}\\) '
        r'sha256=[0-9a-f]{64}\s*$',
        multiLine: true,
      ),
      'Gemfile.lock must checksum CocoaPods $cocoaPodsVersion.',
      failures,
    );
  }

  final platformSection = RegExp(
    r'^PLATFORMS\s*$([\s\S]*?)^DEPENDENCIES\s*$',
    multiLine: true,
  ).firstMatch(lock)?.group(1);
  final platforms = platformSection
      ?.split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  const expectedPlatforms = <String>['arm64-darwin', 'ruby', 'x86_64-darwin'];
  if (platforms == null ||
      platforms.length != expectedPlatforms.length ||
      platforms.indexed.any(
        (entry) => entry.$2 != expectedPlatforms[entry.$1],
      )) {
    failures.add(
      'Gemfile.lock must support exactly arm64, x86_64, and generic Ruby.',
    );
  }

  final gemSection = RegExp(
    r'^GEM\s*$([\s\S]*?)^PLATFORMS\s*$',
    multiLine: true,
  ).firstMatch(lock)?.group(1);
  final checksumSection = RegExp(
    r'^CHECKSUMS\s*$([\s\S]*?)^BUNDLED WITH\s*$',
    multiLine: true,
  ).firstMatch(lock)?.group(1);
  final gemKeys = <String>{};
  var invalidGemEntry = false;
  if (gemSection != null) {
    for (final line in gemSection.split('\n')) {
      if (!line.startsWith('    ') || line.startsWith('      ')) continue;
      final match = RegExp(r'^    ([A-Za-z0-9_.-]+ \([^)]+\))$')
          .firstMatch(line);
      if (match == null || !gemKeys.add(match.group(1)!)) {
        invalidGemEntry = true;
      }
    }
  }

  final checksumKeys = <String>{};
  var invalidChecksumEntry = false;
  if (checksumSection != null) {
    for (final line in checksumSection.split('\n')) {
      if (line.trim().isEmpty) continue;
      final match = RegExp(
        r'^  ([A-Za-z0-9_.-]+ \([^)]+\)) sha256=[0-9a-f]{64}$',
      ).firstMatch(line);
      if (match == null || !checksumKeys.add(match.group(1)!)) {
        invalidChecksumEntry = true;
      }
    }
  }
  if (gemKeys.isEmpty ||
      invalidGemEntry ||
      invalidChecksumEntry ||
      gemKeys.length != checksumKeys.length ||
      !gemKeys.containsAll(checksumKeys) ||
      !checksumKeys.containsAll(gemKeys)) {
    failures.add('Every locked Ruby gem must carry one SHA-256 checksum.');
  }

  final dependencySection = RegExp(
    r'^DEPENDENCIES\s*$([\s\S]*?)^CHECKSUMS\s*$',
    multiLine: true,
  ).firstMatch(lock)?.group(1);
  final dependencies = dependencySection
      ?.split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final expectedDependency = cocoaPodsVersion == null
      ? null
      : 'cocoapods (= $cocoaPodsVersion)';
  if (expectedDependency != null &&
      (dependencies == null ||
          dependencies.length != 1 ||
          dependencies.single != expectedDependency)) {
    failures.add('Gemfile.lock must contain only the CocoaPods dependency.');
  }

  return _readSingleCapture(
    lock,
    RegExp(
      r'^BUNDLED WITH\s*\n  ([0-9]+\.[0-9]+\.[0-9]+)\s*$',
      multiLine: true,
    ),
    'Bundler lock version',
    failures,
  );
}

void _requireIntegrationIdentity(
  String? contents, {
  required String label,
  required String variable,
  required String expected,
  required List<String> failures,
}) {
  if (contents == null) return;
  _requireSinglePattern(
    contents,
    RegExp(
      '^readonly ${RegExp.escape(variable)}="${RegExp.escape(expected)}"\\s*\$',
      multiLine: true,
    ),
    '$label must use release identity $expected.',
    failures,
  );
}

void _requireDerivedDebugIdentity(
  String? contents, {
  required String label,
  required String variable,
  required String releaseVariable,
  required List<String> failures,
}) {
  if (contents == null) return;
  _requireSinglePattern(
    contents,
    RegExp(
      '^readonly ${RegExp.escape(variable)}="\\\$\\{'
      '${RegExp.escape(releaseVariable)}\\}\\.debug"\\s*\$',
      multiLine: true,
    ),
    '$label must derive its debug identity from $releaseVariable.',
    failures,
  );
}

String? _readJsonString(
  Map<String, Object?>? object,
  String key,
  String label,
  List<String> failures,
) {
  if (object == null) return null;
  final value = object[key];
  if (value is String && value.isNotEmpty) return value;
  failures.add('$label is not inspectable.');
  return null;
}

int? _readKotlinIntProperty(
  String? contents,
  String name,
  String label,
  List<String> failures,
) {
  if (contents == null) return null;
  final value = _readSingleCapture(
    contents,
    RegExp('val\\s+$name\\s*:\\s*Int\\s*=\\s*(\\d+)'),
    label,
    failures,
  );
  return value == null ? null : int.parse(value);
}

String? _readSingleCapture(
  String contents,
  RegExp pattern,
  String label,
  List<String> failures,
) {
  final matches = pattern.allMatches(contents).toList();
  final value = matches.length == 1 ? matches.single.group(1) : null;
  if (value == null) {
    failures.add('Expected one inspectable $label, found ${matches.length}.');
  }
  return value;
}

void _requireSinglePattern(
  String contents,
  RegExp pattern,
  String message,
  List<String> failures,
) {
  if (pattern.allMatches(contents).length != 1) failures.add(message);
}

void _requireSingleCapturedValue(
  String contents,
  RegExp pattern,
  String expected,
  String label,
  List<String> failures,
) {
  final values = pattern
      .allMatches(contents)
      .map((match) => match.group(1))
      .toList();
  if (values.length != 1 || values.single != expected) {
    failures.add('$label must be exactly $expected.');
  }
}

void _requireNixVersionList(
  String flake, {
  required String property,
  required String? expected,
  required String label,
  required List<String> failures,
}) {
  if (expected == null) return;
  final versions = RegExp(
    '\\b${RegExp.escape(property)}\\s*=\\s*\\[\\s*"([^"]+)"\\s*\\]\\s*;',
  ).allMatches(flake).map((match) => match.group(1)).toList();
  if (versions.length != 1 || versions.single != expected) {
    failures.add('flake.nix must declare exactly $label $expected.');
  }
}

void _requireJsonValue(
  Map<String, Object?>? object, {
  required String key,
  required String? expected,
  required String label,
  required List<String> failures,
}) {
  if (object == null || expected == null) return;
  if (object[key] != expected) {
    failures.add('$label must be exactly $expected.');
  }
}

String? _readDartStringConstant(
  String? contents,
  String name,
  String label,
  List<String> failures,
) {
  if (contents == null) return null;
  final value = RegExp("const\\s+$name\\s*=\\s*'([^']+)'")
      .firstMatch(contents)
      ?.group(1);
  if (value == null) failures.add('$label is not inspectable.');
  return value;
}

void _requirePluginVersion(
  String settings, {
  required String plugin,
  required String? expected,
  required String label,
  required List<String> failures,
}) {
  if (expected == null) return;
  final matches = RegExp(
    'id\\("${RegExp.escape(plugin)}"\\)\\s+version\\s+"([^"]+)"',
  ).allMatches(settings).map((match) => match.group(1)!).toList();
  if (matches.length != 1 || matches.single != expected) {
    failures.add(
      'android/settings.gradle.kts must declare exactly $label $expected.',
    );
  }
}

void _verifyFlutterSplitVersioning({
  required String? constants,
  required String? plugin,
  required List<String> failures,
}) {
  if (constants != null) {
    final actual = <String, int>{};
    for (final match in RegExp(
      r'ARCH_(ARM32|ARM64|X86_64)\s+to\s+([0-9]+)',
    ).allMatches(constants)) {
      final abi = match.group(1)!;
      if (actual.containsKey(abi)) {
        failures.add('Flutter split-ABI version map contains duplicate $abi.');
        continue;
      }
      actual[abi] = int.parse(match.group(2)!);
    }
    const expected = {'ARM32': 1, 'ARM64': 2, 'X86_64': 4};
    if (actual.length != expected.length ||
        expected.entries.any((entry) => actual[entry.key] != entry.value)) {
      failures.add(
        'Flutter split-ABI version map differs from the artifact verifier.',
      );
    }
  }
  if (plugin != null &&
      !RegExp(r'versionCodeOverride\s*=\s*abiVersionCode\s*\*\s*1000\s*\+')
          .hasMatch(plugin)) {
    failures.add(
      'Flutter split-ABI version-code multiplier differs from the artifact '
      'verifier.',
    );
  }
}

File? _locateFlutterExtension(String dartExecutable) {
  return _locateFlutterFile(
    dartExecutable,
    'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt',
  );
}

File? _locateFlutterVersionMetadata(String dartExecutable) {
  return _locateFlutterFile(dartExecutable, 'bin/cache/flutter.version.json');
}

File? _locateFlutterGradleUtils(String dartExecutable) {
  return _locateFlutterFile(
    dartExecutable,
    'packages/flutter_tools/lib/src/android/gradle_utils.dart',
  );
}

File? _locateFlutterFile(String dartExecutable, String relativePath) {
  var candidate = File(dartExecutable).absolute.parent;
  while (candidate.parent.path != candidate.path) {
    final file = File('${candidate.path}/$relativePath');
    if (file.existsSync()) return file;
    candidate = candidate.parent;
  }
  return null;
}

String? _readRequired(File? file, String label, List<String> failures) {
  if (file == null || !file.existsSync()) {
    failures.add('Missing $label.');
    return null;
  }
  try {
    return file.readAsStringSync();
  } on FileSystemException {
    failures.add('Could not read $label.');
    return null;
  }
}
