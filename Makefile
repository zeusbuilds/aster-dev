.PHONY: shell bootstrap clean build watch run test help

# Default target
help:
	@echo "Available commands:"
	@echo "  make shell     - Enter Nix development environment"
	@echo "  make bootstrap - Initial project setup (clean, pub get, build_runner)"
	@echo "  make clean     - Clean Flutter build artifacts"
	@echo "  make build     - Run build_runner to generate code"
	@echo "  make watch     - Run build_runner in watch mode"
	@echo "  make run       - Run Flutter app"
	@echo "  make test      - Run Flutter tests"

# Enter Nix development environment
shell:
	@echo "Entering Nix development environment..."
	nix develop --experimental-features 'nix-command flakes'

# Initial project setup
bootstrap: clean
	@echo "Setting up project..."
	flutter pub get
	@echo "Running build_runner..."
	flutter pub run build_runner build --delete-conflicting-outputs
	@echo "Setup complete!"

# Clean Flutter build artifacts
clean:
	@echo "Cleaning Flutter build..."
	flutter clean

# Run build_runner to generate code
build:
	@echo "Running build_runner..."
	flutter pub run build_runner build --delete-conflicting-outputs

# Run build_runner in watch mode
watch:
	@echo "Running build_runner in watch mode..."
	flutter pub run build_runner watch --delete-conflicting-outputs

# Run Flutter app
run:
	@echo "Running Flutter app..."
	flutter run

# Run Flutter tests
test:
	@echo "Running Flutter tests..."
	flutter test
