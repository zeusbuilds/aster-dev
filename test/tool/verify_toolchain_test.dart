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
          'bootstrap: clean\n'
          '\t@\$(MAKE) --no-print-directory verify-generated\n'
          'build: verify-generated\n'
          'watch: dependencies\n'
          'run-ios: verify-generated ios-dependencies\n'
          '\tBUNDLE_FROZEN=true BUNDLE_PATH="\$(BUNDLE_PATH)" bundle exec fvm flutter run --no-pub -d "\$(IOS_SIMULATOR_ID)"\n'
          'run-android: verify-generated\n'
          '\tfvm flutter run --no-pub -d "\$(ANDROID_DEVICE_ID)"\n'
          'test: verify-generated\n'
          'ios-native-test: verify-generated ios-dependencies\n'
          '\tBUNDLE_FROZEN=true BUNDLE_PATH="\$(BUNDLE_PATH)" bundle exec fvm flutter build ios --simulator --debug --config-only --no-pub\n'
          'android-native-test: verify-generated\n'
          'ios-storage-test: verify-generated ios-dependencies\n'
          'android-storage-test: verify-generated\n'
          'android-presentation-performance-test: verify-generated\n'
          '\t./scripts/run-android-presentation-performance-test.sh '
          '"\$(ANDROID_DEVICE_ID)"\n'
          'analyze: verify-generated\n'
          'docs: verify-generated\n'
          'verify: verify-generated\n'
          'verify-toolchain: verify-generated\n'
          'verify-architecture: verify-generated\n'
          'verify-design-system: verify-generated\n'
          'verify-barrels: verify-generated\n'
          'verify-generated: dependencies\n'
          '\tfvm dart run build_runner build\n'
          'lint: dependencies verify-generated analyze docs verify\n'
          'prepare-android-release:\n'
          '\tfvm flutter clean\n'
          '\t@\$(MAKE) --no-print-directory verify-generated\n'
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
      'scripts/android-package-state.sh',
      r'''utexo_android_package_paths() {
  set -o pipefail
  [[ "${package_name}" =~ ^[A-Za-z] ]]
  normalized_paths="$({
    "${package_adb}" -s "${package_device_id}" shell pm path \
      "${package_name}" 2>/dev/null |
      awk '
        {
          consumed += length($0) + 1
          if (consumed > 65536) exit 65
          sub(/\r$/, "")
          if ($0 !~ /^package:\/[^[:cntrl:]]+$/) exit 66
        }
      ' |
      LC_ALL=C sort -u
  })"
}''',
    );
    _write(
      repository,
      'scripts/run-android-integration-test.sh',
      'readonly release_package="com.example.utexo"\n'
          'readonly test_package="\${release_package}.debug"\n'
          'source "\${root}/scripts/android-package-state.sh"\n'
          'package_path() {\n'
          '  utexo_android_package_paths "\${adb}" '
          '"\${device_id}" "\$1"\n'
          '}\n'
          'cleanup() {\n'
          '  "\${adb}" -s "\${device_id}" shell am force-stop \\\n'
          '    "\${test_package}" >/dev/null\n'
          '  if ! release_path_after="\$(package_path '
          '"\${release_package}")"; then\n'
          '    cleanup_status=1\n'
          '  fi\n'
          '}\n'
          'trap cleanup EXIT\n'
          'release_path_before="\$(package_path '
          '"\${release_package}")" ||\n'
          '  fail "query failed"\n'
          'test_status=0\n'
          '((test_status == 0)) || exit "\${test_status}"',
    );
    _write(
      repository,
      'scripts/run-android-presentation-performance-test.sh',
      r'''readonly target="integration_test/presentation_performance_test.dart"
readonly release_package="com.example.utexo"
readonly debug_package="${release_package}.debug"
readonly profile_package="${release_package}.profile"
"${root}/scripts/verify-android-performance-renderer.sh" \
  "${adb}" "${device_id}"
source "${root}/scripts/android-package-state.sh"
package_path() {
  utexo_android_package_paths "${adb}" "${device_id}" "$1"
}
clear_profile_state() {
  local installed_path
  installed_path="$(package_path "${profile_package}")" || return 1
}
release_path_before="$(package_path "${release_package}")" ||
  fail "release query failed"
readonly release_path_before
debug_path_before="$(package_path "${debug_package}")" ||
  fail "debug query failed"
readonly debug_path_before
cleanup() {
  if ! clear_profile_state; then
    cleanup_status=1
  fi
  if ! release_path_after="$(package_path "${release_package}")"; then
    cleanup_status=1
  fi
  if ! debug_path_after="$(package_path "${debug_package}")"; then
    cleanup_status=1
  fi
}
trap cleanup EXIT
clear_profile_state || fail "could not reset the isolated profile package"
fvm flutter pub get --enforce-lockfile
fvm flutter drive --no-pub \
  --no-dds \
  --driver=test_driver/integration_test.dart \
  --target="${target}" \
  --keep-app-running \
  --dart-define=UTEXO_ISOLATED_PROFILE_BENCHMARK=true \
  -d "${device_id}" \
  --profile
profile_path_after="$(package_path "${profile_package}")" ||
  fail "profile query failed"
readonly profile_path_after
readonly built_package="$("${UTEXO_AAPT2}" dump packagename "${apk}")"''',
    );
    _write(
      repository,
      'scripts/verify-android-performance-renderer.sh',
      r'''readonly maximum_diagnostic_bytes=$((4 * 1024 * 1024))
renderer_line="$(
  "${adb}" -s "${device_id}" shell dumpsys SurfaceFlinger |
    awk -v maximum="${maximum_diagnostic_bytes}" '
      { consumed += length($0) + 1 }
      { if (consumed > maximum) exit 65 }
      { if (!found && $0 ~ /^GLES:/) { print; found = 1 } }
    '
)" || fail "could not inspect bounded SurfaceFlinger diagnostics"
case "${renderer_normalized}" in
  *swiftshader* | *llvmpipe* | *lavapipe* | *softpipe* | *software\ rasterizer*)
    exit 64
    ;;
esac''',
    );
    _write(
      repository,
      'integration_test/presentation_performance_test.dart',
      "const _isIsolatedProfileBenchmark = bool.fromEnvironment(\n"
          "  'UTEXO_ISOLATED_PROFILE_BENCHMARK',\n"
          ');\n'
          'void main() {\n'
          '  expect(\n'
          '    _isIsolatedProfileBenchmark,\n'
          '    isTrue,\n'
          "    reason: 'Use the wrapper.',\n"
          '  );\n'
          '}',
    );
    _write(
      repository,
      'scripts/run-ios-integration-test.sh',
      r'''readonly release_bundle="com.example.utexo"
readonly test_bundle="${release_bundle}.debug"
readonly bundler_version="4.0.10"
export BUNDLE_FROZEN=true
bundle_path() {
  local bundle_identifier="$1"
  local escaped_identifier installed_apps path
  installed_apps="$(xcrun simctl listapps "${simulator_id}" 2>/dev/null)" ||
    return 1
  printf '%s\n' "${installed_apps}" | plutil -lint - >/dev/null 2>&1 ||
    return 1
  escaped_identifier="${bundle_identifier//./\\.}"
  path="$(printf '%s\n' "${installed_apps}" |
    plutil -extract "${escaped_identifier}.Path" raw -)"
}
release_path_before="$(bundle_path "${release_bundle}")" ||
  fail "release query failed"
readonly release_path_before
bundle check >/dev/null 2>&1 ||
  fail "gems unavailable"
bundle exec fvm flutter pub get --enforce-lockfile
bundle exec fvm flutter build ios --simulator --debug --no-pub
bundle exec fvm flutter test --no-pub target
release_path_after="$(bundle_path "${release_bundle}")" ||
  fail "post-run release query failed"
readonly release_path_after
readonly built_test_app="${root}/build/ios/iphonesimulator/Runner.app"
plutil -extract CFBundleIdentifier raw -- "${built_test_app}/Info.plist"
xcrun simctl install "${simulator_id}" "${built_test_app}"
local restored_app="${root}/build/ios/iphonesimulator/Runner.app"
xcrun simctl install "${simulator_id}" "${restored_app}"
test_path_after="$(bundle_path "${test_bundle}")" ||
  fail "debug query failed"
readonly test_path_after
release_path_after_install="$(bundle_path "${release_bundle}")" ||
  fail "post-install release query failed"
readonly release_path_after_install
fail "the isolated debug bundle was not installed"''',
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
          '  --aapt2 "\${UTEXO_AAPT2}"\n'
          './scripts/verify-android-native-libraries.sh \\\n'
          '  "\${apk_path}" \\\n'
          '  lib \\\n'
          '  apk \\\n'
          '  "\${expected_abi}"',
    );
    _write(
      repository,
      'scripts/verify-android-release-bundle.sh',
      'fvm dart run tool/verify_android_release_identity.dart \\\n'
          '  --bundle "\${bundle_path}" \\\n'
          '  --aapt2-proto "\${UTEXO_AAPT2_PROTO_JAR}" \\\n'
          '  --protobuf "\${UTEXO_PROTOBUF_JAR}"\n'
          'trap cleanup EXIT\n'
          'mktemp -d "\${TMPDIR:-/tmp}/utexo-aab-config.XXXXXX"\n'
          'java scripts/AndroidArchiveEntryExtractor.java \\\n'
          '  "\${bundle_path}" \\\n'
          '  BundleConfig.pb \\\n'
          '  "\${bundle_config_path}" \\\n'
          '  16777216\n'
          'scripts/BundleConfigInspector.java "\${bundle_config_path}"\n'
          'java scripts/AndroidJarSignatureInspector.java '
          '"\${bundle_path}"\n'
          './scripts/verify-android-native-libraries.sh \\\n'
          '  "\${bundle_path}" \\\n'
          '  base/lib \\\n'
          '  aab \\\n'
          '  arm64-v8a,armeabi-v7a,x86_64',
    );
    _write(
      repository,
      'scripts/verify-android-apk-signature.sh',
      'java scripts/AndroidJarSignatureInspector.java \\\n'
          '  --signature-evidence \\\n'
          '  "\${apk_path}"',
    );
    _write(
      repository,
      'scripts/verify-android-native-libraries.sh',
      r'''extraction_output="$({
  java scripts/AndroidNativeLibraryExtractor.java \
    "${archive_path}" \
    "${native_root}" \
    "${temporary_directory}" \
    "${expected_abis}"
})"
[[ "${extraction_output}" =~ ^EXTRACTED_NATIVE_LIBRARIES=([1-9][0-9]*)$ ]]
readonly extracted_library_count="${BASH_REMATCH[1]}"
readonly library_inventory="${temporary_directory}/.native-library-inventory"
if ! find "${temporary_directory}" -mindepth 2 -maxdepth 2 \
  -type f -name '*.so' -print | LC_ALL=C sort >"${library_inventory}"; then
  exit 1
fi
library_count=1
((library_count == extracted_library_count)) ||
  exit 1''',
    );
    _write(
      repository,
      'scripts/AndroidArchiveEntryExtractor.java',
      'new ZipFile(archive.toFile());\n'
          'Files.isRegularFile(archive, LinkOption.NOFOLLOW_LINKS);\n'
          'validateEntryName(name);\n'
          'if (!entryNames.add(name)) {}\n'
          'private static final int MAX_ENTRY_COUNT = 1;\n'
          'private static final long MAX_EXPANDED_BYTES = 1;\n'
          'if (size > maximumEntryBytes) {}\n'
          'StandardOpenOption.CREATE_NEW;\n'
          'Files.deleteIfExists(target);',
    );
    _write(
      repository,
      'scripts/AndroidManifestInspector.java',
      'private static final int MAX_PROTOBUF_BYTES = 1;\n'
          'Files.isRegularFile(input, LinkOption.NOFOLLOW_LINKS);\n'
          'CodedInputStream.newInstance(input);\n'
          'codedInput.setSizeLimit(MAX_PROTOBUF_BYTES);',
    );
    _write(
      repository,
      'scripts/BundleConfigInspector.java',
      'private static final int MAX_PROTOBUF_BYTES = 1;\n'
          'Files.isRegularFile(input, LinkOption.NOFOLLOW_LINKS);\n'
          'CodedInputStream.newInstance(input);\n'
          'codedInput.setSizeLimit(MAX_PROTOBUF_BYTES);',
    );
    _write(
      repository,
      'scripts/AndroidNativeLibraryExtractor.java',
      'new ZipFile(archive.toFile());\n'
          'validateEntryName(name);\n'
          'private static final int MAX_ENTRY_COUNT = 1;\n'
          'private static final long MAX_NATIVE_BYTES = 1;\n'
          'librariesByAbi.keySet().equals(expectedAbis);\n'
          'private static final Set<String> REQUIRED_LIBRARIES = Set.of();\n'
          'StandardOpenOption.CREATE_NEW;',
    );
    _write(
      repository,
      'scripts/AndroidJarSignatureInspector.java',
      'new JarFile(archive.toFile(), true);\n'
          'entry.getCodeSigners();\n'
          'if (hasSignedContent && firstUnsignedEntry != null) {}\n'
          'arguments[0].equals("--signature-evidence");\n'
          'private static final int MAX_ENTRY_COUNT = 1;\n'
          'private static final long MAX_EXPANDED_BYTES = 1;',
    );
    _write(
      repository,
      'tool/verify_android_release_identity.dart',
      "import 'bounded_process.dart';\n"
          'await runBoundedProcess(\n'
          "  'aapt2', const [],\n"
          '  workingDirectory: root, maxStdoutBytes: 1,\n'
          '  maxStderrBytes: 1, timeout: deadline);\n'
          'await runBoundedProcess(\n'
          "  'java', const [],\n"
          '  workingDirectory: root, maxStdoutBytes: 1,\n'
          '  maxStderrBytes: 1, timeout: deadline);\n'
          'await runBoundedProcess(\n'
          "  'java', const [],\n"
          '  workingDirectory: root, maxStdoutBytes: 1,\n'
          '  maxStderrBytes: 1, timeout: deadline);\n'
          "'scripts/AndroidArchiveEntryExtractor.java',\n"
          'artifact,\n'
          "'base/manifest/AndroidManifest.xml',\n"
          'manifest.path,\n'
          "'16777216',\n"
          "'scripts/AndroidManifestInspector.java',\n"
          'manifest.path,\n'
          'await temporaryDirectory.delete(recursive: true);',
    );
    _write(
      repository,
      'tool/bounded_process.dart',
      "const supervisor = r'''\n"
          'set -m\n'
          'set +m\n'
          '"\$@" >&3 2>&4\n'
          'owned_status=\$?\n'
          'while :; do /bin/sleep 3600; done &\n'
          'kill -TERM -- "-\$owned_pid"\n'
          'kill -KILL -- "-\$owned_pid"\n'
          'trap - HUP INT TERM\n'
          'stop_owned_groups\n'
          'exit "\$status"\n'
          "''';\n"
          'killProcessTree && (!Platform.isMacOS && !Platform.isLinux);\n'
          "killProcessTree ? '/bin/bash' : executable;\n"
          "'--noprofile', '--norc', '-p', '-c',\n"
          "_posixProcessTreeSupervisor, 'utexo-bounded-process',\n"
          'executable, ...arguments,\n'
          'Process.start(\n'
          '_readBoundedUtf8(\n'
          '  process.stdout,\n'
          "  streamName: 'stdout',\n"
          '  maximumBytes: maxStdoutBytes,\n'
          '  onLimit: requestTermination,\n'
          ');\n'
          '_readBoundedUtf8(\n'
          '  process.stderr,\n'
          "  streamName: 'stderr',\n"
          '  maximumBytes: maxStderrBytes,\n'
          '  onLimit: requestTermination,\n'
          ');\n'
          'totalBytes > maximumBytes;\n'
          'utf8.decode(output.takeBytes());\n'
          'Future.wait<Object>([\n'
          '  process.exitCode,\n'
          '  stdoutFuture,\n'
          '  stderrFuture,\n'
          '], eagerError: true).timeout(timeout, onTimeout: fail);\n'
          'ProcessSignal.sigterm;\n'
          'ProcessSignal.sigkill;\n'
          'await ensureTerminated();\n'
          'on ProcessException { throw const ProcessLaunchException(); }',
    );
    _write(
      repository,
      'tool/resolve_android_artifact_toolchain.dart',
      'const _maxAgpModuleMetadataBytes = 1024 * 1024;\n'
          'final verifiedBytes = _readVerifiedArtifactBytes(\n'
          '  metadataFile,\n'
          '  maximumBytes: _maxAgpModuleMetadataBytes,\n'
          ');\n'
          'if (input.lengthSync() > maximumBytes) {}\n'
          'if (totalBytes > maximumBytes) {}\n'
          'if (captured.digest == expected) return captured.bytes;\n'
          'jsonDecode(utf8.decode(verifiedBytes));',
    );
    for (final path in <String>[
      'tool/verify_dartdoc.dart',
      'tool/prepare_android_release.dart',
    ]) {
      _write(
        repository,
        path,
        "import 'bounded_process.dart';\n"
        'await runBoundedProcess(command, const [],\n'
        '  killProcessTree: true,\n'
        '  maxStdoutBytes: 1, maxStderrBytes: 1, timeout: deadline);',
      );
    }
    _write(
      repository,
      'tool/verify_production_tracker.dart',
      "import 'bounded_process.dart';\n"
          'await runBoundedProcess(command, const [],\n'
          '  maxStdoutBytes: 1, maxStderrBytes: 1, timeout: deadline);\n'
          "const ['ls-files', '-z', '--cached'];\n"
          "output.endsWith('\\u0000');\n"
          "output.split('\\u0000');\n"
          '!files.add(path);\n'
          'value < 0x20 || value == 0x7f;',
    );
    for (final relativePath in <String>[
      'scripts/android-artifact-toolchain.sh',
      'scripts/android-package-state.sh',
      'scripts/bounded-command.sh',
      'scripts/git-hooks/pre-commit',
      'scripts/install-git-hooks.sh',
      'scripts/run-android-integration-test.sh',
      'scripts/run-android-presentation-performance-test.sh',
      'scripts/run-ios-integration-test.sh',
      'scripts/test-android-apk-signature-policy.sh',
      'scripts/verify-android-apk-signature.sh',
      'scripts/verify-android-native-libraries.sh',
      'scripts/verify-android-performance-renderer.sh',
      'scripts/verify-android-release-apks.sh',
      'scripts/verify-android-release-bundle.sh',
      'tool/bounded_process.dart',
      'tool/run_bounded_command.dart',
    ]) {
      final source = File('${Directory.current.path}/$relativePath');
      _write(
        repository,
        relativePath,
        source.readAsStringSync().replaceAll(
          'com.example.asterdev',
          'com.example.utexo',
        ),
      );
    }
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
            '"\${xcrun_bin}" simctl install '
                '"\${simulator_id}" "\${built_test_app}"\n',
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

  test('rejects a non-isolated Android performance command', () {
    final script = File(
      '${repository.path}/scripts/'
      'run-android-presentation-performance-test.sh',
    );
    script.writeAsStringSync(
      script
          .readAsStringSync()
          .replaceFirst(
            'readonly profile_package="\${release_package}.profile"',
            'readonly profile_package="\${release_package}.debug"',
          )
          .replaceFirst('  --no-dds \\\n', '')
          .replaceFirst(
            'clear_profile_state || fail '
                '"could not reset the isolated profile package"\n',
            '',
          )
          .replaceFirst(
            '"\${root}/scripts/verify-android-performance-renderer.sh" \\\n'
                '  "\${adb}" "\${device_id}"\n',
            '',
          )
          .replaceFirst('trap cleanup EXIT\n', ''),
    );
    final makefile = File('${repository.path}/Makefile');
    makefile.writeAsStringSync(
      makefile.readAsStringSync().replaceFirst(
        'android-presentation-performance-test: verify-generated\n'
            '\t./scripts/run-android-presentation-performance-test.sh '
            '"\$(ANDROID_DEVICE_ID)"\n',
        '',
      ),
    );
    _write(
      repository,
      'integration_test/presentation_performance_test.dart',
      'void main() {}',
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
        contains('must derive its profile identity'),
        contains('must use the exact isolated Profile drive command'),
        contains('must clear Profile state before measurement'),
        contains('must reject software renderers before measurement'),
        contains('must install deterministic cleanup'),
        contains('must require the wrapper isolation marker'),
        contains('must fail closed outside the owned wrapper'),
        contains('Makefile must expose the owned Android performance wrapper'),
      ]),
    );
  });

  test('rejects masked platform discovery and partial native evidence', () {
    final androidPerformance = File(
      '${repository.path}/scripts/'
      'run-android-presentation-performance-test.sh',
    );
    androidPerformance.writeAsStringSync(
      androidPerformance.readAsStringSync().replaceFirst(
        r'''utexo_android_package_paths "${adb}" "${device_id}" "$1"''',
        r'''printf 'package:/unvalidated.apk\n' || true''',
      ),
    );
    final androidPackageState = File(
      '${repository.path}/scripts/android-package-state.sh',
    );
    final weakenedPackageState = androidPackageState
        .readAsStringSync()
        .replaceFirst('  set -o pipefail\n', '')
        .replaceFirst('          consumed += length(\$0) + 1\n', '')
        .replaceFirst(
          r'''if ($0 !~ /^package:\/[^[:cntrl:]]+$/) exit 66''',
          'if (false) exit 66',
        );
    androidPackageState.writeAsStringSync(weakenedPackageState);
    _write(repository, 'scripts/verify-android-performance-renderer.sh', r'''surface_dump="$("${adb}" -s "${device_id}" shell dumpsys SurfaceFlinger)"
renderer_line="$(printf '%s\n' "${surface_dump}" | grep -m 1 '^GLES:')"
case "${renderer_normalized}" in
  *swiftshader* | *llvmpipe* | *lavapipe* | *softpipe* | *software\ rasterizer*)
    exit 64
    ;;
esac''');
    final iosIntegration = File(
      '${repository.path}/scripts/run-ios-integration-test.sh',
    );
    iosIntegration.writeAsStringSync(
      iosIntegration.readAsStringSync().replaceFirst(
        r'''"$1" simctl listapps "$2" >"${temporary_file}"''',
        r'''"$1" simctl get_app_container "$2" "$6" >"${temporary_file}" || true''',
      ),
    );
    final nativeVerifier = File(
      '${repository.path}/scripts/verify-android-native-libraries.sh',
    );
    final incompleteNativeVerifier = nativeVerifier
        .readAsStringSync()
        .replaceFirst(
          '((library_count == extracted_library_count)) ||',
          '((library_count > 0)) ||',
        );
    nativeVerifier.writeAsStringSync(
      '$incompleteNativeVerifier\n'
      r'''done < <(find "${temporary_directory}" -name '*.so')''',
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
        contains('must delegate package discovery'),
        contains('must not mask package-inspection failures'),
        contains('must preserve every pipeline failure'),
        contains('must account for every input byte'),
        contains('must reject malformed package-manager output'),
        contains('must bound diagnostics'),
        contains('must enforce its byte limit at the process boundary'),
        contains('must retain only the first GLES backend line'),
        contains('must count every diagnostic byte while streaming'),
        contains('must preserve every pipeline status'),
        contains('must not retain the full SurfaceFlinger diagnostic payload'),
        contains('status-bearing bounded simctl boundary'),
        contains('must not infer installation state from get_app_container'),
        contains('must not mask simulator or bundle-inspection failures'),
        contains('must inspect every extracted library'),
        contains('must not hide enumeration failure in process substitution'),
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

  test('rejects every standalone Make preparation bypass', () {
    final makefile = File('${repository.path}/Makefile');
    var contents = makefile.readAsStringSync();
    const contracts = <String, String>{
      'verify-generated': 'dependencies',
      'watch': 'dependencies',
      'build': 'verify-generated',
      'run-ios': 'verify-generated',
      'run-android': 'verify-generated',
      'test': 'verify-generated',
      'ios-native-test': 'verify-generated',
      'android-native-test': 'verify-generated',
      'ios-storage-test': 'verify-generated',
      'android-storage-test': 'verify-generated',
      'android-presentation-performance-test': 'verify-generated',
      'analyze': 'verify-generated',
      'docs': 'verify-generated',
      'verify': 'verify-generated',
      'verify-toolchain': 'verify-generated',
      'verify-architecture': 'verify-generated',
      'verify-design-system': 'verify-generated',
      'verify-barrels': 'verify-generated',
      'lint': 'verify-generated',
    };
    for (final contract in contracts.entries) {
      contents = _withoutMakePrerequisite(
        contents,
        target: contract.key,
        prerequisite: contract.value,
      );
    }
    contents = contents
        .replaceFirst('\tfvm dart run build_runner build\n', '')
        .replaceFirst(
          '\t@\$(MAKE) --no-print-directory verify-generated\n',
          '\t@\$(MAKE) --no-print-directory dependencies\n',
        );
    makefile.writeAsStringSync(contents);

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        for (final contract in contracts.entries)
          contains(
            'Make target ${contract.key} must depend directly on '
            '${contract.value}.',
          ),
        contains('exactly one canonical generated-source build command'),
        contains('must clean before invoking canonical generated-source'),
      ]),
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
            '\t@\$(MAKE) --no-print-directory verify-generated\n',
        '\t@\$(MAKE) --no-print-directory verify-generated\n'
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
        'Android Release preparation must clean, regenerate from the exact '
        'lock, and then run the guarded plugin tool in order.',
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

  test('rejects incomplete AAB signature ownership', () {
    _write(
      repository,
      'scripts/verify-android-release-bundle.sh',
      'fvm dart run tool/verify_android_release_identity.dart \\\n'
          '  --bundle "\${bundle_path}" \\\n'
          '  --aapt2-proto "\${UTEXO_AAPT2_PROTO_JAR}" \\\n'
          '  --protobuf "\${UTEXO_PROTOBUF_JAR}"\n'
          'jarsigner -verify "\${bundle_path}"',
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
        contains('inspect signing coverage for every entry'),
        contains('must not rely on permissive jarsigner status'),
      ]),
    );
  });

  test('rejects line-oriented Android archive security decisions', () {
    for (final path in <String>[
      'scripts/verify-android-release-apks.sh',
      'scripts/verify-android-release-bundle.sh',
      'scripts/verify-android-apk-signature.sh',
    ]) {
      final file = File('${repository.path}/$path');
      file.writeAsStringSync('${file.readAsStringSync()}\nunzip -Z1 archive');
    }

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('APK verification must not parse line-oriented ZIP names'),
        contains('Bundle verification must not parse line-oriented ZIP names'),
        contains(
          'APK signature verification must not parse line-oriented ZIP names',
        ),
      ]),
    );
  });

  test('rejects an unbounded native archive extraction bypass', () {
    _write(
      repository,
      'scripts/verify-android-native-libraries.sh',
      'unzip archive.zip',
    );
    _write(
      repository,
      'scripts/AndroidNativeLibraryExtractor.java',
      'new ZipFile(archive.toFile());',
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
        contains('must use the path-safe bounded extractor'),
        contains('must not delegate extraction to unzip'),
        contains('must validate every entry path'),
        contains('must bound archive entry count'),
        contains('must bound extracted bytes'),
        contains('must prove the exact ABI set'),
        contains('must prove required libraries'),
        contains('must not overwrite output paths'),
      ]),
    );
  });

  test('rejects unbounded Android bundle protobuf inspection', () {
    _write(
      repository,
      'scripts/verify-android-release-bundle.sh',
      'fvm dart run tool/verify_android_release_identity.dart\n'
          'scripts/BundleConfigInspector.java "\${bundle_path}"\n'
          'java scripts/AndroidJarSignatureInspector.java '
          '"\${bundle_path}"\n'
          './scripts/verify-android-native-libraries.sh \\\n'
          '  "\${bundle_path}" \\\n'
          '  base/lib \\\n'
          '  aab \\\n'
          '  arm64-v8a,armeabi-v7a,x86_64',
    );
    _write(
      repository,
      'tool/verify_android_release_identity.dart',
      "'scripts/AndroidManifestInspector.java', artifact,",
    );
    _write(
      repository,
      'scripts/AndroidArchiveEntryExtractor.java',
      'new ZipFile(archive.toFile());',
    );
    _write(
      repository,
      'scripts/AndroidManifestInspector.java',
      'new ZipFile(bundle);',
    );
    _write(
      repository,
      'scripts/BundleConfigInspector.java',
      'new ZipFile(bundle);',
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
        contains('safely extract one bounded BundleConfig.pb'),
        contains('consume only the extracted file'),
        contains('fail-safe temporary-file cleanup'),
        contains('safely extract one bounded manifest'),
        contains('consume only the extracted manifest'),
        contains('clean its owned temporary directory'),
        contains('Exact archive extraction must reject non-regular inputs'),
        contains('Exact archive extraction must validate every entry path'),
        contains('Manifest parsing must bound protobuf input bytes'),
        contains('Manifest parsing must not open Android archives directly'),
        contains('BundleConfig parsing must bound protobuf input bytes'),
        contains(
          'BundleConfig parsing must not open Android archives directly',
        ),
      ]),
    );
  });

  test('rejects buffered or incompletely bounded identity subprocesses', () {
    _write(
      repository,
      'tool/verify_android_release_identity.dart',
      "import 'bounded_process.dart';\n"
          'await Process.run(aapt2, const []);\n'
          'await Process.run(java, const []);\n'
          'await Process.run(java, const []);\n'
          "'scripts/AndroidArchiveEntryExtractor.java',\n"
          'artifact,\n'
          "'base/manifest/AndroidManifest.xml',\n"
          'manifest.path,\n'
          "'16777216',\n"
          "'scripts/AndroidManifestInspector.java',\n"
          'manifest.path,\n'
          'await temporaryDirectory.delete(recursive: true);',
    );
    _write(
      repository,
      'tool/bounded_process.dart',
      'Process.run(executable, arguments);\n'
          'utf8.decode(output.takeBytes(), allowMalformed: true);',
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
        contains('execute exactly three bounded inspector processes'),
        contains('must not buffer subprocess output with Process.run'),
        contains('must stream with Process.start'),
        contains('must enforce its stdout limit'),
        contains('must enforce its stderr limit'),
        contains('must count bytes before capture'),
        contains('must enforce one deadline'),
        contains('must force child termination'),
        contains('must request graceful termination'),
        contains('must ignore shell startup code'),
        contains('must reserve the owned group until status capture'),
        contains('must clean descendants after normal completion'),
        contains('launch failures must redact arguments'),
        contains('must not use buffered Process.run'),
        contains('must reject malformed UTF-8'),
      ]),
    );
  });

  test('rejects shell-boundary and process-owner bypasses', () {
    final boundary = File('${repository.path}/scripts/bounded-command.sh');
    boundary.writeAsStringSync(
      boundary
          .readAsStringSync()
          .replaceFirst(
            '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart',
            '/usr/bin/dart',
          )
          .replaceFirst(
            r'${_utexo_bounded_flutter_root}/bin/cache/dart-sdk/bin/dart',
            '/usr/bin/dart',
          )
          .replaceFirst(
            'readonly UTEXO_BOUNDED_FLUTTER_VERSION=3.47.0',
            'readonly UTEXO_BOUNDED_FLUTTER_VERSION=3.46.0',
          )
          .replaceFirst(
            r'_utexo_bounded_dart="${UTEXO_BOUNDED_LOCAL_DART}"',
            r'_utexo_bounded_dart="${FLUTTER_ROOT}/bin/dart"',
          )
          .replaceFirst(
            r'"${_utexo_bounded_flutter_root}" == /* &&',
            r'-n "${_utexo_bounded_flutter_root}" &&',
          )
          .replaceFirst(
            r'_utexo_bounded_flutter_version="$(<"${_utexo_bounded_flutter_version_file}")"',
            '_utexo_bounded_flutter_version=3.47.0',
          )
          .replaceFirst(
            r'"${_utexo_bounded_flutter_version}" ==',
            r'-n "${_utexo_bounded_flutter_version}" &&',
          )
          .replaceFirst(
            'readonly UTEXO_BOUNDED_COMMAND_LOADED=1',
            'readonly UTEXO_BOUNDED_COMMAND_LOADED=1\ncommand -v dart',
          )
          .replaceFirst(
            r'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then',
            r'if [[ "${BASH_SOURCE[0]}" == "disabled" ]]; then',
          )
          .replaceFirst(
            '  unset UTEXO_BOUNDED_COMMAND_LOADED',
            '  : # inherited guard left trusted',
          )
          .replaceFirst(
            'readonly UTEXO_BOUNDED_COMMAND_LOADED=1',
            'UTEXO_BOUNDED_COMMAND_LOADED=1',
          )
          .replaceFirst('readonly UTEXO_BUILD_TIMEOUT_SECONDS=3600', ''),
    );
    final runner = File('${repository.path}/tool/run_bounded_command.dart');
    runner.writeAsStringSync(
      runner.readAsStringSync().replaceFirst(
        'killProcessTree: true',
        'killProcessTree: false',
      ),
    );
    final hook = File('${repository.path}/scripts/git-hooks/pre-commit');
    hook.writeAsStringSync(
      hook.readAsStringSync().replaceFirst(
        'source "\${expected_root}/scripts/bounded-command.sh"',
        '',
      ),
    );
    final bundleVerifier = File(
      '${repository.path}/scripts/verify-android-release-bundle.sh',
    );
    bundleVerifier.writeAsStringSync(
      bundleVerifier
          .readAsStringSync()
          .replaceFirst('  local cleanup_status=0\n', '')
          .replaceFirst('  trap - EXIT HUP INT TERM', '  trap - EXIT')
          .replaceFirst(r'  ((status != 0)) && exit "${status}"', ''),
    );
    _write(
      repository,
      'test/unbounded_process_test.dart',
      "import 'dart:io';\n"
          'Future<void> main() async {\n'
          "  await Process.run('tool', const <String>[]);\n"
          '}\n',
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
        contains('must pin the repository Dart VM'),
        contains('must support the pinned CI Flutter root'),
        contains('must prefer the repository Flutter VM'),
        contains('must reject relative CI Flutter roots'),
        contains('must read the CI Flutter version file'),
        contains('must reject mismatched CI Flutter roots'),
        contains('must pin Flutter 3.47.0'),
        contains('must not discover Dart from ambient PATH'),
        contains('must reject direct helper execution'),
        contains('must discard an inherited mutable guard'),
        contains('must establish one immutable local guard'),
        contains('builds must use a 3600-second limit'),
        contains('CLI must own the complete process tree'),
        contains('pre-commit must source the bounded shell execution boundary'),
        contains('must track cleanup failure independently'),
        contains('cleanup must disarm every installed trap'),
        contains('must preserve its first qualification failure'),
        contains('must delegate run to tool/bounded_process.dart'),
      ]),
    );
  });

  test('rejects unbounded Dart tools and line-framed Git inventory', () {
    for (final path in <String>[
      'tool/verify_dartdoc.dart',
      'tool/prepare_android_release.dart',
      'tool/verify_production_tracker.dart',
    ]) {
      _write(repository, path, 'await Process.run(command, const []);');
    }

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('Dartdoc verification must import the bounded process owner'),
        contains('Dartdoc verification must invoke exactly one bounded'),
        contains('Dartdoc verification must not invoke Process APIs'),
        contains('Android Release preparation must import the bounded'),
        contains('Android Release preparation must invoke exactly one bounded'),
        contains('Android Release preparation must not invoke Process APIs'),
        contains('Dartdoc verification must own its complete subprocess tree'),
        contains(
          'Android Release preparation must own its complete subprocess tree',
        ),
        contains('Production tracker verification must import the bounded'),
        contains('Production tracker verification must invoke exactly one'),
        contains('Production tracker verification must not invoke Process'),
        contains('Git inventory must use NUL framing'),
        contains('must reject truncated Git inventory'),
        contains('must parse NUL-framed Git records'),
        contains('must reject duplicate Git paths'),
        contains('must reject control-bearing Git paths'),
      ]),
    );
  });

  test('rejects missing descendant ownership on process-tree tools', () {
    for (final path in <String>[
      'tool/verify_dartdoc.dart',
      'tool/prepare_android_release.dart',
    ]) {
      final file = File('${repository.path}/$path');
      file.writeAsStringSync(
        file.readAsStringSync().replaceFirst('  killProcessTree: true,\n', ''),
      );
    }

    final result = _verify(
      repository,
      flutterVersionMetadata,
      flutterExtension,
      flutterGradleUtils,
    );

    expect(
      result.failures,
      containsAll(<Matcher>[
        contains('Dartdoc verification must own its complete subprocess tree'),
        contains(
          'Android Release preparation must own its complete subprocess tree',
        ),
      ]),
    );
  });

  test('rejects unbounded or checksum-detached AGP metadata parsing', () {
    _write(
      repository,
      'tool/resolve_android_artifact_toolchain.dart',
      'final decoded = jsonDecode(metadataFile.readAsStringSync());',
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
        contains('must have an exact 1 MiB byte ceiling'),
        contains('must be captured under its format-specific ceiling'),
        contains('must reject oversized files before reading'),
        contains('must reject growth while streaming'),
        contains('consume only the checksum-verified byte snapshot'),
        contains('strict UTF-8 decoding after checksum verification'),
        contains('must not bypass bounded verified-byte capture'),
      ]),
    );
  });

  test('rejects Android integration without fail-safe cleanup', () {
    _write(
      repository,
      'scripts/run-android-integration-test.sh',
      'readonly release_package="com.example.utexo"\n'
          'readonly test_package="\${release_package}.debug"',
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
        contains('install fail-safe EXIT cleanup'),
        contains('stop only its debug package'),
        contains('preserve the drive failure'),
      ]),
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

String _withoutMakePrerequisite(
  String contents, {
  required String target,
  required String prerequisite,
}) {
  final declaration = RegExp(
    '^${RegExp.escape(target)}\\s*:\\s*([^\\n]*)\$',
    multiLine: true,
  );
  final matches = declaration.allMatches(contents).toList(growable: false);
  if (matches.length != 1) {
    throw StateError('Expected one Make target declaration for $target.');
  }
  final prerequisites = matches.single
      .group(1)!
      .trim()
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty && value != prerequisite)
      .join(' ');
  return contents.replaceRange(
    matches.single.start,
    matches.single.end,
    '$target:${prerequisites.isEmpty ? '' : ' $prerequisites'}',
  );
}

File _write(Directory root, String path, String contents) {
  final file = File('${root.path}/$path');
  file.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}
