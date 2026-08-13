.PHONY: shell bootstrap clean build watch run test ios-storage-test format format-check analyze docs verify verify-architecture verify-barrels verify-generated lint android-release-bundle android-release-apks verify-android-release-bundle verify-android-release-apks fvm-setup help

# Default target
help:
	@echo "Available commands:"
	@echo "  make shell     - Enter Nix development environment"
	@echo "  make fvm-setup - Install/use Flutter via FVM for this project"
	@echo "  make bootstrap - Initial project setup (clean, pub get, build_runner)"
	@echo "  make clean     - Clean Flutter build artifacts"
	@echo "  make build     - Run build_runner to generate code"
	@echo "  make watch     - Run build_runner in watch mode"
	@echo "  make run       - Run Flutter app"
	@echo "  make test      - Run Flutter tests"
	@echo "  make ios-storage-test IOS_SIMULATOR_ID=<id> - Run iOS storage integration tests safely"
	@echo "  make format    - Format Dart code"
	@echo "  make format-check - Verify Dart formatting without changing files"
	@echo "  make analyze   - Run static analysis"
	@echo "  make docs      - Generate and validate Dart API documentation"
	@echo "  make verify    - Verify repository policy and tracker inventory"
	@echo "  make verify-architecture - Verify dependency and adapter boundaries"
	@echo "  make verify-barrels - Verify barrel-export boundaries"
	@echo "  make verify-generated - Regenerate ignored generated sources"
	@echo "  make lint      - Run all repository quality checks"
	@echo "  make android-release-bundle - Build the Play Store release bundle"
	@echo "  make android-release-apks - Build and verify ABI-split release APKs"
	@echo "  make verify-android-release-bundle - Verify the existing Play Store bundle"
	@echo "  make verify-android-release-apks - Verify existing ABI-split APKs"

# Enter Nix development environment
shell:
	@echo "Entering Nix development environment..."
	nix develop --experimental-features 'nix-command flakes'

# Initial project setup
bootstrap: clean
	@echo "Setting up project..."
	fvm flutter pub get
	@echo "Running build_runner..."
	fvm dart run build_runner build
	@echo "Setup complete!"

# Clean Flutter build artifacts
clean:
	@echo "Cleaning Flutter build..."
	fvm flutter clean

# Run build_runner to generate code
build:
	@echo "Running build_runner..."
	fvm dart run build_runner build

# Run build_runner in watch mode
watch:
	@echo "Running build_runner in watch mode..."
	fvm dart run build_runner watch

# Run Flutter app
run:
	@echo "Running Flutter app..."
	fvm flutter run

# Run Flutter tests
test:
	@echo "Running Flutter tests..."
	fvm flutter test

# Flutter integration tests temporarily rewrite ignored iOS build settings to a
# disposable listener target. The wrapper restores lib/main.dart on every exit.
ios-storage-test:
	./scripts/run-ios-integration-test.sh integration_test/wallet_storage_security_test.dart "$(IOS_SIMULATOR_ID)"

# Format Dart code
format:
	@echo "Formatting Dart code..."
	fvm dart format .

# Verify formatting without mutating the worktree.
format-check:
	@echo "Checking Dart formatting..."
	fvm dart format --output=none --set-exit-if-changed .

# Run static analysis with all diagnostics fatal.
analyze:
	@echo "Running static analysis..."
	fvm flutter analyze --fatal-warnings --fatal-infos

# Generate docs into a disposable directory and fail on warnings or bad links.
docs:
	@echo "Validating Dart API documentation..."
	fvm dart run tool/verify_dartdoc.dart

# Verify repository invariants that are not covered by the analyzer.
verify:
	@echo "Verifying architecture boundaries..."
	fvm dart run tool/verify_architecture.dart
	@echo "Verifying barrel-export boundaries..."
	fvm dart run tool/verify_barrel_exports.dart
	@echo "Verifying production tracker inventory..."
	fvm dart run tool/verify_production_tracker.dart

verify-architecture:
	@echo "Verifying architecture boundaries..."
	fvm dart run tool/verify_architecture.dart

verify-barrels:
	@echo "Verifying barrel-export boundaries..."
	fvm dart run tool/verify_barrel_exports.dart

# Generated Dart sources are intentionally ignored and recreated from source.
verify-generated:
	@echo "Verifying generated Dart sources..."
	fvm dart run build_runner build

# Quality checks suitable for pre-commit and CI.
lint: format-check verify-generated analyze docs verify

# Google Play performs device-specific delivery from this bundle. Signing and
# application identity still have to be supplied by the release owner.
android-release-bundle:
	fvm flutter build appbundle --release
	./scripts/verify-android-release-bundle.sh

# The pinned wallet SDK AAR contains multiple native ABIs. Direct APK delivery
# must therefore use Flutter's ABI splits; --target-platform alone does not
# remove foreign JNI libraries from transitive Android archives.
android-release-apks:
	fvm flutter build apk --release --split-per-abi
	./scripts/verify-android-release-apks.sh

verify-android-release-bundle:
	./scripts/verify-android-release-bundle.sh

verify-android-release-apks:
	./scripts/verify-android-release-apks.sh

# One-time FVM setup for this project
fvm-setup:
	@echo "Setting up Flutter via FVM for this project..."
	@echo "Using the exact Flutter version pinned in .fvmrc."
	fvm install
	fvm use
	@echo "FVM setup complete. You can now run 'make bootstrap' and 'make run'."
