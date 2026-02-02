.PHONY: shell bootstrap clean build watch run test format analyze lint fvm-setup help

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
	@echo "  make format    - Format Dart code"
	@echo "  make analyze   - Run static analysis"
	@echo "  make lint     - Format and analyze (run before commit)"

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

# Format Dart code
format:
	@echo "Formatting Dart code..."
	fvm dart format .

# Run static analysis
analyze:
	@echo "Running static analysis..."
	fvm flutter analyze

# Format and analyze (for pre-commit / CI)
lint: format analyze

# One-time FVM setup for this project
fvm-setup:
	@echo "Setting up Flutter via FVM for this project..."
	@echo "Using version from .fvm/fvm_config.json (if present) or default configured in FVM."
	fvm install
	fvm use
	@echo "FVM setup complete. You can now run 'make bootstrap' and 'make run'."
