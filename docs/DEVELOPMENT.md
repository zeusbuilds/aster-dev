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

### 2. Install FVM

Install [FVM](https://fvm.app/) globally (once per machine), for example on macOS:

```bash
brew install fvm
```

On other platforms, follow the installation instructions in the FVM docs.

### 3. Setup Project

```bash
make shell
make fvm-setup
make bootstrap
```

## Development Workflow

1. **Enter the development environment:**
   - **Without direnv (manual):**
     ```bash
     make shell
     ```
   - **With direnv (recommended):**
     1. Install direnv (once per machine), for example on macOS:
        ```bash
        brew install direnv
        ```
     2. Add the direnv hook to your shell (e.g. `~/.zshrc`):
        ```bash
        eval "$(direnv hook zsh)"
        ```
     3. In the project root (only once):
        ```bash
        direnv allow
        ```

     After this, simply `cd` into the project directory and direnv will automatically load the Nix dev environment (equivalent to `make shell`), so IDE shortcuts and terminals launched from the project will use the correct toolchain and FVM Flutter.

2. **Ensure FVM Flutter is installed (first time on a machine):**
   ```bash
   make fvm-setup
   ```
   This installs the Flutter version pinned in `.fvmrc` and wires it into the project.

3. **Run the app:**
   ```bash
   make run
   # or
   flutter run   # after FVM is set up, inside `make shell`
   ```

## Available Commands

- `make shell`      - Enter Nix development environment
- `make fvm-setup`  - Install/use Flutter via FVM for this project (uses version from `.fvmrc`)
- `make bootstrap`  - Initial project setup (clean, pub get, build_runner)
- `make clean`      - Clean Flutter build artifacts
- `make build`      - Run build_runner to generate code
- `make watch`      - Run build_runner in watch mode
- `make run`        - Run Flutter app
- `make test`       - Run Flutter tests
- `make help`       - Show all available commands

## Troubleshooting

**Flutter Doctor:**
Check your setup:
```bash
flutter doctor   # after FVM is set up
```

**Clean Build:**
If you encounter build issues:
```bash
make clean
make bootstrap
```

## Development Environment

This project uses [Nix Flakes](https://nixos.wiki/wiki/Flakes) to provide a reproducible development environment for core tooling. The environment includes:

- Flutter 3.35.7
- Dart SDK 3.9.2
- Android SDK with build tools
- Java JDK 21
- CocoaPods (macOS only)

Flutter itself is managed via [FVM](https://fvm.app/) and **pinned per project** using the `.fvmrc` file (currently `flutterSdkVersion: 3.35.7`). This keeps the Flutter version consistent across all developers without relying on the Nix store.

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Nix Flakes Documentation](https://nixos.wiki/wiki/Flakes)
- [Direnv Documentation](https://direnv.net/)
