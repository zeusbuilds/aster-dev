.PHONY: shell bootstrap clean build watch run test imports format analyze lint fvm-setup help

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
	@echo "  make imports   - Convert and sort import paths"
	@echo "  make format    - Format Dart code"
	@echo "  make analyze   - Run static analysis"
	@echo "  make lint      - Imports, format and analyze (run before commit)"

# Enter Nix development environment
shell:
	@echo "Entering Nix development environment..."
	nix develop --experimental-features 'nix-command flakes'

# Initial project setup
bootstrap: clean
	@echo "Setting up project..."
	fvm flutter pub get
	@echo "Running build_runner..."
	fvm flutter pub run build_runner build --delete-conflicting-outputs
	@echo "Setup complete!"

# Clean Flutter build artifacts
clean:
	@echo "Cleaning Flutter build..."
	fvm flutter clean

# Run build_runner to generate code
build:
	@echo "Running build_runner..."
	fvm flutter pub run build_runner build --delete-conflicting-outputs

# Run build_runner in watch mode
watch:
	@echo "Running build_runner in watch mode..."
	fvm flutter pub run build_runner watch --delete-conflicting-outputs

# Run Flutter app
run:
	@echo "Running Flutter app..."
	fvm flutter run

# Run Flutter tests
test:
	@echo "Running Flutter tests..."
	fvm flutter test

# Convert and sort import paths
imports:
	@echo "Converting import paths..."
	fvm flutter pub run import_path_converter:main
	@echo "Sorting imports..."
	fvm flutter pub run import_sorter:main

# Format Dart code
format:
	@echo "Formatting Dart code..."
	fvm dart format .

# Run static analysis (fail only on errors, not warnings)
analyze:
	@echo "Running static analysis..."
	fvm flutter analyze --no-fatal-warnings --no-fatal-infos

# Imports, format and analyze (for pre-commit / CI)
lint: imports format analyze

# One-time FVM setup for this project
fvm-setup:
	@echo "Setting up Flutter via FVM for this project..."
	@echo "Using version from .fvm/fvm_config.json (if present) or default configured in FVM."
	fvm install
	fvm use
	@echo "FVM setup complete. You can now run 'make bootstrap' and 'make run'."
