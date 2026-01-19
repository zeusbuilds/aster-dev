# Development Setup

This guide will help you set up the Aster development environment.

## First-Time Setup

### 1. Install Nix (if not already installed)

**macOS:**
```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Or using Homebrew:
```bash
brew install nix
```

**Linux:**
```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

After installation, restart your terminal.

### 2. Setup Project

```bash
make shell
make bootstrap
```

## Development Workflow

1. **Enter the development environment:**
   ```bash
   make shell
   ```
   Or use direnv for automatic activation:
   ```bash
   brew install direnv  # macOS
   direnv allow
   ```

2. **Run the app:**
   ```bash
   make run
   # or
   flutter run
   ```

## Available Commands

- `make shell` - Enter Nix development environment
- `make bootstrap` - Initial project setup (clean, pub get, build_runner)
- `make clean` - Clean Flutter build artifacts
- `make build` - Run build_runner to generate code
- `make watch` - Run build_runner in watch mode
- `make run` - Run Flutter app
- `make test` - Run Flutter tests
- `make help` - Show all available commands

## Troubleshooting

**iOS Build Permission Errors:**
If you encounter permission errors during iOS builds, run:
```bash
fix_build_permissions
```

**Flutter Doctor:**
Check your setup:
```bash
flutter doctor
```

**Clean Build:**
If you encounter build issues:
```bash
make clean
make bootstrap
```

## Development Environment

This project uses [Nix Flakes](https://nixos.wiki/wiki/Flakes) to provide a reproducible development environment. The environment includes:

- Flutter 3.35.7 (pinned)
- Dart SDK 3.9.2
- Android SDK with build tools
- Java JDK 21
- CocoaPods (macOS only)

All dependencies are managed by Nix, ensuring consistent builds across different machines and operating systems.

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Nix Flakes Documentation](https://nixos.wiki/wiki/Flakes)
- [Direnv Documentation](https://direnv.net/)
