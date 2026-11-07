import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'gradle_verification_metadata.dart';

const _reviewedGradleDistributionSha256 = <String, String>{
  '9.3.1': '17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43',
};

// Android 17 needs API 37 and AGP 9.1.1 before Flutter's API 36 defaults catch up.
// AGP 9.1.1 supports SDK build tools 36.0.0; their major need not match the API.
// https://developer.android.com/build/releases/agp-9-1-0-release-notes
const _reviewedAndroidSdk = 37;
const _reviewedAndroidSdkPlatform = '37.0';
const _reviewedAndroidAgp = '9.1.1';
const _reviewedAndroidBuildTools = '36.0.0';
const _reviewedNkfVersion = '0.3.0';
const _reviewedNkfSha256 =
    '357a8dbeba38b727b75930f665146546076a394a1c243faf634ff176e3588895';

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

  /// Whether every owned toolchain surface agrees with the reviewed contract.
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
    'AGP $_reviewedAndroidAgp, Kotlin ${result.flutterKotlinVersion}, '
    'Android SDK $_reviewedAndroidSdk, build tools '
    '${result.androidBuildToolsVersion}, platform tools '
    '${result.androidPlatformToolsVersion}, NDK '
    '${result.flutterNdkVersion}, CocoaPods ${result.cocoaPodsVersion}, and '
    'Bundler ${result.bundlerVersion}.',
  );
}

/// Checks the reviewed platform contract and executing Flutter SDK together.
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
            r'^aster\.applicationId='
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
      RegExp(r'id\("com\.android\.built-in-kotlin"\)'),
      'Aster Android app module must apply AGP built-in Kotlin.',
      failures,
    );
    if (RegExp(r'id\("(?:kotlin-android|org\.jetbrains\.kotlin\.android)"\)')
        .hasMatch(android)) {
      failures.add(
        'Aster Android app module must not apply the legacy Kotlin Gradle '
        'plugin.',
      );
    }
    _requireSinglePattern(
      android,
      RegExp(
        r'val\s+asterApplicationId\s*=\s*providers\.gradleProperty\('
        r'"aster\.applicationId"\)\.get\(\)',
      ),
      'Android application ID must come from the owned Gradle property.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bnamespace\s*=\s*asterApplicationId\b'),
      'Android namespace must use the owned application ID.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp(r'\bapplicationId\s*=\s*asterApplicationId\b'),
      'Android release application ID must use the owned property.',
      failures,
    );
    _requireSinglePattern(
      android,
      RegExp('\\bcompileSdk\\s*=\\s*$_reviewedAndroidSdk\\b'),
      'android/app/build.gradle.kts must pin compileSdk to reviewed '
      'Android $_reviewedAndroidSdk.',
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
      RegExp('\\btargetSdk\\s*=\\s*$_reviewedAndroidSdk\\b'),
      'android/app/build.gradle.kts must pin targetSdk to reviewed '
      'Android $_reviewedAndroidSdk.',
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
    if (buildToolsVersion != null &&
        buildToolsVersion != _reviewedAndroidBuildTools) {
      failures.add(
        'Android build tools $buildToolsVersion must use reviewed '
        '$_reviewedAndroidBuildTools for AGP $_reviewedAndroidAgp.',
      );
    }
  }

  if (androidProperties != null) {
    _requireSinglePattern(
      androidProperties,
      RegExp(r'^android\.builtInKotlin=false\s*$', multiLine: true),
      'Android must keep global built-in Kotlin disabled only for unmigrated '
      'dependency modules.',
      failures,
    );
    _requireSinglePattern(
      androidProperties,
      RegExp(r'^android\.newDsl=false\s*$', multiLine: true),
      'Android must keep the legacy DSL compatibility flag explicit while '
      'dependency modules require it.',
      failures,
    );
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
      expected: _reviewedAndroidAgp,
      label: 'Android Gradle Plugin',
      failures: failures,
    );
    _requirePluginVersion(
      settings,
      plugin: 'com.android.built-in-kotlin',
      expected: _reviewedAndroidAgp,
      label: 'Android built-in Kotlin plugin',
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
      expected: _reviewedAndroidSdkPlatform,
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

  if (flake != null) {
    _requireSinglePattern(
      flake,
      RegExp(r'commonBuildInputs[\s\S]*?\bpython3\b'),
      'Nix development shells must provide Python 3 for process ownership.',
      failures,
    );
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
        RegExp.escape(
          "python3 -I -S -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 69)'",
        ),
      ),
      'Quality CI must verify the isolated Python 3.9 process supervisor runtime.',
      failures,
    );
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
  final androidPackageState = _readRequired(
    File('$root/scripts/android-package-state.sh'),
    'scripts/android-package-state.sh',
    failures,
  );
  final androidPerformance = _readRequired(
    File('$root/scripts/run-android-presentation-performance-test.sh'),
    'scripts/run-android-presentation-performance-test.sh',
    failures,
  );
  final androidPerformanceRenderer = _readRequired(
    File('$root/scripts/verify-android-performance-renderer.sh'),
    'scripts/verify-android-performance-renderer.sh',
    failures,
  );
  final presentationPerformanceTest = _readRequired(
    File('$root/integration_test/presentation_performance_test.dart'),
    'integration_test/presentation_performance_test.dart',
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
      androidPerformance,
      label: 'Android performance wrapper',
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
    _requireDerivedIdentity(
      androidIntegration,
      label: 'Android integration wrapper',
      variable: 'test_package',
      releaseVariable: 'release_package',
      suffix: 'debug',
      failures: failures,
    );
    _requireDerivedIdentity(
      iosIntegration,
      label: 'iOS integration wrapper',
      variable: 'test_bundle',
      releaseVariable: 'release_bundle',
      suffix: 'debug',
      failures: failures,
    );
    _requireDerivedIdentity(
      androidPerformance,
      label: 'Android performance wrapper',
      variable: 'profile_package',
      releaseVariable: 'release_package',
      suffix: 'profile',
      failures: failures,
    );
  }
  if (androidIntegration != null) {
    _requireSinglePattern(
      androidIntegration,
      RegExp(r'^trap cleanup EXIT\s*$', multiLine: true),
      'Android integration must install fail-safe EXIT cleanup.',
      failures,
    );
    _requireSinglePattern(
      androidIntegration,
      RegExp(
        r'"\$\{adb\}" -s "\$\{device_id\}" shell am force-stop \\\s*\n'
        r'\s*"\$\{test_package\}"',
        multiLine: true,
      ),
      'Android integration cleanup must stop only its debug package.',
      failures,
    );
    _requireSinglePattern(
      androidIntegration,
      RegExp(
        r'^\(\(test_status == 0\)\) \|\| exit "\$\{test_status\}"\s*$',
        multiLine: true,
      ),
      'Android integration must preserve the drive failure before artifact '
      'verification.',
      failures,
    );
    _requireSinglePattern(
      androidIntegration,
      RegExp(
        r'^release_path_before="\$\(package_path "\$\{release_package\}"\)" '
        r'\|\|\s*$',
        multiLine: true,
      ),
      'Android integration must fail when its pre-launch release identity '
      'query fails.',
      failures,
    );
    _requireSinglePattern(
      androidIntegration,
      RegExp(
        r'^\s*if ! release_path_after="\$\(package_path '
        r'"\$\{release_package\}"\)"; then\s*$',
        multiLine: true,
      ),
      'Android integration cleanup must distinguish a failed release query '
      'from an absent package.',
      failures,
    );
  }
  for (final wrapper in <({String label, String? contents})>[
    (label: 'Android integration wrapper', contents: androidIntegration),
    (label: 'Android performance wrapper', contents: androidPerformance),
  ]) {
    if (wrapper.contents == null) continue;
    _requireSinglePattern(
      wrapper.contents!,
      RegExp(
        RegExp.escape(r'source "${root}/scripts/android-package-state.sh"'),
      ),
      '${wrapper.label} must source the shared package-state boundary.',
      failures,
    );
    _requireSinglePattern(
      wrapper.contents!,
      RegExp(
        RegExp.escape(
          r'aster_android_package_paths "${adb}" "${device_id}" "$1"',
        ),
      ),
      '${wrapper.label} must delegate package discovery to the shared '
      'boundary.',
      failures,
    );
  }
  if (androidPackageState != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(
          r'^aster_android_package_paths\(\) \{$',
          multiLine: true,
        ),
        failure: 'Android package-state inspection must expose one owned API.',
      ),
      (
        pattern: RegExp(r'^\s*set -o pipefail\s*$', multiLine: true),
        failure:
            'Android package-state inspection must preserve every '
            'pipeline failure.',
      ),
      (
        pattern: RegExp(r'^\s*\[\[ "\$\{package_name\}" =~ ', multiLine: true),
        failure:
            'Android package-state inspection must validate package identity.',
      ),
      (
        pattern: RegExp(
          r'aster_bounded_capture[\s\S]*?'
          r'"\$1" -s "\$2" shell pm path "\$3"',
        ),
        failure:
            'Android package-state inspection must query the exact '
            'package through its bounded adb boundary.',
      ),
      (
        pattern: RegExp(r'consumed \+= length\(\$0\) \+ 1'),
        failure: 'Android package-state inspection must account for every input byte.',
      ),
      (
        pattern: RegExp(r'if \(consumed > 65536\) exit 65'),
        failure:
            'Android package-state inspection must bound successful '
            'package-manager output.',
      ),
      (
        pattern: RegExp(RegExp.escape(r'sub(/\r$/, "")')),
        failure:
            'Android package-state inspection must normalize only CRLF line '
            'terminators.',
      ),
      (
        pattern: RegExp(
          RegExp.escape(r'if ($0 !~ /^package:\/[^[:cntrl:]]+$/) exit 66'),
        ),
        failure:
            'Android package-state inspection must reject malformed '
            'package-manager output.',
      ),
      (
        pattern: RegExp(r'LC_ALL=C "\$5" -u'),
        failure:
            'Android package-state inspection must canonicalize one exact '
            'path set.',
      ),
    ]) {
      _requireSinglePattern(
        androidPackageState,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
    if (androidPackageState.contains('|| true')) {
      failures.add(
        'Android package-state inspection must not mask adb or parser failures.',
      );
    }
  }
  if (iosIntegration != null) {
    _requireSinglePattern(
      iosIntegration,
      RegExp(r'"\$1" simctl listapps "\$2" >"\$\{temporary_file\}"'),
      'iOS integration must query installed applications through a '
      'status-bearing bounded simctl boundary.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(r'"\$3" -lint "\$\{temporary_file\}" >/dev/null'),
      'iOS integration must validate the complete simctl application plist.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(
        RegExp.escape(r'escaped_identifier="${bundle_identifier//./\\.}"'),
      ),
      'iOS integration must escape bundle identifiers before plist key-path '
      'lookup.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(RegExp.escape(r'"$3" -extract "$6.Path" raw "${temporary_file}"')),
      'iOS integration must read the installed bundle path from validated '
      'plist data.',
      failures,
    );
    for (final query in <({String variable, String bundle, String label})>[
      (
        variable: 'release_path_before',
        bundle: 'release_bundle',
        label: 'pre-run release bundle',
      ),
      (
        variable: 'release_path_after',
        bundle: 'release_bundle',
        label: 'post-run release bundle',
      ),
      (
        variable: 'test_path_after',
        bundle: 'test_bundle',
        label: 'installed debug bundle',
      ),
      (
        variable: 'release_path_after_install',
        bundle: 'release_bundle',
        label: 'post-install release bundle',
      ),
    ]) {
      _requireSinglePattern(
        iosIntegration,
        RegExp(
          '^${RegExp.escape(query.variable)}="\\\$\\(bundle_path '
          '"\\\$\\{${RegExp.escape(query.bundle)}\\}"\\)" \\|\\|\\s*\$',
          multiLine: true,
        ),
        'iOS integration must fail explicitly when its ${query.label} query '
        'fails.',
        failures,
      );
    }
    if (iosIntegration.contains('get_app_container')) {
      failures.add(
        'iOS integration must not infer installation state from '
        'get_app_container diagnostics.',
      );
    }
    if (iosIntegration.contains('|| true')) {
      failures.add(
        'iOS integration must not mask simulator or bundle-inspection failures.',
      );
    }
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
      RegExp(r'"\$\{plutil_bin\}" -extract CFBundleIdentifier raw'),
      'iOS integration must inspect the built test bundle identifier.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(
        r'"\$\{xcrun_bin\}" simctl install '
        r'"\$\{simulator_id\}" "\$\{built_test_app\}"',
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
      RegExp(
        r'"\$\{xcrun_bin\}" simctl install '
        r'"\$\{simulator_id\}" "\$\{restored_app\}"',
      ),
      'iOS integration must restore the ordinary installed debug app.',
      failures,
    );
    _requireSinglePattern(
      iosIntegration,
      RegExp(r'^readonly test_path_after\s*$', multiLine: true),
      'iOS integration must make the inspected debug path immutable.',
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
  if (androidPerformance != null) {
    _verifyAndroidPerformanceWrapper(
      androidPerformance,
      benchmark: presentationPerformanceTest,
      makefile: makefile,
      rendererVerifier: androidPerformanceRenderer,
      failures: failures,
    );
  }
  if (makefile != null) {
    _requireSinglePattern(
      makefile,
      RegExp(
        RegExp.escape(
          "python3 -I -S -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 69)'",
        ),
      ),
      'Makefile setup must verify the isolated Python 3.9 process supervisor runtime.',
      failures,
    );
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
      RegExp(r'^\s*fvm dart run build_runner build\s*$', multiLine: true),
      'Makefile must own exactly one canonical generated-source build command.',
      failures,
    );
    for (final contract in <({String target, String prerequisite})>[
      (target: 'verify-generated', prerequisite: 'dependencies'),
      (target: 'watch', prerequisite: 'dependencies'),
      (target: 'build', prerequisite: 'verify-generated'),
      (target: 'run-ios', prerequisite: 'verify-generated'),
      (target: 'run-android', prerequisite: 'verify-generated'),
      (target: 'test', prerequisite: 'verify-generated'),
      (target: 'ios-native-test', prerequisite: 'verify-generated'),
      (target: 'android-native-test', prerequisite: 'verify-generated'),
      (target: 'ios-storage-test', prerequisite: 'verify-generated'),
      (target: 'android-storage-test', prerequisite: 'verify-generated'),
      (
        target: 'android-presentation-performance-test',
        prerequisite: 'verify-generated',
      ),
      (target: 'analyze', prerequisite: 'verify-generated'),
      (target: 'docs', prerequisite: 'verify-generated'),
      (target: 'verify', prerequisite: 'verify-generated'),
      (target: 'verify-toolchain', prerequisite: 'verify-generated'),
      (target: 'verify-architecture', prerequisite: 'verify-generated'),
      (target: 'verify-design-system', prerequisite: 'verify-generated'),
      (target: 'verify-barrels', prerequisite: 'verify-generated'),
      (target: 'lint', prerequisite: 'verify-generated'),
    ]) {
      _requireMakeTargetPrerequisite(
        makefile,
        target: contract.target,
        prerequisite: contract.prerequisite,
        failures: failures,
      );
    }
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^bootstrap:\s+clean\s*$\n'
        r'(?:\t[^\n]*\n)*?'
        r'\t@\$\(MAKE\) --no-print-directory verify-generated\s*$',
        multiLine: true,
      ),
      'Make bootstrap must clean before invoking canonical generated-source preparation.',
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
        r'^ios-native-test:\s+verify-generated ios-dependencies\s*$',
        multiLine: true,
      ),
      'iOS native tests must bootstrap generated Dart and locked Ruby dependencies.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^ios-storage-test:\s+verify-generated ios-dependencies\s*$',
        multiLine: true,
      ),
      'iOS integration tests must bootstrap generated Dart and locked Ruby dependencies.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^run-ios:\s+verify-generated ios-dependencies\s*$',
        multiLine: true,
      ),
      'Interactive iOS builds must bootstrap generated Dart and locked Ruby dependencies.',
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
      RegExp(r'^run-android:\s+verify-generated\s*$', multiLine: true),
      'Interactive Android builds must bootstrap generated Dart sources.',
      failures,
    );
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^android-native-test:\s+verify-generated\s*$\n'
        r'\tfvm flutter build apk --debug --no-pub\s*$\n'
        r'\tcd android && ./gradlew :app:testDebugUnitTest --no-daemon\s*$',
        multiLine: true,
      ),
      'Android native tests must compile the complete Debug APK before one no-daemon host-test run.',
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
        r'^prepare-android-release:'
        r'(?:\s+verify-release-configuration)?\s*$\n'
        r'\tfvm flutter clean\s*$\n'
        r'\t@\$\(MAKE\) --no-print-directory verify-generated\s*$\n'
        r'\tfvm dart run tool/prepare_android_release\.dart\s*$',
        multiLine: true,
      ),
      'Android Release preparation must clean, regenerate from the exact lock, '
      'and then run the guarded plugin tool in order.',
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
      RegExp(
        r'^aster_run_quick "\$\{bundle_bin\}" check '
        r'>/dev/null 2>&1 \|\|\s*$',
        multiLine: true,
      ),
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
        RegExp(
          RegExp.escape(r'"${bundle_bin}" exec fvm flutter ') +
              RegExp.escape(command),
        ),
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
  final apkSignatureVerifier = _readRequired(
    File('$root/scripts/verify-android-apk-signature.sh'),
    'scripts/verify-android-apk-signature.sh',
    failures,
  );
  final nativeLibraryVerifier = _readRequired(
    File('$root/scripts/verify-android-native-libraries.sh'),
    'scripts/verify-android-native-libraries.sh',
    failures,
  );
  final nativeLibraryExtractor = _readRequired(
    File('$root/scripts/AndroidNativeLibraryExtractor.java'),
    'scripts/AndroidNativeLibraryExtractor.java',
    failures,
  );
  final archiveEntryExtractor = _readRequired(
    File('$root/scripts/AndroidArchiveEntryExtractor.java'),
    'scripts/AndroidArchiveEntryExtractor.java',
    failures,
  );
  final manifestInspector = _readRequired(
    File('$root/scripts/AndroidManifestInspector.java'),
    'scripts/AndroidManifestInspector.java',
    failures,
  );
  final bundleConfigInspector = _readRequired(
    File('$root/scripts/BundleConfigInspector.java'),
    'scripts/BundleConfigInspector.java',
    failures,
  );
  final androidReleaseIdentityVerifier = _readRequired(
    File('$root/tool/verify_android_release_identity.dart'),
    'tool/verify_android_release_identity.dart',
    failures,
  );
  final boundedProcess = _readRequired(
    File('$root/tool/bounded_process.dart'),
    'tool/bounded_process.dart',
    failures,
  );
  final androidArtifactToolchainResolver = _readRequired(
    File('$root/tool/resolve_android_artifact_toolchain.dart'),
    'tool/resolve_android_artifact_toolchain.dart',
    failures,
  );
  final boundedDartTools =
      <({String label, bool ownsDescendants, String? source})>[
        (
          label: 'Dartdoc verification',
          ownsDescendants: true,
          source: _readRequired(
            File('$root/tool/verify_dartdoc.dart'),
            'tool/verify_dartdoc.dart',
            failures,
          ),
        ),
        (
          label: 'Android Release preparation',
          ownsDescendants: true,
          source: _readRequired(
            File('$root/tool/prepare_android_release.dart'),
            'tool/prepare_android_release.dart',
            failures,
          ),
        ),
        (
          label: 'Production tracker verification',
          ownsDescendants: false,
          source: _readRequired(
            File('$root/tool/verify_production_tracker.dart'),
            'tool/verify_production_tracker.dart',
            failures,
          ),
        ),
      ];
  if (apkVerifier != null) {
    _requireSinglePattern(
      apkVerifier,
      RegExp(
        r'aster_run_inspector[\s\S]*?'
        r'"\$\{ASTER_BOUNDED_DART\}" --disable-dart-dev[\s\S]*?'
        r'tool/verify_android_release_identity\.dart',
      ),
      'APK verification must enforce committed release identity.',
      failures,
    );
    _requireSinglePattern(
      apkVerifier,
      RegExp(r'--aapt2 "\$\{ASTER_AAPT2\}"'),
      'APK identity verification must use the resolved aapt2 binary.',
      failures,
    );
    _requireSinglePattern(
      apkVerifier,
      RegExp(
        r'"\$\{root\}/scripts/verify-android-native-libraries\.sh"\s*\\\s*\n'
        r'\s*"\$\{apk_path\}"\s*\\\s*\n'
        r'\s*lib\s*\\\s*\n'
        r'\s*apk\s*\\\s*\n'
        r'\s*"\$\{expected_abi\}"',
        multiLine: true,
      ),
      'APK verification must delegate exact ABI ownership to the native '
      'archive boundary.',
      failures,
    );
    if (apkVerifier.contains('unzip -Z1')) {
      failures.add('APK verification must not parse line-oriented ZIP names.');
    }
  }
  final bundleVerifier = _readRequired(
    File('$root/scripts/verify-android-release-bundle.sh'),
    'scripts/verify-android-release-bundle.sh',
    failures,
  );
  final jarSignatureInspector = _readRequired(
    File('$root/scripts/AndroidJarSignatureInspector.java'),
    'scripts/AndroidJarSignatureInspector.java',
    failures,
  );
  if (bundleVerifier != null) {
    _requireSinglePattern(
      bundleVerifier,
      RegExp(
        r'aster_run_inspector[\s\S]*?'
        r'"\$\{ASTER_BOUNDED_DART\}" --disable-dart-dev[\s\S]*?'
        r'tool/verify_android_release_identity\.dart',
      ),
      'Bundle verification must enforce committed release identity.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'--aapt2-proto "\$\{ASTER_AAPT2_PROTO_JAR\}"'),
      'Bundle identity verification must use the resolved aapt2 schema.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'--protobuf "\$\{ASTER_PROTOBUF_JAR\}"'),
      'Bundle identity verification must use the resolved protobuf runtime.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(
        r'"\$\{java_bin\}" scripts/AndroidArchiveEntryExtractor\.java\s*\\\s*\n'
        r'\s*"\$\{bundle_path\}"\s*\\\s*\n'
        r'\s*BundleConfig\.pb\s*\\\s*\n'
        r'\s*"\$\{bundle_config_path\}"\s*\\\s*\n'
        r'\s*16777216',
        multiLine: true,
      ),
      'Bundle verification must safely extract one bounded BundleConfig.pb.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(
        r'scripts/BundleConfigInspector\.java '
        r'"\$\{bundle_config_path\}"',
      ),
      'Bundle configuration inspection must consume only the extracted file.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'^trap cleanup EXIT\s*$', multiLine: true),
      'Bundle verification must install fail-safe temporary-file cleanup.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'^\s*local cleanup_status=0$', multiLine: true),
      'Bundle verification must track cleanup failure independently.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(r'^\s*trap - EXIT HUP INT TERM$', multiLine: true),
      'Bundle verification cleanup must disarm every installed trap.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(
        RegExp.escape(r'((status != 0)) && exit "${status}"'),
        multiLine: true,
      ),
      'Bundle verification must preserve its first qualification failure.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(
        r'"\$\{mktemp_bin\}" -d '
        r'"\$\{TMPDIR:-/tmp\}/aster-aab-config\.XXXXXX"',
      ),
      'Bundle verification must use an isolated owned inspection directory.',
      failures,
    );
    _requireSinglePattern(
      bundleVerifier,
      RegExp(
        r'"\$\{java_bin\}" scripts/AndroidJarSignatureInspector\.java '
        r'"\$\{bundle_path\}"',
      ),
      'Bundle verification must inspect signing coverage for every entry.',
      failures,
    );
    if (bundleVerifier.contains('jarsigner -verify')) {
      failures.add(
        'Bundle verification must not rely on permissive jarsigner status.',
      );
    }
    _requireSinglePattern(
      bundleVerifier,
      RegExp(
        r'"\$\{root\}/scripts/verify-android-native-libraries\.sh"\s*\\\s*\n'
        r'\s*"\$\{bundle_path\}"\s*\\\s*\n'
        r'\s*base/lib\s*\\\s*\n'
        r'\s*aab\s*\\\s*\n'
        r'\s*arm64-v8a,armeabi-v7a,x86_64',
        multiLine: true,
      ),
      'Bundle verification must delegate its exact ABI matrix to the native '
      'archive boundary.',
      failures,
    );
    if (bundleVerifier.contains('unzip -Z1')) {
      failures.add(
        'Bundle verification must not parse line-oriented ZIP names.',
      );
    }
  }
  if (apkSignatureVerifier != null) {
    _requireSinglePattern(
      apkSignatureVerifier,
      RegExp(
        r'"\$\{java_bin\}" scripts/AndroidJarSignatureInspector\.java\s*\\\s*\n'
        r'\s*--signature-evidence\s*\\\s*\n'
        r'\s*"\$\{apk_path\}"',
        multiLine: true,
      ),
      'APK signature verification must inspect v1 evidence through the '
      'structured archive boundary.',
      failures,
    );
    if (apkSignatureVerifier.contains('unzip -Z1')) {
      failures.add(
        'APK signature verification must not parse line-oriented ZIP names.',
      );
    }
  }
  if (nativeLibraryVerifier != null) {
    _requireSinglePattern(
      nativeLibraryVerifier,
      RegExp(
        r'"\$\{java_bin\}" scripts/AndroidNativeLibraryExtractor\.java\s*\\\s*\n'
        r'\s*"\$\{archive_path\}"\s*\\\s*\n'
        r'\s*"\$\{native_root\}"\s*\\\s*\n'
        r'\s*"\$\{temporary_directory\}"\s*\\\s*\n'
        r'\s*"\$\{expected_abis\}"',
        multiLine: true,
      ),
      'Native-library verification must use the path-safe bounded extractor.',
      failures,
    );
    if (nativeLibraryVerifier.contains('unzip ')) {
      failures.add(
        'Native-library verification must not delegate extraction to unzip.',
      );
    }
    _requireSinglePattern(
      nativeLibraryVerifier,
      RegExp(r'^extraction_output="\$\(\{\s*$', multiLine: true),
      'Native-library verification must capture the extractor result.',
      failures,
    );
    _requireSinglePattern(
      nativeLibraryVerifier,
      RegExp(
        RegExp.escape(
          r'[[ "${extraction_output}" =~ ^EXTRACTED_NATIVE_LIBRARIES=([1-9][0-9]*)$ ]]',
        ),
      ),
      'Native-library verification must validate the extractor count exactly.',
      failures,
    );
    _requireSinglePattern(
      nativeLibraryVerifier,
      RegExp(
        RegExp.escape(r'readonly extracted_library_count="${BASH_REMATCH[1]}"'),
      ),
      'Native-library verification must retain the authoritative extractor '
      'count.',
      failures,
    );
    _requireSinglePattern(
      nativeLibraryVerifier,
      RegExp(
        r'aster_capture_inspector[\s\S]*?'
        r'"\$1" "\$3" -mindepth 2 -maxdepth 2 '
        r'-type f -name "\*\.so" -print \|[\s\S]*?'
        r'LC_ALL=C "\$2"',
      ),
      'Native-library verification must materialize one status-bearing exact '
      'inventory.',
      failures,
    );
    _requireSinglePattern(
      nativeLibraryVerifier,
      RegExp(RegExp.escape(r'((library_count == extracted_library_count)) ||')),
      'Native-library verification must inspect every extracted library.',
      failures,
    );
    if (nativeLibraryVerifier.contains('done < <(')) {
      failures.add(
        'Native-library verification must not hide enumeration failure in '
        'process substitution.',
      );
    }
  }
  if (nativeLibraryExtractor != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(r'new ZipFile\(archive\.toFile\(\)\)'),
        failure: 'Native archive extraction must use structured ZIP entries.',
      ),
      (
        pattern: RegExp(r'validateEntryName\(name\)'),
        failure: 'Native archive extraction must validate every entry path.',
      ),
      (
        pattern: RegExp(r'private static final int MAX_ENTRY_COUNT ='),
        failure: 'Native archive extraction must bound archive entry count.',
      ),
      (
        pattern: RegExp(r'private static final long MAX_NATIVE_BYTES ='),
        failure: 'Native archive extraction must bound extracted bytes.',
      ),
      (
        pattern: RegExp(r'librariesByAbi\.keySet\(\)\.equals\(expectedAbis\)'),
        failure: 'Native archive extraction must prove the exact ABI set.',
      ),
      (
        pattern: RegExp(
          r'private static final Set<String> REQUIRED_LIBRARIES =',
        ),
        failure: 'Native archive extraction must prove required libraries.',
      ),
      (
        pattern: RegExp(r'StandardOpenOption\.CREATE_NEW'),
        failure: 'Native archive extraction must not overwrite output paths.',
      ),
    ]) {
      _requireSinglePattern(
        nativeLibraryExtractor,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
  }
  if (archiveEntryExtractor != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(r'new ZipFile\(archive\.toFile\(\)\)'),
        failure: 'Exact archive extraction must use structured ZIP entries.',
      ),
      (
        pattern: RegExp(
          r'Files\.isRegularFile\(archive, LinkOption\.NOFOLLOW_LINKS\)',
        ),
        failure: 'Exact archive extraction must reject non-regular inputs.',
      ),
      (
        pattern: RegExp(r'validateEntryName\(name\)'),
        failure: 'Exact archive extraction must validate every entry path.',
      ),
      (
        pattern: RegExp(r'if \(!entryNames\.add\(name\)\)'),
        failure: 'Exact archive extraction must reject duplicate entries.',
      ),
      (
        pattern: RegExp(r'private static final int MAX_ENTRY_COUNT ='),
        failure: 'Exact archive extraction must bound archive entry count.',
      ),
      (
        pattern: RegExp(r'private static final long MAX_EXPANDED_BYTES ='),
        failure: 'Exact archive extraction must bound declared expanded bytes.',
      ),
      (
        pattern: RegExp(r'size > maximumEntryBytes'),
        failure: 'Exact archive extraction must bound the requested entry.',
      ),
      (
        pattern: RegExp(r'StandardOpenOption\.CREATE_NEW'),
        failure: 'Exact archive extraction must not overwrite output paths.',
      ),
      (
        pattern: RegExp(r'Files\.deleteIfExists\(target\)'),
        failure: 'Exact archive extraction must delete partial output.',
      ),
    ]) {
      _requireSinglePattern(
        archiveEntryExtractor,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
  }
  if (androidReleaseIdentityVerifier != null) {
    _requireSinglePattern(
      androidReleaseIdentityVerifier,
      RegExp(r"import 'bounded_process\.dart';"),
      'Android identity verification must import the bounded process owner.',
      failures,
    );
    _requirePatternCount(
      androidReleaseIdentityVerifier,
      RegExp(r'await runBoundedProcess\('),
      3,
      'Android identity verification must execute exactly three bounded '
      'inspector processes.',
      failures,
    );
    for (final contract in <({RegExp pattern, String label})>[
      (pattern: RegExp(r'workingDirectory:'), label: 'working-directory'),
      (pattern: RegExp(r'maxStdoutBytes:'), label: 'stdout-limit'),
      (pattern: RegExp(r'maxStderrBytes:'), label: 'stderr-limit'),
      (pattern: RegExp(r'timeout:'), label: 'deadline'),
    ]) {
      _requirePatternCount(
        androidReleaseIdentityVerifier,
        contract.pattern,
        3,
        'Every Android identity inspector must own one ${contract.label} '
        'policy.',
        failures,
      );
    }
    if (androidReleaseIdentityVerifier.contains('Process.run(')) {
      failures.add(
        'Android identity verification must not buffer subprocess output with '
        'Process.run.',
      );
    }
    _requireSinglePattern(
      androidReleaseIdentityVerifier,
      RegExp(
        r"'scripts/AndroidArchiveEntryExtractor\.java',\s*"
        r"artifact,\s*"
        r"'base/manifest/AndroidManifest\.xml',\s*"
        r'manifest\.path,\s*'
        r"'16777216',",
        multiLine: true,
      ),
      'AAB identity verification must safely extract one bounded manifest.',
      failures,
    );
    _requireSinglePattern(
      androidReleaseIdentityVerifier,
      RegExp(
        r"'scripts/AndroidManifestInspector\.java',\s*manifest\.path,",
        multiLine: true,
      ),
      'AAB identity inspection must consume only the extracted manifest.',
      failures,
    );
    _requireSinglePattern(
      androidReleaseIdentityVerifier,
      RegExp(r'await temporaryDirectory\.delete\(recursive: true\);'),
      'AAB identity verification must clean its owned temporary directory.',
      failures,
    );
  }
  if (boundedProcess != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(r'Process\.start\('),
        failure: 'Bounded subprocess execution must stream with Process.start.',
      ),
      (
        pattern: RegExp(
          r'_readBoundedUtf8\(\s*process\.stdout,\s*'
          r"streamName: 'stdout',\s*"
          r'maximumBytes: maxStdoutBytes,\s*'
          r'onLimit: requestTermination,\s*'
          r'onDecodedChunk: onStdout,\s*\)',
        ),
        failure: 'Bounded subprocess execution must enforce its stdout limit.',
      ),
      (
        pattern: RegExp(
          r'_readBoundedUtf8\(\s*process\.stderr,\s*'
          r"streamName: 'stderr',\s*"
          r'maximumBytes: maxStderrBytes,\s*'
          r'onLimit: requestTermination,\s*'
          r'onDecodedChunk: onStderr,\s*\)',
        ),
        failure: 'Bounded subprocess execution must enforce its stderr limit.',
      ),
      (
        pattern: RegExp(r'totalBytes > maximumBytes'),
        failure:
            'Bounded subprocess execution must count bytes before capture.',
      ),
      (
        pattern: RegExp(r'utf8\.decoder\.startChunkedConversion\('),
        failure: 'Bounded subprocess output must use strict UTF-8 decoding.',
      ),
      (
        pattern: RegExp(
          r'Future\.wait<Object>\(\[\s*process\.exitCode,\s*'
          r'stdoutFuture,\s*stderrFuture,\s*\],\s*eagerError: true,?\s*'
          r'\)\.timeout\(\s*timeout,',
        ),
        failure: 'Bounded subprocess execution must enforce one deadline.',
      ),
      (
        pattern: RegExp(r'ProcessSignal\.sigkill'),
        failure: 'Bounded subprocess failures must force child termination.',
      ),
      (
        pattern: RegExp(r'ProcessSignal\.sigterm'),
        failure:
            'Bounded subprocess failures must request graceful termination.',
      ),
      (
        pattern: RegExp(
          r'killProcessTree && \(!Platform\.isMacOS && !Platform\.isLinux\)',
        ),
        failure:
            'Process-tree supervision must fail closed on unsupported hosts.',
      ),
      (
        pattern: RegExp(r"killProcessTree \? 'python3' : executable"),
        failure:
            'Descendant-owning commands must use the fixed POSIX supervisor.',
      ),
      (
        pattern: RegExp(
          r"'-I',\s*'-S',\s*'-c',\s*_posixProcessTreeSupervisor,\s*executable,\s*\.\.\.arguments,",
        ),
        failure: 'The POSIX subprocess supervisor must isolate Python and forward positional arguments.',
      ),
      (
        pattern: RegExp(r'if sys.version_info < \(3, 9\):'),
        failure: 'The POSIX subprocess supervisor must reject unsupported Python runtimes.',
      ),
      (
        pattern: RegExp(
          r'start_new_session=True,\s*close_fds=True,\s*pass_fds=\(status_write, gate_read\),',
        ),
        failure: 'The POSIX subprocess supervisor must create an owned session with private descriptors.',
      ),
      (
        pattern: RegExp(
          r'os.getpid\(\) != os.getpgrp\(\) or os.getpid\(\) != os.getsid\(0\)',
        ),
        failure: 'The POSIX subprocess worker must verify its native group and session.',
      ),
      (
        pattern: RegExp(
          r"os.getpgid\(worker.pid\) != worker.pid or os.getsid\(worker.pid\) != worker.pid:[\s\S]*?owned_group = True\s*if read_bytes\(1\) != b'R':",
        ),
        failure: 'The POSIX subprocess supervisor must verify native identity and READY before activation.',
      ),
      (
        pattern: RegExp(
          r'termination_pending = False\s*def request_termination\(signum, frame\):\s*global termination_pending\s*termination_pending = True\s*for name',
        ),
        failure: 'The POSIX subprocess supervisor must latch cancellation without destructive signal handlers.',
      ),
      (
        pattern: RegExp(
          r"activation_attempted = True\s*if os.write\(gate_write, b'G'\) != 1:",
        ),
        failure: 'The POSIX subprocess supervisor must mark activation before its gate write.',
      ),
      (
        pattern: RegExp(
          r'if termination_pending:\s*raise Cancelled\(\)[\s\S]*?select.select\(\[status_read\], \[\], \[\], 0.05\)',
        ),
        failure: 'The POSIX subprocess supervisor must poll cancellation with a finite protocol wait.',
      ),
      (
        pattern: RegExp(
          r"received_bytes > 5[\s\S]*?struct.unpack\('!i', read_bytes\(4\)\)\[0\][\s\S]*?0 <= result <= 255[\s\S]*?read_bytes\(1, eof=True\)",
        ),
        failure: 'The POSIX subprocess supervisor must validate its bounded status record and EOF.',
      ),
      (
        pattern: RegExp(
          r'os.set_inheritable\(status_fd, False\)\s*os.set_inheritable\(gate_fd, False\)',
        ),
        failure: 'The POSIX subprocess worker must close private descriptors on command exec.',
      ),
      (
        pattern: RegExp(
          r'command = subprocess.Popen\(sys.argv\[3:\], close_fds=True\)',
        ),
        failure: 'The POSIX subprocess worker must forward arguments directly with default exec signals.',
      ),
      (
        pattern: RegExp(
          r'select.select\(\[gate_fd\], \[\], \[\], timeout\)[\s\S]*?os.read\(gate_fd, 1\)\s*os.killpg\(os.getpid\(\), signal.SIGKILL\)',
        ),
        failure: 'The POSIX subprocess worker must self-clean on parent control-pipe loss.',
      ),
      (
        pattern: RegExp(
          r'if owned_group and activation_attempted:[\s\S]*?os.killpg\(worker.pid, signal.SIGTERM\)[\s\S]*?time.sleep\(0.25\)[\s\S]*?finally:[\s\S]*?os.killpg\(worker.pid, signal.SIGKILL\)',
        ),
        failure: 'The POSIX subprocess supervisor must clean descendants after normal completion.',
      ),
      (
        pattern: RegExp(
          r'finally:[\s\S]*?for descriptor in \(status_read, status_write, gate_read, gate_write\):[\s\S]*?os.close\(descriptor\)[\s\S]*?worker.wait\(\)',
        ),
        failure: 'The POSIX subprocess supervisor must close liveness descriptors before reaping its anchor.',
      ),
      (
        pattern: RegExp(r'await ensureTerminated\(\);'),
        failure:
            'Bounded subprocess failures must await deterministic cleanup.',
      ),
      (
        pattern: RegExp(r'on ProcessException[\s\S]*ProcessLaunchException'),
        failure: 'Bounded subprocess launch failures must redact arguments.',
      ),
    ]) {
      _requireSinglePattern(
        boundedProcess,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
    if (boundedProcess.contains('Process.run(')) {
      failures.add(
        'Bounded subprocess execution must not use buffered Process.run.',
      );
    }
    if (boundedProcess.contains('allowMalformed: true')) {
      failures.add('Bounded subprocess output must reject malformed UTF-8.');
    }
  }
  if (androidArtifactToolchainResolver != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(r'const _maxAgpModuleMetadataBytes = 1024 \* 1024;'),
        failure: 'AGP module metadata must have an exact 1 MiB byte ceiling.',
      ),
      (
        pattern: RegExp(
          r'final verifiedBytes = _readVerifiedArtifactBytes\(\s*'
          r'metadataFile,[\s\S]*?'
          r'maximumBytes: _maxAgpModuleMetadataBytes,',
        ),
        failure: 'AGP module metadata must be captured under its format-specific ceiling.',
      ),
      (
        pattern: RegExp(r'input\.lengthSync\(\) > maximumBytes'),
        failure: 'Verified metadata capture must reject oversized files before reading.',
      ),
      (
        pattern: RegExp(r'totalBytes > maximumBytes'),
        failure:
            'Verified metadata capture must reject growth while streaming.',
      ),
      (
        pattern: RegExp(
          r'if \(captured\.digest == expected\) return captured\.bytes;',
        ),
        failure: 'AGP metadata parsing must consume only the checksum-verified byte snapshot.',
      ),
      (
        pattern: RegExp(r'jsonDecode\(utf8\.decode\(verifiedBytes\)\)'),
        failure: 'AGP metadata must use strict UTF-8 decoding after checksum verification.',
      ),
    ]) {
      _requireSinglePattern(
        androidArtifactToolchainResolver,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
    if (androidArtifactToolchainResolver.contains(
      'metadataFile.readAsStringSync()',
    )) {
      failures.add(
        'AGP metadata must not bypass bounded verified-byte capture.',
      );
    }
  }
  for (final tool in boundedDartTools) {
    final source = tool.source;
    if (source == null) continue;
    _requireSinglePattern(
      source,
      RegExp(r"import 'bounded_process\.dart';"),
      '${tool.label} must import the bounded process owner.',
      failures,
    );
    _requirePatternCount(
      source,
      RegExp(r'await runBoundedProcess\('),
      1,
      '${tool.label} must invoke exactly one bounded subprocess.',
      failures,
    );
    for (final contract in <({RegExp pattern, String label})>[
      (pattern: RegExp(r'maxStdoutBytes:'), label: 'stdout-limit'),
      (pattern: RegExp(r'maxStderrBytes:'), label: 'stderr-limit'),
      (pattern: RegExp(r'timeout:'), label: 'deadline'),
    ]) {
      _requirePatternCount(
        source,
        contract.pattern,
        1,
        '${tool.label} must own exactly one ${contract.label} policy.',
        failures,
      );
    }
    _requirePatternCount(
      source,
      RegExp(r'killProcessTree:\s*true'),
      tool.ownsDescendants ? 1 : 0,
      tool.ownsDescendants
          ? '${tool.label} must own its complete subprocess tree.'
          : '${tool.label} must not pay for unnecessary process-tree supervision.',
      failures,
    );
    if (RegExp(r'Process\.(?:run|runSync|start|startSync)\(')
        .hasMatch(source)) {
      failures.add(
        '${tool.label} must not invoke Process APIs outside the bounded owner.',
      );
    }
  }
  final trackerTool = boundedDartTools.last.source;
  if (trackerTool != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(r"'ls-files',\s*'-z',"),
        failure: 'Production tracker Git inventory must use NUL framing.',
      ),
      (
        pattern: RegExp(r"output\.endsWith\('\\u0000'\)"),
        failure: 'Production tracker must reject truncated Git inventory.',
      ),
      (
        pattern: RegExp(r"split\('\\u0000'\)"),
        failure: 'Production tracker must parse NUL-framed Git records.',
      ),
      (
        pattern: RegExp(r'!files\.add\(path\)'),
        failure: 'Production tracker must reject duplicate Git paths.',
      ),
      (
        pattern: RegExp(r'value < 0x20 \|\| value == 0x7f'),
        failure: 'Production tracker must reject control-bearing Git paths.',
      ),
    ]) {
      _requireSinglePattern(
        trackerTool,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
  }
  for (final inspector in <({String? source, String name})>[
    (source: manifestInspector, name: 'Manifest'),
    (source: bundleConfigInspector, name: 'BundleConfig'),
  ]) {
    final source = inspector.source;
    if (source == null) continue;
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(r'private static final int MAX_PROTOBUF_BYTES ='),
        failure: '${inspector.name} parsing must bound protobuf input bytes.',
      ),
      (
        pattern: RegExp(
          r'Files\.isRegularFile\(input, LinkOption\.NOFOLLOW_LINKS\)',
        ),
        failure: '${inspector.name} parsing must reject non-regular inputs.',
      ),
      (
        pattern: RegExp(r'CodedInputStream\.newInstance\(input\)'),
        failure: '${inspector.name} parsing must use a bounded coded stream.',
      ),
      (
        pattern: RegExp(r'codedInput\.setSizeLimit\(MAX_PROTOBUF_BYTES\)'),
        failure: '${inspector.name} parsing must enforce its protobuf limit.',
      ),
    ]) {
      _requireSinglePattern(
        source,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
    if (source.contains('ZipFile') || source.contains('ZipEntry')) {
      failures.add(
        '${inspector.name} parsing must not open Android archives directly.',
      );
    }
  }
  if (jarSignatureInspector != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(r'new JarFile\([^;]+, true\)'),
        failure: 'JAR signature inspection must enable entry verification.',
      ),
      (
        pattern: RegExp(r'entry\.getCodeSigners\(\)'),
        failure: 'JAR signature inspection must read every entry signer.',
      ),
      (
        pattern: RegExp(r'hasSignedContent && firstUnsignedEntry != null'),
        failure: 'JAR signature inspection must reject partial signatures.',
      ),
      (
        pattern: RegExp(r'arguments\[0\]\.equals\("--signature-evidence"\)'),
        failure: 'JAR inspection must expose structured signature evidence.',
      ),
      (
        pattern: RegExp(r'private static final int MAX_ENTRY_COUNT ='),
        failure: 'JAR inspection must bound archive entry count.',
      ),
      (
        pattern: RegExp(r'private static final long MAX_EXPANDED_BYTES ='),
        failure: 'JAR inspection must bound expanded archive bytes.',
      ),
    ]) {
      _requireSinglePattern(
        jarSignatureInspector,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
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

  _verifyAsterProductIdentity(root, pubspec, iosProject, failures);

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
        'Gradle $gradleVersion, Android Gradle Plugin $_reviewedAndroidAgp, and '
        'Kotlin $kotlinVersion',
      )) {
    failures.add(
      'docs/DEVELOPMENT.md must document the reviewed Android build chain.',
    );
  }
  if (development != null &&
      compileSdk != null &&
      buildToolsVersion != null &&
      platformToolsVersion != null &&
      !development.contains(
        'Android SDK platform $_reviewedAndroidSdkPlatform, build tools $buildToolsVersion, '
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

  _verifyBoundedShellExecution(root, flutterVersion, failures);
  _verifyProcessApiOwnership(root, failures);

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
  final result = parseGradleVerificationMetadata(contents);
  failures.addAll(result.failures);
  return result.metadata?.artifactCount ?? 0;
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
  _requireSinglePattern(
    gemfile,
    RegExp(
      '^gem "nkf", "${RegExp.escape(_reviewedNkfVersion)}"\\s*\$',
      multiLine: true,
    ),
    'Gemfile must pin NKF $_reviewedNkfVersion exactly for Ruby 4 kconv.',
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
    'gem "nkf", "$_reviewedNkfVersion"',
  ];
  if (activeLines.length != expectedLines.length ||
      activeLines.indexed.any((entry) => entry.$2 != expectedLines[entry.$1])) {
    failures.add(
      'Gemfile must contain only the reviewed RubyGems source and exact '
      'CocoaPods and NKF dependencies.',
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

  for (final (pattern, failure) in <(RegExp, String)>[
    (
      RegExp(
        '^    nkf \\(${RegExp.escape(_reviewedNkfVersion)}\\)\\s*\$',
        multiLine: true,
      ),
      'Gemfile.lock must resolve NKF $_reviewedNkfVersion exactly.',
    ),
    (
      RegExp(
        '^  nkf \\(= ${RegExp.escape(_reviewedNkfVersion)}\\)\\s*\$',
        multiLine: true,
      ),
      'Gemfile.lock must retain the exact NKF dependency constraint.',
    ),
    (
      RegExp(
        '^  nkf \\(${RegExp.escape(_reviewedNkfVersion)}\\) '
        'sha256=$_reviewedNkfSha256\\s*\$',
        multiLine: true,
      ),
      'Gemfile.lock must use the reviewed NKF $_reviewedNkfVersion checksum.',
    ),
  ]) {
    _requireSinglePattern(lock, pattern, failure, failures);
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
  final expectedDependencies = cocoaPodsVersion == null
      ? null
      : <String>[
          'cocoapods (= $cocoaPodsVersion)',
          'nkf (= $_reviewedNkfVersion)',
        ];
  if (expectedDependencies != null &&
      (dependencies == null ||
          dependencies.length != expectedDependencies.length ||
          dependencies.indexed.any(
            (entry) => entry.$2 != expectedDependencies[entry.$1],
          ))) {
    failures.add(
      'Gemfile.lock must contain only the exact CocoaPods and NKF dependencies.',
    );
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

void _requireDerivedIdentity(
  String? contents, {
  required String label,
  required String variable,
  required String releaseVariable,
  required String suffix,
  required List<String> failures,
}) {
  if (contents == null) return;
  _requireSinglePattern(
    contents,
    RegExp(
      '^readonly ${RegExp.escape(variable)}="\\\$\\{'
      '${RegExp.escape(releaseVariable)}\\}\\.${RegExp.escape(suffix)}"\\s*\$',
      multiLine: true,
    ),
    '$label must derive its $suffix identity from $releaseVariable.',
    failures,
  );
}

void _verifyAndroidPerformanceWrapper(
  String contents, {
  required String? benchmark,
  required String? makefile,
  required String? rendererVerifier,
  required List<String> failures,
}) {
  _requireSinglePattern(
    contents,
    RegExp(
      r'^readonly target="integration_test/'
      r'presentation_performance_test\.dart"\s*$',
      multiLine: true,
    ),
    'Android performance wrapper must own the presentation target.',
    failures,
  );
  _requireSinglePattern(
    contents,
    RegExp(
      r'^\s*installed_path="\$\(package_path '
      r'"\$\{profile_package\}"\)" \|\| return 1\s*$',
      multiLine: true,
    ),
    'Android performance wrapper must fail when Profile state inspection '
    'fails.',
    failures,
  );
  for (final query in <({String variable, String package, String label})>[
    (
      variable: 'release_path_before',
      package: 'release_package',
      label: 'pre-run release package',
    ),
    (
      variable: 'debug_path_before',
      package: 'debug_package',
      label: 'pre-run debug package',
    ),
    (
      variable: 'profile_path_after',
      package: 'profile_package',
      label: 'post-run Profile package',
    ),
  ]) {
    _requireSinglePattern(
      contents,
      RegExp(
        '^${RegExp.escape(query.variable)}="\\\$\\(package_path '
        '"\\\$\\{${RegExp.escape(query.package)}\\}"\\)" \\|\\|\\s*\$',
        multiLine: true,
      ),
      'Android performance wrapper must fail explicitly when its ${query.label} '
      'query fails.',
      failures,
    );
  }
  for (final identity in <String>['release', 'debug']) {
    _requireSinglePattern(
      contents,
      RegExp(
        '^\\s*if ! ${identity}_path_after="\\\$\\(package_path '
        '"\\\$\\{${identity}_package\\}"\\)"; then\\s*\$',
        multiLine: true,
      ),
      'Android performance cleanup must distinguish a failed $identity query '
      'from an absent package.',
      failures,
    );
  }
  if (contents.contains('|| true')) {
    failures.add(
      'Android performance wrapper must not mask package-inspection failures.',
    );
  }
  if (benchmark != null) {
    _requireSinglePattern(
      benchmark,
      RegExp(
        r'bool\.fromEnvironment\(\s*'
        r"'ASTER_ISOLATED_PROFILE_BENCHMARK'\s*,\s*\)",
      ),
      'Presentation benchmark must require the wrapper isolation marker.',
      failures,
    );
    _requireSinglePattern(
      benchmark,
      RegExp(r'expect\(\s*_isIsolatedProfileBenchmark,\s*isTrue,'),
      'Presentation benchmark must fail closed outside the owned wrapper.',
      failures,
    );
  }
  for (final option in <String>[
    r'^aster_run_build fvm flutter drive --no-pub \\$',
    r'^  --no-dds \\$',
    r'^  --driver=test_driver/integration_test\.dart \\$',
    r'^  --target="\$\{target\}" \\$',
    r'^  --keep-app-running \\$',
    r'^  --dart-define=ASTER_ISOLATED_PROFILE_BENCHMARK=true \\$',
    r'^  -d "\$\{device_id\}" \\$',
    r'^  --profile$',
  ]) {
    _requireSinglePattern(
      contents,
      RegExp(option, multiLine: true),
      'Android performance wrapper must use the exact isolated Profile drive '
      'command.',
      failures,
    );
  }
  _requireSinglePattern(
    contents,
    RegExp(
      r'^clear_profile_state \|\| fail '
      r'"could not reset the isolated profile package"$',
      multiLine: true,
    ),
    'Android performance wrapper must clear Profile state before measurement.',
    failures,
  );
  _requireSinglePattern(
    contents,
    RegExp(
      r'^aster_run_quick "\$\{root\}/scripts/'
      r'verify-android-performance-renderer\.sh" \\$'
      r'\n  "\$\{adb\}" "\$\{device_id\}"$',
      multiLine: true,
    ),
    'Android performance wrapper must reject software renderers before '
    'measurement.',
    failures,
  );
  if (rendererVerifier != null) {
    _requireSinglePattern(
      rendererVerifier,
      RegExp(r'shell dumpsys SurfaceFlinger'),
      'Android performance renderer verification must inspect SurfaceFlinger.',
      failures,
    );
    _requireSinglePattern(
      rendererVerifier,
      RegExp(r'^readonly maximum_diagnostic_bytes=', multiLine: true),
      'Android performance renderer verification must bound diagnostics.',
      failures,
    );
    _requireSinglePattern(
      rendererVerifier,
      RegExp(
        r'aster_bounded_capture[\s\S]*?'
        r'"\$\{maximum_diagnostic_bytes\}"',
      ),
      'Android performance renderer verification must enforce its byte limit '
      'at the process boundary.',
      failures,
    );
    _requireSinglePattern(
      rendererVerifier,
      RegExp(r'if \(!found && \$0 ~ /\^GLES:/\)'),
      'Android performance renderer verification must retain only the first '
      'GLES backend line.',
      failures,
    );
    _requireSinglePattern(
      rendererVerifier,
      RegExp(r'consumed \+= length\(\$0\) \+ 1'),
      'Android performance renderer verification must count every diagnostic '
      'byte while streaming.',
      failures,
    );
    _requireSinglePattern(
      rendererVerifier,
      RegExp(r'set -o pipefail'),
      'Android performance renderer verification must preserve every pipeline '
      'status.',
      failures,
    );
    if (rendererVerifier.contains('surface_dump=')) {
      failures.add(
        'Android performance renderer verification must not retain the full '
        'SurfaceFlinger diagnostic payload.',
      );
    }
    for (final softwareRenderer in <String>[
      'swiftshader',
      'llvmpipe',
      'lavapipe',
      'softpipe',
      'software\\ rasterizer',
    ]) {
      _requireSinglePattern(
        rendererVerifier,
        RegExp('\\*${RegExp.escape(softwareRenderer)}\\*'),
        'Android performance renderer verification must reject known software '
        'backend $softwareRenderer.',
        failures,
      );
    }
  }
  _requireSinglePattern(
    contents,
    RegExp(r'^\s*if ! clear_profile_state; then\s*$', multiLine: true),
    'Android performance wrapper must verify Profile cleanup.',
    failures,
  );
  _requireSinglePattern(
    contents,
    RegExp(r'^trap cleanup EXIT$', multiLine: true),
    'Android performance wrapper must install deterministic cleanup.',
    failures,
  );
  _requireSinglePattern(
    contents,
    RegExp(
      r'^aster_run_build fvm flutter pub get --enforce-lockfile$',
      multiLine: true,
    ),
    'Android performance wrapper must enforce the committed Pub lock.',
    failures,
  );
  _requireSinglePattern(
    contents,
    RegExp(
      r'readonly built_package="\$\([\s\S]*?'
      r'aster_capture_inspector "\$\{ASTER_AAPT2\}" '
      r'dump packagename "\$\{apk\}"[\s\S]*?\)"',
    ),
    'Android performance wrapper must inspect the exact built APK identity.',
    failures,
  );
  if (makefile != null) {
    _requireSinglePattern(
      makefile,
      RegExp(
        r'^android-presentation-performance-test:\s+verify-generated\s*$\n'
        r'\t\./scripts/run-android-presentation-performance-test\.sh '
        r'"\$\(ANDROID_DEVICE_ID\)"\s*$',
        multiLine: true,
      ),
      'Makefile must expose the owned Android performance wrapper.',
      failures,
    );
  }
}

void _requireMakeTargetPrerequisite(
  String contents, {
  required String target,
  required String prerequisite,
  required List<String> failures,
}) {
  final declarations = RegExp(
    '^${RegExp.escape(target)}[ \\t]*:[ \\t]*([^#\\n]*)(?:#.*)?\$',
    multiLine: true,
  ).allMatches(contents).toList(growable: false);
  if (declarations.length != 1) {
    failures.add('Make target $target must have one unambiguous declaration.');
    return;
  }
  final prerequisites = declarations.single
      .group(1)!
      .trim()
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty)
      .toSet();
  if (!prerequisites.contains(prerequisite)) {
    failures.add('Make target $target must depend directly on $prerequisite.');
  }
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

void _verifyAsterProductIdentity(
  String root,
  String? pubspec,
  String? iosProject,
  List<String> failures,
) {
  _verifyRetiredProductIdentity(root, failures);

  if (pubspec != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(r'^name: aster$', multiLine: true),
        failure: 'pubspec.yaml must identify the Aster package.',
      ),
      (
        pattern: RegExp(r'^description: Aster\b.*$', multiLine: true),
        failure: 'pubspec.yaml must identify Aster as the product.',
      ),
      (
        pattern: RegExp(
          r'^    - assets/brand/aster-mark\.svg$',
          multiLine: true,
        ),
        failure: 'pubspec.yaml must bundle the Aster product mark.',
      ),
    ]) {
      _requireSinglePattern(
        pubspec,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
  }

  final appConstants = _readRequired(
    File('$root/lib/core/constants/app_constants.dart'),
    'lib/core/constants/app_constants.dart',
    failures,
  );
  if (appConstants != null) {
    _requireSinglePattern(
      appConstants,
      RegExp(r"static const String appName = 'Aster';"),
      'Flutter product identity must be exactly Aster.',
      failures,
    );
  }

  final mainSource = _readRequired(
    File('$root/lib/main.dart'),
    'lib/main.dart',
    failures,
  );
  if (mainSource != null) {
    _requireSinglePattern(
      mainSource,
      RegExp(r'class AsterApp extends ConsumerStatefulWidget'),
      'The Flutter application root must be owned by Aster.',
      failures,
    );
  }

  final androidManifest = _readRequired(
    File('$root/android/app/src/main/AndroidManifest.xml'),
    'android/app/src/main/AndroidManifest.xml',
    failures,
  );
  if (androidManifest != null) {
    _requireSinglePattern(
      androidManifest,
      RegExp(r'android:label="Aster"'),
      'The Android application label must be exactly Aster.',
      failures,
    );
  }

  final iosInfo = _readRequired(
    File('$root/ios/Runner/Info.plist'),
    'ios/Runner/Info.plist',
    failures,
  );
  if (iosInfo != null) {
    for (final key in const ['CFBundleDisplayName', 'CFBundleName']) {
      _requireSinglePattern(
        iosInfo,
        RegExp('<key>$key</key>\\s*<string>Aster</string>'),
        'iOS $key must be exactly Aster.',
        failures,
      );
    }
  }
  if (iosProject != null) {
    _requirePatternCount(
      iosProject,
      RegExp(r'ASSETCATALOG_COMPILER_APPICON_NAME = AsterIcon;'),
      3,
      'Every iOS application build mode must use the Aster icon catalog.',
      failures,
    );
  }

  final environment = _readRequired(
    File('$root/lib/core/config/app_environment.dart'),
    'lib/core/config/app_environment.dart',
    failures,
  );
  if (environment != null) {
    _requireSinglePattern(
      environment,
      RegExp(r"String\.fromEnvironment\(\s*'ASTER_NETWORK'"),
      'Wallet build configuration must use the Aster environment namespace.',
      failures,
    );
    if (RegExp(
      r"'(?:bitcoin|utexo)'\s*=>\s*BlockchainEnvironment\.(?:mainnet|signet)",
    ).hasMatch(environment)) {
      failures.add(
        'The app-owned chain parser must not accept asset or protocol names '
        'as blockchain environments.',
      );
    }
  }

  final secureStorage = _readRequired(
    File('$root/lib/core/storage/secure_storage_service.dart'),
    'lib/core/storage/secure_storage_service.dart',
    failures,
  );
  if (secureStorage != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(r"accountName: 'com\.aster\.wallet\.secrets'"),
        failure: 'iOS secure storage must use the Aster wallet namespace.',
      ),
      (
        pattern: RegExp(r"storageNamespace: 'aster_wallet_secrets'"),
        failure: 'Android secure storage must use the Aster wallet namespace.',
      ),
      (
        pattern: RegExp(r'migrateOnAlgorithmChange: true'),
        failure:
            'Android secure storage must permit the pinned plugin to bootstrap '
            'the configured cipher markers inside the isolated Aster namespace.',
      ),
      (
        pattern: RegExp(r'migrateWithBackup: false'),
        failure:
            'Android secure storage must not enable the plugin backup '
            'compatibility path.',
      ),
    ]) {
      _requireSinglePattern(
        secureStorage,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
  }
}

void _verifyRetiredProductIdentity(String root, List<String> failures) {
  const roots = <String>[
    'README.md',
    'pubspec.yaml',
    'lib',
    'android/app/src/main',
    'ios/Runner',
    'assets/brand',
    'docs',
    'scripts',
    'tool',
    'integration_test',
    'test',
  ];
  final retiredStackTokens = <String>[
    String.fromCharCodes(const [103, 100, 107]),
    String.fromCharCodes(const [
      103,
      114,
      101,
      101,
      110,
      97,
      100,
      100,
      114,
      101,
      115,
      115,
    ]),
    String.fromCharCodes(const [
      103,
      114,
      101,
      101,
      110,
      32,
      97,
      100,
      100,
      114,
      101,
      115,
      115,
    ]),
    String.fromCharCodes(const [98, 111, 108, 116, 122]),
    String.fromCharCodes(const [108, 105, 113, 117, 105, 100]),
    String.fromCharCodes(const [108, 98, 116, 99]),
    String.fromCharCodes(const [108, 45, 98, 116, 99]),
  ];
  final retiredStackPatterns = <RegExp>[
    for (final token in retiredStackTokens)
      RegExp('\\b${RegExp.escape(token)}\\b', caseSensitive: false),
    RegExp(
      '\\b${String.fromCharCodes(const [112, 101, 103])}'
      r'[ _-]?(?:in|out)\b',
      caseSensitive: false,
    ),
  ];
  final retiredAppIdentifier = RegExp(
    '${String.fromCharCodes(const [85, 84, 69, 88, 79, 95])}[A-Z0-9_]+'
    '|\\b${String.fromCharCodes(const [117, 116, 101, 120, 111])}[_-]'
    '[a-z0-9_]+'
    '|${String.fromCharCodes(const [85, 116, 101, 120, 111])}(?:App|Icon)\\b',
  );
  final protocolProductCopy = RegExp(
    '\\b${String.fromCharCodes(const [117, 116, 101, 120, 111])}\\b',
    caseSensitive: false,
  );

  final files = <File>[];
  for (final relativeRoot in roots) {
    final entity = FileSystemEntity.typeSync('$root/$relativeRoot');
    if (entity == FileSystemEntityType.file) {
      files.add(File('$root/$relativeRoot'));
    } else if (entity == FileSystemEntityType.directory) {
      files.addAll(
        Directory('$root/$relativeRoot')
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where(_isProductIdentityTextFile),
      );
    }
  }
  files.sort((left, right) => left.path.compareTo(right.path));

  for (final file in files) {
    final relativePath = file.path
        .substring(root.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    if (_isGeneratedProductIdentityFile(relativePath)) continue;
    final source = _readRequired(file, relativePath, failures);
    if (source == null) continue;

    final pathValue = relativePath.toLowerCase();
    final retiredPath = retiredStackPatterns.any(
      (pattern) => pattern.hasMatch(pathValue),
    );
    if (retiredPath || retiredAppIdentifier.hasMatch(relativePath)) {
      failures.add('$relativePath uses a retired wallet product identifier.');
    }

    for (final pattern in retiredStackPatterns) {
      final match = pattern.firstMatch(source);
      if (match == null) continue;
      failures.add(
        '$relativePath:${_lineNumberAt(source, match.start)} contains retired '
        'wallet-stack vocabulary.',
      );
      break;
    }
    // Real shared-stack identities in operational documentation are external
    // infrastructure, not app branding. Match bounded complete identities, then
    // continue inspecting every remaining match in the document.
    final infrastructureSpans = _externalInfrastructureIdentitySpans(
      relativePath,
      source,
    );
    final appIdentifier = retiredAppIdentifier
        .allMatches(source)
        .where(
          (match) => !infrastructureSpans.any(
            (span) => span.start == match.start && span.end >= match.end,
          ),
        )
        .firstOrNull;
    // Cross-workspace recovery notes must retain real sibling repository paths.
    // This exception does not permit retired stack vocabulary or app branding.
    final isWorkspaceHandoff =
        relativePath.startsWith('docs/handoff/') &&
        (relativePath.endsWith('.md') || relativePath.endsWith('.json'));
    if (appIdentifier != null && !isWorkspaceHandoff) {
      failures.add(
        '$relativePath:${_lineNumberAt(source, appIdentifier.start)} uses a '
        'retired app-owned identifier.',
      );
    }
    if (_isProductPresentationSurface(relativePath)) {
      final productCopy = protocolProductCopy.firstMatch(source);
      if (productCopy != null) {
        failures.add(
          '$relativePath:${_lineNumberAt(source, productCopy.start)} presents '
          'the protocol name as Aster product identity.',
        );
      }
    }
  }
}

Iterable<RegExpMatch> _externalInfrastructureIdentitySpans(
  String relativePath,
  String source,
) {
  const operationalDocuments = <String>{
    'docs/PRODUCTION_REFACTOR_TRACKER.md',
    'docs/REGTEST.md',
    'docs/SHARED_WALLET_QUALIFICATION.md',
  };
  if (!operationalDocuments.contains(relativePath)) return const [];
  final prefix = String.fromCharCodes(const [117, 116, 101, 120, 111]);
  final identities = <String>['${prefix}_local', '$prefix-local-stack'];
  return RegExp(
    r'(?<![\p{L}\p{N}_-])(?:'
    '${identities.map(RegExp.escape).join('|')}'
    r')(?![\p{L}\p{N}_-])',
    unicode: true,
  ).allMatches(source);
}

bool _isGeneratedProductIdentityFile(String path) {
  return path.endsWith('/GeneratedPluginRegistrant.java') ||
      path.endsWith('/GeneratedPluginRegistrant.h') ||
      path.endsWith('/GeneratedPluginRegistrant.m') ||
      path.endsWith('/GeneratedPluginRegistrant.swift');
}

bool _isProductIdentityTextFile(File file) {
  final name = file.uri.pathSegments.last;
  if (name == 'Makefile' || name == 'pre-commit' || name == '.fvmrc') {
    return true;
  }
  return const {
    '.dart',
    '.gradle',
    '.java',
    '.json',
    '.kt',
    '.kts',
    '.md',
    '.nix',
    '.plist',
    '.properties',
    '.sh',
    '.storyboard',
    '.swift',
    '.svg',
    '.xcconfig',
    '.xml',
    '.yaml',
    '.yml',
  }.any(name.endsWith);
}

bool _isProductPresentationSurface(String path) {
  return path == 'lib/main.dart' ||
      path.startsWith('lib/shared/screens/') ||
      (path.startsWith('lib/features/') && path.contains('/presentation/')) ||
      path.startsWith('android/app/src/main/') ||
      path.startsWith('ios/Runner/');
}

int _lineNumberAt(String source, int offset) {
  return '\n'.allMatches(source.substring(0, offset)).length + 1;
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

void _requirePatternCount(
  String contents,
  RegExp pattern,
  int expected,
  String message,
  List<String> failures,
) {
  if (pattern.allMatches(contents).length != expected) failures.add(message);
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

void _verifyBoundedShellExecution(
  String root,
  String? flutterVersion,
  List<String> failures,
) {
  final boundary = _readRequired(
    File('$root/scripts/bounded-command.sh'),
    'scripts/bounded-command.sh',
    failures,
  );
  final runner = _readRequired(
    File('$root/tool/run_bounded_command.dart'),
    'tool/run_bounded_command.dart',
    failures,
  );
  if (boundary != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(
          RegExp.escape(r'.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart'),
        ),
        failure: 'Bounded shell execution must pin the repository Dart VM.',
      ),
      (
        pattern: RegExp(
          RegExp.escape(
            r'${_aster_bounded_flutter_root}/bin/cache/dart-sdk/bin/dart',
          ),
        ),
        failure:
            'Bounded shell execution must support the pinned CI Flutter root.',
      ),
      (
        pattern: RegExp(
          r'_aster_bounded_dart="\$\{ASTER_BOUNDED_LOCAL_DART\}"\s*'
          r'if \[\[ ! -x "\$\{_aster_bounded_dart\}" \]\]; then',
        ),
        failure:
            'Bounded shell execution must prefer the repository Flutter VM.',
      ),
      (
        pattern: RegExp(
          r'"\$\{_aster_bounded_flutter_root\}" == /\* &&\s*'
          r'-f "\$\{_aster_bounded_flutter_metadata_file\}"',
        ),
        failure:
            'Bounded shell execution must reject relative CI Flutter roots.',
      ),
      (
        pattern: RegExp(
          RegExp.escape(
            r'${_aster_bounded_flutter_root}/bin/cache/flutter.version.json',
          ),
        ),
        failure:
            'Bounded shell execution must read canonical CI Flutter metadata.',
      ),
      (
        pattern: RegExp(
          r'_aster_bounded_flutter_version_count='
          r'\$\(\(_aster_bounded_flutter_version_count \+ 1\)\)',
        ),
        failure:
            'Bounded shell execution must reject duplicate CI version fields.',
      ),
      (
        pattern: RegExp(
          r'"\$\{_aster_bounded_flutter_version_count\}" == 1 &&\s*'
          r'"\$\{_aster_bounded_flutter_version\}" ==\s*'
          r'"\$\{ASTER_BOUNDED_FLUTTER_VERSION\}"',
        ),
        failure: 'Bounded shell execution must reject malformed or mismatched CI Flutter roots.',
      ),
      (
        pattern: RegExp(
          RegExp.escape(r'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then'),
        ),
        failure: 'Bounded shell execution must reject direct helper execution.',
      ),
      (
        pattern: RegExp(
          r'^\s*unset ASTER_BOUNDED_COMMAND_LOADED$',
          multiLine: true,
        ),
        failure:
            'Bounded shell execution must discard an inherited mutable guard.',
      ),
      (
        pattern: RegExp(
          r'^readonly ASTER_BOUNDED_COMMAND_LOADED=1$',
          multiLine: true,
        ),
        failure:
            'Bounded shell execution must establish one immutable local guard.',
      ),
      (
        pattern: RegExp(r'^\s*--stream-output \\$', multiLine: true),
        failure: 'Bounded shell execution must support live build output.',
      ),
      (
        pattern: RegExp(
          r'^\s*readonly ASTER_QUICK_TIMEOUT_SECONDS=120$',
          multiLine: true,
        ),
        failure: 'Bounded shell quick operations must use a 120-second limit.',
      ),
      (
        pattern: RegExp(
          r'^\s*readonly ASTER_INSPECT_TIMEOUT_SECONDS=600$',
          multiLine: true,
        ),
        failure:
            'Bounded shell artifact inspection must use a 600-second limit.',
      ),
      (
        pattern: RegExp(
          r'^\s*readonly ASTER_BUILD_TIMEOUT_SECONDS=3600$',
          multiLine: true,
        ),
        failure: 'Bounded shell builds must use a 3600-second limit.',
      ),
      (
        pattern: RegExp(r'^\s*aster_bounded_capture\(\) \{$', multiLine: true),
        failure: 'Bounded shell execution must expose one capture boundary.',
      ),
      (
        pattern: RegExp(r'^\s*aster_bounded_stream\(\) \{$', multiLine: true),
        failure: 'Bounded shell execution must expose one streaming boundary.',
      ),
    ]) {
      _requireSinglePattern(
        boundary,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
    _requirePatternCount(
      boundary,
      RegExp(r'aster_bounded_boundary_available \|\| return 69'),
      2,
      'Both bounded shell modes must fail closed when their runner is absent.',
      failures,
    );
    _requirePatternCount(
      boundary,
      RegExp(r'"\$\{ASTER_BOUNDED_DART\}" --disable-dart-dev \\'),
      2,
      'Both bounded shell modes must bypass mutable Dart tooling.',
      failures,
    );
    if (flutterVersion != null) {
      _requireSinglePattern(
        boundary,
        RegExp(
          '^readonly ASTER_BOUNDED_FLUTTER_VERSION='
          '${RegExp.escape(flutterVersion)}\$',
          multiLine: true,
        ),
        'Bounded shell execution must pin Flutter $flutterVersion.',
        failures,
      );
    }
    if (boundary.contains('ASTER_BOUNDED_DART:-') ||
        boundary.contains('ASTER_BOUNDED_RUNNER:-')) {
      failures.add(
        'Bounded shell execution must not accept environment-selected owners.',
      );
    }
    if (boundary.contains('command -v dart') ||
        boundary.contains('which dart')) {
      failures.add(
        'Bounded shell execution must not discover Dart from ambient PATH.',
      );
    }
  }
  if (runner != null) {
    for (final contract in <({RegExp pattern, String failure})>[
      (
        pattern: RegExp(r"import 'bounded_process\.dart';"),
        failure: 'Bounded command CLI must use the sole process owner.',
      ),
      (
        pattern: RegExp(r'const _maximumTimeoutSeconds = 2 \* 60 \* 60;'),
        failure:
            'Bounded command CLI must cap accepted deadlines at two hours.',
      ),
      (
        pattern: RegExp(r'const _maximumOutputBytes = 128 \* 1024 \* 1024;'),
        failure: 'Bounded command CLI must cap each output stream at 128 MiB.',
      ),
      (
        pattern: RegExp(r'killProcessTree: true'),
        failure: 'Bounded command CLI must own the complete process tree.',
      ),
      (
        pattern: RegExp(r'onStdout: invocation\.streamOutput'),
        failure:
            'Bounded command CLI must forward validated stdout on request.',
      ),
      (
        pattern: RegExp(r'onStderr: invocation\.streamOutput'),
        failure:
            'Bounded command CLI must forward validated stderr on request.',
      ),
      (
        pattern: RegExp(r"RegExp\(r'\^\[1-9\]\[0-9\]\*\$'\)"),
        failure:
            'Bounded command CLI must accept only positive decimal bounds.',
      ),
      (
        pattern: RegExp(r'exitCode = _deadlineExitCode;'),
        failure: 'Bounded command CLI must expose a stable deadline status.',
      ),
      (
        pattern: RegExp(r'exitCode = _outputLimitExitCode;'),
        failure: 'Bounded command CLI must expose a stable overflow status.',
      ),
    ]) {
      _requireSinglePattern(
        runner,
        contract.pattern,
        contract.failure,
        failures,
      );
    }
    if (runner.contains('invocation.executable}') ||
        runner.contains('invocation.arguments}')) {
      failures.add(
        'Bounded command CLI watchdog errors must not interpolate child input.',
      );
    }
  }

  final scriptsDirectory = Directory('$root/scripts');
  if (!scriptsDirectory.existsSync()) {
    failures.add('Missing scripts directory for shell ownership verification.');
    return;
  }
  final shellOwners = <({String path, String source})>[];
  final scriptFiles =
      scriptsDirectory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  for (final file in scriptFiles) {
    final path = file.path
        .substring(root.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final source = _readRequired(file, path, failures);
    if (source == null ||
        !RegExp(r'^#!(?:/usr/bin/env bash|/bin/bash|/bin/sh)\r?\n')
            .hasMatch(source) ||
        path == 'scripts/bounded-command.sh') {
      continue;
    }
    shellOwners.add((path: path, source: source));
  }
  if (shellOwners.isEmpty) {
    failures.add('No repository shell entrypoints were found for ownership.');
  }
  for (final owner in shellOwners) {
    final path = owner.path;
    final source = owner.source;
    final ownsBoundary =
        source.contains('bounded-command.sh') ||
        source.contains('android-artifact-toolchain.sh');
    if (!ownsBoundary) {
      failures.add('$path must source the bounded shell execution boundary.');
    }
    if (!RegExp(r'aster_(?:bounded|capture|run)_').hasMatch(source)) {
      failures.add('$path must execute its external work through a bound.');
    }
    if (source.contains('fvm dart run ')) {
      failures.add('$path must not launch Dart through unbounded FVM startup.');
    }
  }
}

void _verifyProcessApiOwnership(String root, List<String> failures) {
  const sourceRoots = <String>['integration_test', 'lib', 'test', 'tool'];
  const owner = 'tool/bounded_process.dart';
  final featureSet = FeatureSet.latestLanguageVersion();
  for (final sourceRoot in sourceRoots) {
    final directory = Directory('$root/$sourceRoot');
    if (!directory.existsSync()) continue;
    final sources =
        directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList(growable: false)
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final source in sources) {
      final relativePath = source.path
          .substring(root.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      if (relativePath == owner) continue;
      final parsed = parseFile(
        path: source.path,
        featureSet: featureSet,
        throwIfDiagnostics: false,
      );
      final visitor = _ProcessInvocationVisitor();
      parsed.unit.accept(visitor);
      for (final invocation in visitor.invocations) {
        final line = parsed.lineInfo.getLocation(invocation.offset).lineNumber;
        failures.add(
          '$relativePath:$line must delegate ${invocation.methodName.name} '
          'to $owner.',
        );
      }
    }
  }
}

final class _ProcessInvocationVisitor extends RecursiveAstVisitor<void> {
  final List<MethodInvocation> invocations = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    if (node.target case SimpleIdentifier(name: 'Process')) {
      if (method == 'run' || method == 'runSync' || method == 'start') {
        invocations.add(node);
      }
    }
    super.visitMethodInvocation(node);
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
