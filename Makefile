.PHONY: shell dependencies ios-dependencies bootstrap clean build watch run-ios run-android test ios-native-test android-native-test ios-storage-test android-storage-test android-presentation-performance-test format format-check analyze docs verify verify-toolchain verify-architecture verify-design-system verify-barrels verify-generated verify-release-configuration lint prepare-android-release android-release-bundle android-release-apks verify-android-release-bundle verify-android-release-apks verify-android-apk-signature-policy prepare-ios-release ios-release-archive ios-release-ipa verify-ios-export-options verify-ios-release-archive verify-ios-signed-release-archive verify-ios-release-ipa fvm-setup help

BUNDLE_PATH ?= $(CURDIR)/.bundle
BUNDLER_VERSION := 4.0.10
RELEASE_AUDIENCE ?= internal-beta

# Default target
help:
	@echo "Available commands:"
	@echo "  make shell     - Enter Nix development environment"
	@echo "  make dependencies - Resolve the exact committed Pub lockfile"
	@echo "  make ios-dependencies - Install the exact committed CocoaPods bundle"
	@echo "  make fvm-setup - Install/use Flutter via FVM for this project"
	@echo "  make bootstrap - Initial project setup (clean, pub get, build_runner)"
	@echo "  make clean     - Clean Flutter build artifacts"
	@echo "  make build     - Run build_runner to generate code"
	@echo "  make watch     - Run build_runner in watch mode"
	@echo "  make run-ios IOS_SIMULATOR_ID=<id> - Run the iOS Debug app with locked CocoaPods"
	@echo "  make run-android ANDROID_DEVICE_ID=<id> - Run the Android Debug app"
	@echo "  make test      - Run Flutter tests"
	@echo "  make ios-native-test IOS_SIMULATOR_ID=<id> - Run iOS Runner XCTest"
	@echo "  make android-native-test - Run Android app-host unit tests"
	@echo "  make ios-storage-test IOS_SIMULATOR_ID=<id> - Run iOS storage integration tests safely"
	@echo "  make android-storage-test ANDROID_DEVICE_ID=<id> - Run Android storage integration tests safely"
	@echo "  make android-presentation-performance-test ANDROID_DEVICE_ID=<id> - Run the isolated Android Profile performance gate"
	@echo "  make format    - Format Dart code"
	@echo "  make format-check - Verify Dart formatting without changing files"
	@echo "  make analyze   - Run static analysis"
	@echo "  make docs      - Generate and validate Dart API documentation"
	@echo "  make verify    - Verify repository policy and tracker inventory"
	@echo "  make verify-toolchain - Verify Flutter, Android, Nix, and docs alignment"
	@echo "  make verify-architecture - Verify dependency and adapter boundaries"
	@echo "  make verify-design-system - Verify semantic UI design-system boundaries"
	@echo "  make verify-barrels - Verify barrel-export boundaries"
	@echo "  make verify-generated - Regenerate ignored generated sources"
	@echo "  make verify-release-configuration RELEASE_CONFIG=<file> - Validate release defines"
	@echo "  make lint      - Run all repository quality checks"
	@echo "  make prepare-android-release - Clean and verify Release plugin wiring"
	@echo "  make android-release-bundle - Build the Play Store release bundle"
	@echo "  make android-release-apks - Build and verify ABI-split release APKs"
	@echo "  make ios-release-archive - Build and verify an unsigned iOS archive"
	@echo "  make ios-release-ipa IOS_EXPORT_OPTIONS_PLIST=<file> - Export and verify a signed IPA"
	@echo "  make verify-android-release-bundle - Verify the existing Play Store bundle"
	@echo "  make verify-android-release-apks - Verify existing ABI-split APKs"
	@echo "  make verify-android-apk-signature-policy - Fault-test APK signature policy"

# Enter Nix development environment
shell:
	@echo "Entering Nix development environment..."
	nix develop --experimental-features 'nix-command flakes'

# Resolve only the dependency graph committed by the repository.
dependencies:
	python3 -I -S -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 69)'
	fvm flutter pub get --enforce-lockfile

# Keep CocoaPods and its Ruby graph local to this checkout and Gemfile.lock.
ios-dependencies:
	@command -v bundle >/dev/null 2>&1 || (echo "Bundler is required for iOS work" >&2; exit 64)
	@test "$$(bundle --version)" = "$(BUNDLER_VERSION)" || (echo "Bundler $(BUNDLER_VERSION) is required" >&2; exit 64)
	@BUNDLE_FROZEN=true BUNDLE_PATH="$(BUNDLE_PATH)" bundle check >/dev/null 2>&1 || BUNDLE_FROZEN=true BUNDLE_PATH="$(BUNDLE_PATH)" bundle install --jobs 4 --retry 3

# Initial project setup
bootstrap: clean
	@echo "Setting up project..."
	@$(MAKE) --no-print-directory verify-generated
	@echo "Setup complete!"

# Clean Flutter build artifacts
clean:
	@echo "Cleaning Flutter build..."
	fvm flutter clean

# Regenerate code through the same dependency-locked path used by quality gates.
build: verify-generated

# Run build_runner in watch mode
watch: dependencies
	@echo "Running build_runner in watch mode..."
	fvm dart run build_runner watch

# Interactive builds require an explicit platform and device identity.
run-ios: verify-generated ios-dependencies
	@test -n "$(IOS_SIMULATOR_ID)" || (echo "IOS_SIMULATOR_ID is required" >&2; exit 64)
	BUNDLE_FROZEN=true BUNDLE_PATH="$(BUNDLE_PATH)" bundle exec fvm flutter run --no-pub -d "$(IOS_SIMULATOR_ID)"

run-android: verify-generated
	@test -n "$(ANDROID_DEVICE_ID)" || (echo "ANDROID_DEVICE_ID is required" >&2; exit 64)
	fvm flutter run --no-pub -d "$(ANDROID_DEVICE_ID)"

# Run Flutter tests
test: verify-generated
	@echo "Running Flutter tests..."
	fvm flutter test --no-pub

ios-native-test: verify-generated ios-dependencies
	@test -n "$(IOS_SIMULATOR_ID)" || (echo "IOS_SIMULATOR_ID is required" >&2; exit 64)
	BUNDLE_FROZEN=true BUNDLE_PATH="$(BUNDLE_PATH)" bundle exec fvm flutter build ios --simulator --debug --config-only --no-pub
	xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -destination "platform=iOS Simulator,id=$(IOS_SIMULATOR_ID)" -quiet clean test

android-native-test: verify-generated
	fvm flutter build apk --debug --no-pub
	cd android && ./gradlew :app:testDebugUnitTest --no-daemon

# Flutter integration tests temporarily rewrite ignored iOS build settings to a
# disposable listener target. The wrapper restores lib/main.dart on every exit.
ios-storage-test: verify-generated ios-dependencies
	./scripts/run-ios-integration-test.sh integration_test/wallet_storage_security_test.dart "$(IOS_SIMULATOR_ID)"

android-storage-test: verify-generated
	./scripts/run-android-integration-test.sh integration_test/wallet_storage_security_test.dart "$(ANDROID_DEVICE_ID)"

android-presentation-performance-test: verify-generated
	./scripts/run-android-presentation-performance-test.sh "$(ANDROID_DEVICE_ID)"

# Format Dart code
format:
	@echo "Formatting Dart code..."
	fvm dart format .

# Verify formatting without mutating the worktree.
format-check:
	@echo "Checking Dart formatting..."
	fvm dart format --output=none --set-exit-if-changed .

# Run static analysis with all diagnostics fatal.
analyze: verify-generated
	@echo "Running static analysis..."
	fvm flutter analyze --no-pub --fatal-warnings --fatal-infos

# Generate docs into a disposable directory and fail on warnings or bad links.
docs: verify-generated
	@echo "Validating Dart API documentation..."
	fvm dart run tool/verify_dartdoc.dart

# Verify repository invariants that are not covered by the analyzer.
verify: verify-generated
	@echo "Verifying toolchain alignment..."
	fvm dart run tool/verify_toolchain.dart
	@echo "Verifying architecture boundaries..."
	fvm dart run tool/verify_architecture.dart
	@echo "Verifying design-system boundaries..."
	fvm dart run tool/verify_design_system.dart
	@echo "Verifying barrel-export boundaries..."
	fvm dart run tool/verify_barrel_exports.dart
	@echo "Verifying repository governance and CI policy..."
	fvm dart run tool/verify_repository_governance.dart
	@echo "Verifying release configuration contract..."
	fvm dart run tool/verify_release_configuration_contract.dart
	@echo "Verifying production tracker inventory..."
	fvm dart run tool/verify_production_tracker.dart

verify-architecture: verify-generated
	@echo "Verifying architecture boundaries..."
	fvm dart run tool/verify_architecture.dart

verify-toolchain: verify-generated
	@echo "Verifying toolchain alignment..."
	fvm dart run tool/verify_toolchain.dart

verify-design-system: verify-generated
	@echo "Verifying design-system boundaries..."
	fvm dart run tool/verify_design_system.dart

verify-barrels: verify-generated
	@echo "Verifying barrel-export boundaries..."
	fvm dart run tool/verify_barrel_exports.dart

# Generated Dart sources are intentionally ignored and recreated from source.
verify-generated: dependencies
	@echo "Verifying generated Dart sources..."
	fvm dart run build_runner build

# Quality checks suitable for pre-commit and CI.
lint: dependencies format-check verify-generated analyze docs verify

# Release artifacts accept one reviewed non-secret manifest. App/service
# credentials never belong in dart-defines because mobile binaries expose them.
verify-release-configuration:
	@test -n "$(RELEASE_CONFIG)" || (echo "RELEASE_CONFIG is required" >&2; exit 64)
	fvm dart run tool/verify_release_configuration.dart --file "$(RELEASE_CONFIG)" --audience "$(RELEASE_AUDIENCE)"

# Flutter issue 169336 skips release-specific plugin regeneration with
# --no-pub. Clean first so the candidate cannot inherit an earlier variant,
# then prove Pub and plugin wiring did not drift before no-Pub compilation.
prepare-android-release: verify-release-configuration
	fvm flutter clean
	@$(MAKE) --no-print-directory verify-generated
	fvm dart run tool/prepare_android_release.dart

# Google Play performs device-specific delivery from this bundle. Signing and
# application identity still have to be supplied by the release owner.
android-release-bundle: prepare-android-release
	fvm flutter build appbundle --release --target-platform android-arm64,android-x64 --no-pub --dart-define-from-file="$(RELEASE_CONFIG)"
	./scripts/verify-android-release-bundle.sh

# The pinned wallet SDK AAR contains multiple native ABIs. Direct APK delivery
# must therefore use Flutter's ABI splits; --target-platform alone does not
# remove foreign JNI libraries from transitive Android archives.
android-release-apks: prepare-android-release
	fvm flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64 --no-pub --dart-define-from-file="$(RELEASE_CONFIG)"
	./scripts/verify-android-release-apks.sh

verify-android-release-bundle: dependencies
	./scripts/verify-android-release-bundle.sh

verify-android-release-apks: dependencies
	./scripts/verify-android-release-apks.sh

verify-android-apk-signature-policy: dependencies
	./scripts/test-android-apk-signature-policy.sh

# iOS uses the same reviewed release manifest as Android. An unsigned archive
# is build evidence only; public distribution requires the separate signed IPA
# target plus release-owned identifiers, provisioning, and export policy.
prepare-ios-release: verify-release-configuration
	fvm flutter clean
	@$(MAKE) --no-print-directory verify-generated ios-dependencies

ios-release-archive: prepare-ios-release
	BUNDLE_FROZEN=true BUNDLE_PATH="$(BUNDLE_PATH)" bundle exec fvm flutter build ipa --release --no-pub --no-codesign --dart-define-from-file="$(RELEASE_CONFIG)"
	@$(MAKE) --no-print-directory verify-ios-release-archive

ios-release-ipa: prepare-ios-release
	@test -n "$(IOS_EXPORT_OPTIONS_PLIST)" || (echo "IOS_EXPORT_OPTIONS_PLIST is required" >&2; exit 64)
	@$(MAKE) --no-print-directory verify-ios-export-options
	BUNDLE_FROZEN=true BUNDLE_PATH="$(BUNDLE_PATH)" bundle exec fvm flutter build ipa --release --no-pub --export-options-plist="$(IOS_EXPORT_OPTIONS_PLIST)" --dart-define-from-file="$(RELEASE_CONFIG)"
	@$(MAKE) --no-print-directory verify-ios-signed-release-archive verify-ios-release-ipa

verify-ios-export-options: dependencies
	@test -n "$(IOS_EXPORT_OPTIONS_PLIST)" || (echo "IOS_EXPORT_OPTIONS_PLIST is required" >&2; exit 64)
	fvm dart run tool/verify_ios_export_options.dart --file "$(IOS_EXPORT_OPTIONS_PLIST)" --audience "$(RELEASE_AUDIENCE)"

verify-ios-release-archive: dependencies
	fvm dart run tool/verify_ios_release_archive.dart --archive "$(or $(IOS_ARCHIVE_PATH),build/ios/archive/Runner.xcarchive)"

verify-ios-signed-release-archive: dependencies
	fvm dart run tool/verify_ios_release_archive.dart --archive "$(or $(IOS_ARCHIVE_PATH),build/ios/archive/Runner.xcarchive)" --require-signed

verify-ios-release-ipa: dependencies
	fvm dart run tool/verify_ios_release_export.dart --directory "$(or $(IOS_IPA_DIRECTORY),build/ios/ipa)"

# One-time FVM setup for this project
fvm-setup:
	@echo "Setting up Flutter via FVM for this project..."
	@echo "Using the exact Flutter version pinned in .fvmrc."
	fvm install
	fvm use
	@echo "FVM setup complete. Run 'make bootstrap', then an explicit run-ios or run-android target."
